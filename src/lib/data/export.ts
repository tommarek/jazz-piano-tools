/**
 * Data export and import.
 *
 * There is no server and no account, so this file is the only way somebody's
 * practice history leaves their phone — for a backup, or to move to a new
 * device. `reviews` is append-only and everything else can be rebuilt from it.
 */

import { db } from '$lib/db';
import { getSettings } from './settings';

export interface ExportPayload {
	exportedAt: string;
	version: number;
	settings: unknown;
	cards: unknown[];
	cardState: unknown[];
	reviews: unknown[];
	sessions: unknown[];
	dailyStats: unknown[];
}

export async function buildExport(): Promise<ExportPayload> {
	const conn = await db();
	return {
		exportedAt: new Date().toISOString(),
		version: 1,
		settings: await getSettings(),
		cards: await conn.all('SELECT * FROM cards'),
		cardState: await conn.all('SELECT * FROM card_state'),
		reviews: await conn.all('SELECT * FROM reviews'),
		sessions: await conn.all('SELECT * FROM sessions'),
		dailyStats: await conn.all('SELECT * FROM daily_stats')
	};
}

/** Triggers a file download in the browser or the WebView. */
export async function downloadExport(): Promise<void> {
	const payload = await buildExport();
	const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = `voicings-${new Date().toISOString().slice(0, 10)}.json`;
	document.body.appendChild(a);
	a.click();
	a.remove();
	URL.revokeObjectURL(url);
}

/**
 * Replaces everything with the contents of an export. Card rows are left to the
 * catalogue sync so that importing an old backup into a newer app keeps the
 * cards the newer app knows about — and anything the payload carries for a card
 * this build has dropped goes with them.
 */
export async function importExport(payload: ExportPayload): Promise<{ reviews: number }> {
	validateExport(payload);
	const conn = await db();

	// The wipe lives inside the same transaction as the inserts. This file
	// replaces the only copy of somebody's practice history, and a payload that
	// fails half way — a truncated backup, a row the schema rejects — must leave
	// them with what they had rather than with nothing. (resetAll() opens no
	// transaction of its own; its DELETEs are inlined rather than called so the
	// non-reentrant conn.tx is not entered twice.)
	let imported = 0;
	await conn.tx(async () => {
		await conn.exec(`
			DELETE FROM reviews;
			DELETE FROM card_state;
			DELETE FROM sessions;
			DELETE FROM daily_stats;
			DELETE FROM settings;
		`);
		for (const row of payload.cardState as Record<string, unknown>[]) {
			await insert(conn, 'card_state', row);
		}
		for (const row of payload.reviews as Record<string, unknown>[]) {
			await insert(conn, 'reviews', row);
		}
		for (const row of payload.sessions as Record<string, unknown>[]) {
			await insert(conn, 'sessions', row);
		}
		for (const row of payload.dailyStats as Record<string, unknown>[]) {
			await insert(conn, 'daily_stats', row);
		}
		// A backup written before a drill was cut still carries its reviews, and
		// nothing downstream would ever remove them: syncCatalogue's purge walks
		// the `cards` table, which no longer holds those ids, so the rows would
		// sit there forever feeding the LIKE-matched chain median and the stage
		// gates with a drill that no longer exists.
		await conn.exec(`
			DELETE FROM reviews WHERE card_id NOT IN (SELECT id FROM cards);
			DELETE FROM card_state WHERE card_id NOT IN (SELECT id FROM cards);
		`);
		// What survived, not what the file carried: the purge above can take a
		// whole cut drill's history with it, and a backup of 100 reviews that
		// restored 60 must not be reported as 100.
		imported = (await conn.get<{ n: number }>('SELECT COUNT(*) AS n FROM reviews'))?.n ?? 0;
		for (const [key, value] of Object.entries(payload.settings ?? {})) {
			await conn.run(
				`INSERT INTO settings (key, value) VALUES (?, ?)
				 ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
				[key, JSON.stringify(value)]
			);
		}
	});
	await conn.persist();
	return { reviews: imported };
}

/**
 * Everything the import will read, checked before the database is touched at
 * all. The version stamp alone is not evidence of a whole file: any JSON that
 * happens to say `"version": 1` used to get as far as the wipe and then throw
 * on the first missing table, and the settings screen reported that as a bare
 * "Import failed".
 */
function validateExport(payload: ExportPayload): void {
	if (payload === null || typeof payload !== 'object') throw new Error('Not a Comp export');
	if (payload.version !== 1) throw new Error(`Unsupported export version ${payload.version}`);
	for (const table of ['cards', 'cardState', 'reviews', 'sessions', 'dailyStats'] as const) {
		if (!Array.isArray(payload[table])) throw new Error(`Export is missing ${table}`);
	}
	const settings = payload.settings;
	if (settings === null || typeof settings !== 'object' || Array.isArray(settings)) {
		throw new Error('Export is missing settings');
	}
}

/**
 * What an import is allowed to write, per table — the SCHEMA columns, listed
 * again here because the statement below is built from the file's own object
 * keys. Without this the payload chooses the SQL: a key of
 * `card_id) VALUES ('x',0,0,0,0); DELETE FROM card_state; --` is valid JSON and
 * both drivers run every statement they are handed. Unknown keys are dropped
 * rather than rejected, so a backup from a build with an extra column still
 * restores everything this schema does have.
 */
const IMPORTABLE_COLUMNS = {
	card_state: [
		'card_id',
		'due',
		'stability',
		'difficulty',
		'elapsed_days',
		'scheduled_days',
		'learning_steps',
		'reps',
		'lapses',
		'state',
		'last_review',
		'median_response_ms',
		'consecutive_correct',
		'mastery'
	],
	reviews: [
		'id',
		'card_id',
		'ts',
		'grade',
		'response_ms',
		'correct',
		'answer_given',
		'session_id',
		'mode'
	],
	sessions: ['id', 'started_at', 'ended_at', 'card_count', 'mode'],
	daily_stats: ['date', 'reviews', 'correct', 'median_response_ms', 'minutes']
} as const;

async function insert(
	conn: Awaited<ReturnType<typeof db>>,
	table: keyof typeof IMPORTABLE_COLUMNS,
	row: Record<string, unknown>
) {
	const allowed: readonly string[] = IMPORTABLE_COLUMNS[table];
	const cols = Object.keys(row).filter((c) => allowed.includes(c));
	if (cols.length === 0) return;
	const placeholders = cols.map(() => '?').join(', ');
	await conn.run(
		`INSERT OR REPLACE INTO ${table} (${cols.join(', ')}) VALUES (${placeholders})`,
		cols.map((c) => row[c] ?? null)
	);
}
