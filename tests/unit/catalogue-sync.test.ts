/**
 * The catalogue sync runs on every launch, and its purge is the one code path
 * in the app that deletes review history without anybody asking it to. It has
 * to remove exactly the cards this build no longer generates and nothing else:
 * a `buildCatalogue()` that silently returned a subset — an early return, a
 * changed id shape — would take somebody's practice with it, irreversibly,
 * because there is no server and no second copy.
 */

import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db, syncCatalogue } from '../../src/lib/db';
import { buildCatalogue } from '../../src/lib/music/cards';

// An id from the root-shell era: the shape the July 2026 cut left behind.
const DEAD = 'chain:C:737';
const LIVE = 'gt:C:m7';

beforeAll(async () => {
	await useMemoryDb();
});

afterAll(async () => {
	await (await db()).close();
});

beforeEach(async () => {
	const conn = await db();
	await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM daily_stats;');
	await conn.run('DELETE FROM cards WHERE id = ?', [DEAD]);
});

async function seedBoth() {
	const conn = await db();
	await conn.run(
		`INSERT INTO cards (id, type, root, quality, root_pitch_class, created_at)
		 VALUES (?, 'chain', 'C', NULL, 0, 1000)`,
		[DEAD]
	);
	for (const id of [DEAD, LIVE]) {
		await conn.run(
			`INSERT INTO reviews (card_id, ts, grade, response_ms, correct, mode)
			 VALUES (?, 1000, 3, 2400, 1, 'srs')`,
			[id]
		);
		await conn.run(
			`INSERT INTO card_state
			 (card_id, due, stability, difficulty, median_response_ms, consecutive_correct, mastery)
			 VALUES (?, 2000, 1.5, 5, 2400, 1, 'familiar')`,
			[id]
		);
	}
	await conn.run(
		`INSERT INTO daily_stats (date, reviews, correct, minutes) VALUES ('2026-07-01', 2, 2, 4)`
	);
}

async function idsIn(table: string, column: string): Promise<string[]> {
	const conn = await db();
	const rows = await conn.all<{ id: string }>(`SELECT ${column} AS id FROM ${table} ORDER BY id`);
	return rows.map((r) => r.id);
}

describe('syncCatalogue', () => {
	it('purges a card this build no longer generates, with its state and reviews', async () => {
		await seedBoth();
		await syncCatalogue(await db());

		expect(await idsIn('cards', 'id')).not.toContain(DEAD);
		expect(await idsIn('card_state', 'card_id')).toEqual([LIVE]);
		expect(await idsIn('reviews', 'card_id')).toEqual([LIVE]);
	});

	it('leaves the practised days alone, so the streak survives the purge', async () => {
		await seedBoth();
		await syncCatalogue(await db());

		const conn = await db();
		const day = await conn.get<{ reviews: number }>(
			`SELECT reviews FROM daily_stats WHERE date = '2026-07-01'`
		);
		expect(day?.reviews).toBe(2);
	});

	it('keeps every live card, so a sync is not a reset', async () => {
		await seedBoth();
		await syncCatalogue(await db());

		const conn = await db();
		const row = await conn.get<{ n: number }>('SELECT COUNT(*) AS n FROM cards');
		expect(row?.n).toBe(buildCatalogue().length);
	});
});
