/**
 * Speed rounds are pure throughput: they must not move any median, accuracy or
 * daily-stats number. These tests pin the exclusions the way the gate tests pin
 * theirs — against the real SQL.
 */

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db } from '../../src/lib/db';
import { getStats } from '../../src/lib/data/stats';
import { rollUpDay } from '../../src/lib/data/review';

beforeAll(async () => {
	await useMemoryDb();
});

afterAll(async () => {
	await (await db()).close();
});

async function insertReview(cardId: string, ts: number, responseMs: number, correct: number, mode: string) {
	const conn = await db();
	await conn.run(
		`INSERT INTO reviews (card_id, ts, grade, response_ms, correct, mode)
		 VALUES (?, ?, 3, ?, ?, ?)`,
		[cardId, ts, responseMs, correct, mode]
	);
}

describe('speed rounds and the statistics', () => {
	it('keeps sprint rows out of daily_stats medians and accuracy', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM daily_stats;');
		const ts = Date.now();

		// One deliberate review at 3000 ms, correct; a burst of fast sprint rows,
		// half of them wrong. The day must read as the single srs attempt.
		await insertReview('s2n:C:m7:r3', ts, 3000, 1, 'srs');
		for (let i = 0; i < 10; i++) {
			await insertReview('s2n:C:m7:r3', ts + 1 + i, 500, i % 2, 'speed');
		}
		await rollUpDay(ts);

		const row = await conn.get<{ reviews: number; correct: number; median_response_ms: number }>(
			'SELECT reviews, correct, median_response_ms FROM daily_stats'
		);
		expect(row?.reviews).toBe(1);
		expect(row?.correct).toBe(1);
		expect(row?.median_response_ms).toBe(3000);
	});

	it('keeps sprint rows out of the by-quality medians and accuracy', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM daily_stats;');
		const ts = Date.now();

		await insertReview('s2n:C:m7:r3', ts, 3000, 1, 'srs');
		await insertReview('s2n:C:m7:r3', ts + 1, 400, 0, 'speed');
		await insertReview('s2n:C:m7:r3', ts + 2, 400, 1, 'speed');

		const stats = await getStats(ts);
		const m7 = stats.byQuality.find((q) => q.quality === 'm7');
		expect(m7).toBeDefined();
		expect(m7!.medianResponseMs).toBe(3000);
		expect(m7!.accuracy).toBe(1);
	});
});

describe('the by-quality breakdown', () => {
	it('counts every card that names a quality, not a chosen few id shapes', async () => {
		// It used to trust a hand-kept list of id prefixes, which had already gone
		// stale by the time the guide-tone decks arrived: they name a quality in
		// the id and in the catalogue's own column, and contributed nothing.
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM daily_stats;');
		const ts = Date.now();

		await insertReview('s2n:C:m7:r3', ts, 3000, 1, 'srs');
		await insertReview('gt:C:maj7', ts + 1, 2000, 1, 'srs');
		await insertReview('eqal:C:dim7', ts + 2, 5000, 1, 'srs');
		// A guide-tone class is not a chord quality — 'maj7' there means "a 3rd
		// and a 7th a fifth apart", which m7 and m7♭5 share. It must not land in
		// the maj7 bucket.
		await insertReview('gtn:C:maj7', ts + 3, 9000, 1, 'srs');

		const stats = await getStats(ts);
		const of = (q: string) => stats.byQuality.find((b) => b.quality === q);
		expect(of('m7')!.medianResponseMs).toBe(3000);
		expect(of('maj7')!.medianResponseMs).toBe(2000);
		expect(of('dim7')!.medianResponseMs).toBe(5000);
	});
});
