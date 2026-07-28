/**
 * The path is the one piece of logic that changes the deck on its own, so it
 * gets tested against a real SQLite database — the same WASM build the browser
 * uses, with persistence switched off — rather than a mock.
 */

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db } from '../../src/lib/db';
import { evaluateStages, GATE_MIN_SAMPLE } from '../../src/lib/data/stages';
import { getSettings, saveSettings, DEFAULT_SETTINGS } from '../../src/lib/data/settings';

beforeAll(async () => {
	await useMemoryDb();
});

afterAll(async () => {
	await (await db()).close();
});

/** Marks every shell-family card in the given keys as automatic. */
async function masterShellKeys(pitchClasses: number[]) {
	const conn = await db();
	const rows = await conn.all<{ id: string }>(
		`SELECT id FROM cards
		 WHERE (type IN ('s2n','n2s') OR (type IN ('chain','vl') AND id NOT LIKE '%:minor'))
		   AND root_pitch_class IN (${pitchClasses.join(',')})`
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

async function recordChainReviews(count: number, responseMs: number, mode = 'srs') {
	const conn = await db();
	for (let i = 0; i < count; i++) {
		await conn.run(
			`INSERT INTO reviews (card_id, ts, grade, response_ms, correct, mode)
			 VALUES ('chain:C:737', ?, 3, ?, 1, ?)`,
			[Date.now() - i * 1000, responseMs, mode]
		);
	}
}

async function reset() {
	const conn = await db();
	await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
	await saveSettings(DEFAULT_SETTINGS);
}

describe('the path', () => {
	it('starts at stage 1 on an empty deck, pointing at stage 2', async () => {
		await reset();
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(1);
		expect(stages.next?.n).toBe(2);
		expect(stages.next?.criteria[0].met).toBe(false);
		expect(stages.next?.criteria[0].label).toContain('0/12');
	});

	it('opens stage 2 when every key has an automatic shell', async () => {
		await reset();
		await masterShellKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		const stages = await evaluateStages();
		expect(stages.unlocked).toBeGreaterThanOrEqual(2);
		expect(stages.justUnlocked).not.toBeNull();
		expect((await getSettings()).unlockedStages).toBe(stages.unlocked);
	});

	it('keeps stage 2 shut while any key lacks an automatic shell', async () => {
		await reset();
		await masterShellKeys([0, 2, 4, 5, 7, 9, 11]);
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(1);
		expect(stages.next?.n).toBe(2);
		expect(stages.next?.criteria[0].label).toContain('7/12');
	});

	it('says so when both shell drills are off instead of freezing at 0/12', async () => {
		// Nothing can be counted, so the criterion would otherwise sit at a
		// permanent 0/12 with no hint that a Settings switch is what is holding it.
		await reset();
		await saveSettings({
			activeCardTypes: DEFAULT_SETTINGS.activeCardTypes.filter((t) => t !== 's2n' && t !== 'n2s')
		});
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(1);
		expect(stages.next?.criteria[0].met).toBe(false);
		expect(stages.next?.criteria[0].label).toContain('Settings');
		expect(stages.next?.criteria[0].label).not.toContain('0/12');
	});

	it('opens stage 3 on twenty correct chains under 3s per chord', async () => {
		await reset();
		await masterShellKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		await recordChainReviews(GATE_MIN_SAMPLE + 5, 8000); // 2.7s per chord
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(3);
		expect(stages.next?.n).toBe(4);
	});

	it('opens stage 4 only at 2s per chord, even when 3s is met', async () => {
		await reset();
		await masterShellKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		await recordChainReviews(GATE_MIN_SAMPLE + 5, 8000);
		expect((await evaluateStages()).unlocked).toBe(3);

		const conn = await db();
		await conn.exec('DELETE FROM reviews;');
		await recordChainReviews(GATE_MIN_SAMPLE + 5, 4500); // 1.5s per chord
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(4);
		expect(stages.next).toBeNull();
	});

	it('never skips a rung: fast chains alone open nothing', async () => {
		await reset();
		// Chains under 2s but no automatic shells — stage 2's criterion unmet.
		await recordChainReviews(GATE_MIN_SAMPLE + 5, 4500);
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(1);
	});

	it('respects the auto-unlock switch', async () => {
		await reset();
		await saveSettings({ stageAutoUnlock: false });
		await masterShellKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(1);
		expect(stages.justUnlocked).toBeNull();
	});

	it('respects a manual unlock even when nothing is earned', async () => {
		await reset();
		await saveSettings({ unlockedStages: 4 });
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(4);
		expect(stages.justUnlocked).toBeNull();
	});

	it('announces an unlock exactly once', async () => {
		await reset();
		await masterShellKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		expect((await evaluateStages()).justUnlocked).not.toBeNull();
		expect((await evaluateStages()).justUnlocked).toBeNull();
	});

	it('ignores minor chains when judging the chain median', async () => {
		await reset();
		await masterShellKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		await recordChainReviews(GATE_MIN_SAMPLE + 5, 4500);
		const conn = await db();
		for (let i = 0; i < 40; i++) {
			await conn.run(
				`INSERT INTO reviews (card_id, ts, grade, response_ms, correct, mode)
				 VALUES ('chain:C:737:minor', ?, 3, 30000, 1, 'srs')`,
				[Date.now() + i * 1000]
			);
		}
		expect((await evaluateStages()).unlocked).toBe(4);
	});

	it('ignores sprint chain times: fast speed rows open nothing', async () => {
		await reset();
		await masterShellKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		await recordChainReviews(GATE_MIN_SAMPLE + 5, 4500, 'speed');
		const stages = await evaluateStages();
		// Stage 2 opens off the mastered shells, but the chain criteria see no data.
		expect(stages.unlocked).toBe(2);
		expect(stages.next?.n).toBe(3);
		expect(stages.next?.criteria[0].met).toBe(false);
	});

	it('migrates legacy rootlessUnlocked settings to the last stage', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
		await conn.run(`INSERT INTO settings (key, value) VALUES ('rootlessUnlocked', 'true')`);
		expect((await getSettings()).unlockedStages).toBe(4);
	});

	it('does not demote a legacy deck that never opened the rootless gate', async () => {
		// Before the path, the only gate was rootlessUnlocked: everything else was
		// already being served. Defaulting these blobs to stage 1 shrank the deck
		// of anyone who had been practising for months.
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
		await conn.run(`INSERT INTO settings (key, value) VALUES ('rootlessUnlocked', 'false')`);
		await conn.run(`INSERT INTO settings (key, value) VALUES ('sessionMinutes', '8')`);
		await conn.run(`INSERT INTO settings (key, value) VALUES ('stageAutoUnlock', 'false')`);
		const settings = await getSettings();
		expect(settings.unlockedStages).toBe(3);
		// With auto-unlock off nothing else will ever raise it, so the migration is
		// the only chance to get this right.
		expect(settings.stageAutoUnlock).toBe(false);
	});

	it('migrates a legacy blob that never mentioned the rootless gate at all', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
		await conn.run(`INSERT INTO settings (key, value) VALUES ('newCardsPerDay', '5')`);
		expect((await getSettings()).unlockedStages).toBe(3);
	});

	it('still starts a fresh install at stage 1', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
		expect((await getSettings()).unlockedStages).toBe(1);
	});
});

describe('target constants', () => {
	it('keeps the per-chord gate target and the chain mastery target in step', async () => {
		const { GATE_PER_CHORD_MS } = await import('../../src/lib/data/stages');
		const { TIME_TARGETS } = await import('../../src/lib/music/cards');
		expect(TIME_TARGETS.chain.automatic).toBe(3 * GATE_PER_CHORD_MS);
	});
});
