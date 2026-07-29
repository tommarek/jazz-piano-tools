/**
 * Opening the database and keeping the card catalogue up to date.
 *
 * One shared connection per app run, opened lazily on first use, because
 * nothing can touch the database until the platform is known.
 */

import { Capacitor } from '@capacitor/core';
import type { Db } from './driver';
import { buildCatalogue, renderCard } from '$lib/music/cards';

let handle: Promise<Db> | null = null;

export function isNative(): boolean {
	return Capacitor.isNativePlatform();
}

/**
 * tx() on both drivers is non-reentrant — a nested BEGIN throws. Serialising
 * here, at the single shared connection, means *every* caller queues
 * (reviews, settings, gate auto-unlock, export/import) instead of each write
 * path needing its own chain.
 *
 * Only conn.tx queues. Both drivers hold one connection, so a bare run() that
 * lands while somebody's BEGIN is open runs inside that transaction and shares
 * its fate — which is why every write in the app goes through tx(), even the
 * single-statement ones that look like they need no atomicity of their own.
 */
function serialiseTx(conn: Db): Db {
	let txChain: Promise<unknown> = Promise.resolve();
	const rawTx = conn.tx.bind(conn);
	conn.tx = <T>(fn: () => Promise<T>): Promise<T> => {
		const run = txChain.then(() => rawTx(fn));
		txChain = run.catch(() => {});
		return run;
	};
	return conn;
}

async function open(): Promise<Db> {
	const db = serialiseTx(
		isNative()
			? await (await import('./native')).openNativeDb()
			: await (await import('./wasm')).openWasmDb()
	);
	await syncCatalogue(db);
	return db;
}

/** The shared connection. Safe to call from anywhere, any number of times. */
export function db(): Promise<Db> {
	if (!handle) handle = open();
	return handle;
}

/**
 * Point the app at a specific connection. Only for tests — it lets the unit
 * suite drive the real SQL against an in-memory database instead of mocking it.
 */
export async function useDb(conn: Db): Promise<void> {
	const wrapped = serialiseTx(conn);
	handle = Promise.resolve(wrapped);
	await syncCatalogue(wrapped);
}

/**
 * Insert catalogue cards that are not in the table yet, leaving existing rows
 * alone. This is how the deck grows across app updates without detaching
 * anybody's review history from their cards.
 */
export async function syncCatalogue(conn: Db, now = Date.now()): Promise<number> {
	const existing = await conn.all<{ id: string; root_pitch_class: number }>(
		'SELECT id, root_pitch_class FROM cards'
	);
	const storedPc = new Map(existing.map((r) => [r.id, r.root_pitch_class]));
	const catalogue = buildCatalogue();
	const missing = catalogue.filter((spec) => !storedPc.has(spec.id));
	// Backfill: root_pitch_class is derived display metadata (heatmap bucket),
	// so when a render fix changes it — e.g. vl ii-V cards moving from the
	// dominant's root to the card's key — existing rows follow the code.
	const drifted = catalogue
		.map((spec) => ({ spec, pc: renderCard(spec).rootPitchClass }))
		.filter(({ spec, pc }) => storedPc.has(spec.id) && storedPc.get(spec.id) !== pc);
	if (missing.length === 0 && drifted.length === 0) return 0;

	await conn.tx(async () => {
		for (const spec of missing) {
			const view = renderCard(spec);
			await conn.run(
				`INSERT OR IGNORE INTO cards
				 (id, type, root, quality, voicing_type, key_center, variant, transition,
				  root_pitch_class, created_at)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
				[
					spec.id,
					spec.type,
					'root' in spec ? spec.root : null,
					'quality' in spec ? spec.quality : null,
					'shellType' in spec ? spec.shellType : null,
					'key' in spec ? spec.key : null,
					'variant' in spec ? spec.variant : null,
					'transition' in spec ? spec.transition : null,
					view.rootPitchClass,
					now
				]
			);
		}
		for (const { spec, pc } of drifted) {
			await conn.run('UPDATE cards SET root_pitch_class = ? WHERE id = ?', [pc, spec.id]);
		}
	});
	await conn.persist();
	return missing.length;
}

/** Wipes all progress. Used by the in-app reset and by the test harness. */
export async function resetAll(): Promise<void> {
	const conn = await db();
	// Through conn.tx, not bare: a plain exec() resolving while somebody else's
	// BEGIN is open would execute inside *their* transaction and be committed or
	// rolled back with it. Only conn.tx queues on the serialised chain.
	await conn.tx(async () => {
		await conn.exec(`
			DELETE FROM reviews;
			DELETE FROM card_state;
			DELETE FROM sessions;
			DELETE FROM daily_stats;
			DELETE FROM settings;
		`);
	});
	await conn.persist();
}
