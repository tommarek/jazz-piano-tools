/**
 * Speed rounds are pure throughput: they must not move any median, accuracy or
 * daily-stats number. These tests pin the exclusions the way the gate tests pin
 * theirs — against the real SQL.
 */

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db } from '../../src/lib/db';
import { getStats } from '../../src/lib/data/stats';
import { evaluateStages, GATE_KEY_SCORE, keyScores } from '../../src/lib/data/stages';
import { DEFAULT_SETTINGS, saveSettings, type Settings } from '../../src/lib/data/settings';
import { rollUpDay } from '../../src/lib/data/review';
import { addDays, dateKey } from '../../src/lib/data/queue';

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
		await insertReview('gt:C:m7', ts, 3000, 1, 'srs');
		for (let i = 0; i < 10; i++) {
			await insertReview('gt:C:m7', ts + 1 + i, 500, i % 2, 'speed');
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

		await insertReview('gt:C:m7', ts, 3000, 1, 'srs');
		await insertReview('gt:C:m7', ts + 1, 400, 0, 'speed');
		await insertReview('gt:C:m7', ts + 2, 400, 1, 'speed');

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

		await insertReview('gt:C:m7', ts, 3000, 1, 'srs');
		await insertReview('gt:C:maj7', ts + 1, 2000, 1, 'srs');
		// An ear rep, which must NOT appear below: the by-quality table is part of
		// the theory screen and the ear section reports its own figures. Slow and
		// wrong, so including it would move both dim7 figures rather than hiding
		// inside a tie with the theory rep.
		await insertReview('eqal:C:dim7', ts + 2, 9000, 0, 'srs');
		await insertReview('gt:C:dim7', ts + 4, 5000, 1, 'srs');
		// A guide-tone class is not a chord quality — 'maj7' there means "a 3rd
		// and a 7th a fifth apart", which m7 and m7♭5 share. It must not land in
		// the maj7 bucket.
		await insertReview('gtn:C:maj7', ts + 3, 9000, 1, 'srs');
		// The degree drills carry no quality column at all, and the numeral is the
		// whole answer: dia:C:vii asks for Bm7♭5 by name. Reading the column alone
		// left both of them out of the table entirely.
		await insertReview('dia:C:vii', ts + 5, 4000, 1, 'srs');
		await insertReview('mode:C:vii', ts + 6, 6000, 1, 'srs');
		// A progression is answered by all of its chords at once, so there is no
		// one bucket its rep belongs in and it stays out.
		await insertReview('chain:C', ts + 7, 12_000, 1, 'srs');

		const stats = await getStats(ts);
		const of = (q: string) => stats.byQuality.find((b) => b.quality === q);
		expect(of('m7')!.medianResponseMs).toBe(3000);
		expect(of('maj7')!.medianResponseMs).toBe(2000);
		expect(of('dim7')!.medianResponseMs).toBe(5000);
		// The dim7 figure is the theory rep's, not an average with the ear one.
		expect(of('dim7')!.accuracy).toBe(1);
		expect(of('m7b5')!.medianResponseMs).toBe(5000);
	});

	it('keeps ear reps out of the theory retention figure', async () => {
		// The e2e that covers the split only asserts the ear block is populated,
		// so dropping the section filter on retention showed up nowhere.
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM daily_stats;');
		const ts = Date.now();
		// Retention only counts a card met on an earlier day, so both cards are
		// introduced yesterday and answered again today.
		const before = addDays(ts, -1) + 3_600_000;

		await insertReview('eint:C:P5', before, 4000, 1, 'srs');
		await insertReview('gt:C:m7', before, 3000, 1, 'srs');
		await insertReview('eint:C:P5', ts, 4000, 0, 'srs');
		expect((await getStats(ts)).retention.reviewed).toBe(0);

		await insertReview('gt:C:m7', ts + 1, 3000, 1, 'srs');
		const stats = await getStats(ts);
		expect(stats.retention.reviewed).toBe(1);
		expect(stats.retention.correct).toBe(1);
	});
});

describe('the twelve-key heatmap and the rootless keys criterion', () => {
	/**
	 * Progress captions the heatmap as "the same measure the path's last stage
	 * uses". They were two computations over two populations: Progress filtered
	 * by the user's current stage lock, while the criteria deliberately judge as
	 * if every stage were open. On stage 1 that hid the chain and voice-leading
	 * cards from one screen and not the other, so the same key read 100% on
	 * Progress and failed the gate it claimed to be measuring.
	 */
	async function masterTypes(types: string[]) {
		const conn = await db();
		const rows = await conn.all<{ id: string }>(
			`SELECT id FROM cards WHERE type IN (${types.map((t) => `'${t}'`).join(',')})
			   AND id NOT LIKE '%:minor'`
		);
		for (const row of rows) {
			await conn.run(
				`INSERT OR REPLACE INTO card_state
				 (card_id, due, stability, difficulty, reps, lapses, state, consecutive_correct, mastery)
				 VALUES (?, 0, 10, 5, 5, 0, 2, 5, 'automatic')`,
				[row.id]
			);
		}
	}

	async function clean(settings: Partial<Settings>) {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM daily_stats; DELETE FROM card_state; DELETE FROM settings;');
		// Auto-unlock off, so evaluating the criteria cannot move the very stage
		// lock this test is holding still.
		await saveSettings({ ...DEFAULT_SETTINGS, stageAutoUnlock: false, ...settings });
	}

	// Stage 1 is the case that used to diverge: the heatmap saw only the
	// guide-tone drills, the gate saw the chains too.
	for (const unlockedStages of [1, 3]) {
		it(`agree key for key with the path locked at stage ${unlockedStages}`, async () => {
			await clean({ unlockedStages });
			await masterTypes(['gt', 'gtn']);

			const stats = await getStats(Date.now());
			const scores = await keyScores();
			expect(stats.heatmap).toHaveLength(12);
			for (const cell of stats.heatmap) {
				const scored = scores.find((k) => k.pitchClass === cell.pitchClass)!;
				expect(cell.score, `${cell.label} score`).toBe(scored.score);
				expect(cell.total, `${cell.label} total`).toBe(scored.total);
				expect(cell.automatic, `${cell.label} automatic`).toBe(scored.automatic);
			}

			// And the number the caption points at: the gate's verdict is exactly
			// "every cell at or above the bar", read off the same cells.
			const { keysMet } = await evaluateStages();
			const allGreen = stats.heatmap.every((c) => c.score >= GATE_KEY_SCORE);
			expect(allGreen).toBe(keysMet);
		});
	}

	it('counts the locked stages\' cards, because the criterion does', async () => {
		// The assertion above is only worth having if the lock could move the
		// numbers. It could: with the path at stage 1 the heatmap used to see the
		// shell drills alone and read a wall of 100%, while the gate it captions
		// itself as measuring was still counting the chains against it.
		await clean({ unlockedStages: 1 });
		await masterTypes(['gt', 'gtn']);
		const locked = await getStats(Date.now());

		await clean({ unlockedStages: 3 });
		await masterTypes(['gt', 'gtn']);
		const open = await getStats(Date.now());

		expect(locked.heatmap.map((c) => c.total)).toEqual(open.heatmap.map((c) => c.total));
		expect(locked.heatmap.map((c) => c.score)).toEqual(open.heatmap.map((c) => c.score));
		// Not a wall of 100%: the chain and voice-leading cards are in there unmastered.
		expect(locked.heatmap.every((c) => c.score < 1)).toBe(true);

		// Finish the family off and both screens turn over together.
		await masterTypes(['gt', 'gtn', 'chain', 'gtc']);
		const done = await getStats(Date.now());
		expect(done.heatmap.every((c) => c.score === 1)).toBe(true);
		expect((await evaluateStages()).keysMet).toBe(true);
	});
});

describe('a day of nothing but speed rounds', () => {
	/**
	 * daily_stats is the sprint-free population on purpose — a 60-second blitz
	 * would drag the day's median and accuracy to sprint pace. But "did you
	 * practise today" is a different question, and answering it out of that
	 * column told a user who had drilled for an hour that they had done nothing,
	 * greyed their square and broke their streak.
	 */
	it('counts as practice and keeps the streak alive', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM daily_stats;');
		const today = Date.now();
		const yesterday = addDays(today, -1) + 3_600_000;

		// Yesterday: ordinary practice. Today: sprints only.
		await insertReview('gt:C:m7', yesterday, 3000, 1, 'srs');
		await rollUpDay(yesterday);
		for (let i = 0; i < 20; i++) {
			await insertReview('gt:C:m7', today + i, 500, 1, 'speed');
		}
		await rollUpDay(today);

		const stats = await getStats(today);
		expect(stats.today.reviews).toBe(20);
		expect(stats.streakDays).toBe(2);

		const day = stats.byDay.find((d) => d.date === dateKey(today))!;
		expect(day.attempts).toBe(20);
		// The quality columns stay sprint-free: no reviews to judge, so no median.
		expect(day.reviews).toBe(0);
		expect(day.medianResponseMs).toBeNull();
	});

	/**
	 * A day whose whole session was cut drills loses its review rows to the
	 * catalogue purge but keeps its daily_stats row, which is what the streak
	 * reads. The week strip reads byDay, so a zero there would grey a square on
	 * the same screen whose streak is counting that very day.
	 */
	it('keeps a purged day on the strip with the count the streak sees', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM daily_stats;');
		const today = Date.now();
		const purged = addDays(today, -1) + 3_600_000;

		await insertReview('gt:C:m7', today, 3000, 1, 'srs');
		await rollUpDay(today);
		// The rollup as the purged day left it: the reviews behind it are gone.
		await conn.run(
			`INSERT INTO daily_stats (date, reviews, correct, median_response_ms, minutes)
			 VALUES (?, 14, 12, 2800, 4.2)`,
			[dateKey(purged)]
		);

		const stats = await getStats(today);
		expect(stats.byDay.find((d) => d.date === dateKey(purged))!.attempts).toBe(14);
		expect(stats.streakDays).toBe(2);
	});

	it('leaves the medians and accuracy on the deliberate attempts alone', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM daily_stats;');
		const ts = Date.now();

		await insertReview('gt:C:m7', ts, 3000, 1, 'srs');
		for (let i = 0; i < 10; i++) {
			await insertReview('gt:C:m7', ts + 1 + i, 500, i % 2, 'speed');
		}
		await rollUpDay(ts);

		const stats = await getStats(ts);
		const day = stats.byDay.find((d) => d.date === dateKey(ts))!;
		expect(day.attempts).toBe(11);
		expect(day.reviews).toBe(1);
		expect(day.accuracy).toBe(1);
		expect(day.medianResponseMs).toBe(3000);
	});
});
