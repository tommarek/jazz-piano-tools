/**
 * The path is the one piece of logic that changes the deck on its own, so it
 * gets tested against a real SQLite database — the same WASM build the browser
 * uses, with persistence switched off — rather than a mock.
 */

import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db } from '../../src/lib/db';
import {
	EAR_MIN_SAMPLE,
	evaluateEarPath,
	evaluateStages,
	GATE_MIN_SAMPLE
} from '../../src/lib/data/stages';
import { getSettings, saveSettings, DEFAULT_SETTINGS } from '../../src/lib/data/settings';

beforeAll(async () => {
	await useMemoryDb();
});

afterAll(async () => {
	await (await db()).close();
});

/** Marks every guide-tone-family card in the given keys as automatic. */
async function masterPairKeys(pitchClasses: number[]) {
	const conn = await db();
	const rows = await conn.all<{ id: string }>(
		`SELECT id FROM cards
		 WHERE (type IN ('gt','gtn') OR (type IN ('chain','gtc') AND id NOT LIKE '%:minor'))
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
			 VALUES ('chain:C', ?, 3, ?, 1, ?)`,
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

	it('opens stage 2 when every key has an automatic guide-tone pair', async () => {
		await reset();
		await masterPairKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		const stages = await evaluateStages();
		expect(stages.unlocked).toBeGreaterThanOrEqual(2);
		expect(stages.justUnlocked).not.toBeNull();
		expect((await getSettings()).unlockedStages).toBe(stages.unlocked);
	});

	it('keeps stage 2 shut while any key lacks an automatic pair', async () => {
		await reset();
		await masterPairKeys([0, 2, 4, 5, 7, 9, 11]);
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(1);
		expect(stages.next?.n).toBe(2);
		expect(stages.next?.criteria[0].label).toContain('7/12');
	});

	it('says so when both pair drills are off instead of freezing at 0/12', async () => {
		// Nothing can be counted, so the criterion would otherwise sit at a
		// permanent 0/12 with no hint that a Settings switch is what is holding it.
		await reset();
		await saveSettings({
			activeCardTypes: DEFAULT_SETTINGS.activeCardTypes.filter((t) => t !== 'gt' && t !== 'gtn')
		});
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(1);
		expect(stages.next?.criteria[0].met).toBe(false);
		expect(stages.next?.criteria[0].label).toContain('Settings');
		expect(stages.next?.criteria[0].label).not.toContain('0/12');
	});

	it('opens stage 3 only at 2s per chord over enough chains', async () => {
		await reset();
		await masterPairKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		await recordChainReviews(GATE_MIN_SAMPLE + 5, 8000); // 2.7s per chord: not enough
		expect((await evaluateStages()).unlocked).toBe(2);

		const conn = await db();
		await conn.exec('DELETE FROM reviews;');
		await recordChainReviews(GATE_MIN_SAMPLE + 5, 4500); // 1.5s per chord
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(3);
		expect(stages.next).toBeNull();
	});

	it('says which qualities withhold the chain instead of freezing at no counter', async () => {
		// The chain criteria and the headline are computed over MAJOR chains only,
		// so switching one of m7/7/maj7 off freezes them at null for good while
		// minor chains keep being dealt. The type is still ticked, so the type-off
		// label would be a lie — the two causes must read differently.
		await reset();
		await masterPairKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		await saveSettings({
			activeQualities: DEFAULT_SETTINGS.activeQualities.filter((q) => q !== 'maj7')
		});
		const stages = await evaluateStages();
		expect(stages.next?.n).toBe(3);
		expect(stages.chainBlocked).toBe('qualities');
		const label = stages.next!.criteria[0].label;
		expect(label).toContain('maj7');
		expect(label).toContain('Settings');
		expect(label).not.toContain('per chord');
		expect(label).not.toContain('chain drill on');
	});

	it('keeps the type-off label distinguishable from the quality-off one', async () => {
		await reset();
		await masterPairKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		await saveSettings({
			activeCardTypes: DEFAULT_SETTINGS.activeCardTypes.filter((t) => t !== 'chain')
		});
		const stages = await evaluateStages();
		expect(stages.chainBlocked).toBe('type');
		expect(stages.next?.criteria[0].label).toContain('chain drill on');
	});

	it('reports no block while the chain is dealable, whatever the times say', async () => {
		// The headline says "no chain cards answered yet" off this: it must not
		// blame a filter for what is simply a deck nobody has practised yet.
		await reset();
		expect((await evaluateStages()).chainBlocked).toBeNull();
	});

	it('never skips a rung: fast chains alone open nothing', async () => {
		await reset();
		// Chains under 2s but no automatic pairs — stage 2's criterion unmet.
		await recordChainReviews(GATE_MIN_SAMPLE + 5, 4500);
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(1);
	});

	it('respects the auto-unlock switch', async () => {
		await reset();
		await saveSettings({ stageAutoUnlock: false });
		await masterPairKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(1);
		expect(stages.justUnlocked).toBeNull();
	});

	it('respects a manual unlock even when nothing is earned', async () => {
		await reset();
		await saveSettings({ unlockedStages: 3 });
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(3);
		expect(stages.justUnlocked).toBeNull();
	});

	it('announces an unlock exactly once', async () => {
		await reset();
		await masterPairKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		expect((await evaluateStages()).justUnlocked).not.toBeNull();
		expect((await evaluateStages()).justUnlocked).toBeNull();
	});

	it('ignores minor chains when judging the chain median', async () => {
		await reset();
		await masterPairKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		await recordChainReviews(GATE_MIN_SAMPLE + 5, 4500);
		const conn = await db();
		for (let i = 0; i < 40; i++) {
			await conn.run(
				`INSERT INTO reviews (card_id, ts, grade, response_ms, correct, mode)
				 VALUES ('chain:C:minor', ?, 3, 30000, 1, 'srs')`,
				[Date.now() + i * 1000]
			);
		}
		expect((await evaluateStages()).unlocked).toBe(3);
	});

	it('ignores sprint chain times: fast speed rows open nothing', async () => {
		await reset();
		await masterPairKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		await recordChainReviews(GATE_MIN_SAMPLE + 5, 4500, 'speed');
		const stages = await evaluateStages();
		// Stage 2 opens off the mastered pairs, but the chain criteria see no data.
		expect(stages.unlocked).toBe(2);
		expect(stages.next?.n).toBe(3);
		expect(stages.next?.criteria[0].met).toBe(false);
	});

	it('migrates legacy rootlessUnlocked settings to the last stage', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
		await conn.run(`INSERT INTO settings (key, value) VALUES ('rootlessUnlocked', 'true')`);
		expect((await getSettings()).unlockedStages).toBe(3);
	});

	it('renumbers a four-stage-era blob exactly once', async () => {
		// Old stage 3 (guide tones) folds into new stage 2; old 4 (rootless)
		// becomes 3. Keyed on pathVersion, not on the value: a new-era 3 means
		// rootless is open and must not be demoted on every load.
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
		await conn.run(`INSERT INTO settings (key, value) VALUES ('unlockedStages', '3')`);
		expect((await getSettings()).unlockedStages).toBe(2);

		// Nothing has written the marker yet, so this is the load that happens on
		// every launch until something saves. It maps the stored number; mapping
		// the live one would cost a stage per read.
		expect((await getSettings()).unlockedStages).toBe(2);

		// A save stamps pathVersion, so the mapping never runs again.
		await saveSettings({ unlockedStages: 3 });
		expect((await getSettings()).unlockedStages).toBe(3);
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
		expect(settings.unlockedStages).toBe(2);
		// With auto-unlock off nothing else will ever raise it, so the migration is
		// the only chance to get this right.
		expect(settings.stageAutoUnlock).toBe(false);
	});

	it('migrates a legacy blob that never mentioned the rootless gate at all', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
		await conn.run(`INSERT INTO settings (key, value) VALUES ('newCardsPerDay', '5')`);
		expect((await getSettings()).unlockedStages).toBe(2);
	});

	it('still starts a fresh install at stage 1', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
		expect((await getSettings()).unlockedStages).toBe(1);
	});
});

describe('a stage opened by hand', () => {
	it('lets the ladder carry on from where the user actually is', async () => {
		// Settings actively offers "Start it anyway". Re-judging stage 2 after the
		// user took that offer pinned `earned` at 1, so stage 3 could never open —
		// while Today rendered stage 3's fully ticked checklist and did nothing.
		await reset();
		await saveSettings({ unlockedStages: 2, stageAutoUnlock: false });
		await masterPairKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		await recordChainReviews(25, 2400);

		// Auto-unlock off first, so the checklist Today would draw is visible.
		const shown = await evaluateStages();
		expect(shown.unlocked).toBe(2);
		expect(shown.next?.n).toBe(3);
		expect(shown.next?.criteria.every((c) => c.met)).toBe(true);

		await saveSettings({ stageAutoUnlock: true });
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(3);
		expect(stages.justUnlocked).toBe(3);
		expect((await getSettings()).unlockedStages).toBe(3);
	});

	it('never leaves a met checklist showing with nothing behind it', async () => {
		// What the checklist shows is exactly what `earned` is judged on, so an
		// earlier stage can no longer be the silent blocker.
		await reset();
		await saveSettings({ unlockedStages: 2 });
		await recordChainReviews(GATE_MIN_SAMPLE, 9000);

		const stages = await evaluateStages();
		expect(stages.next?.n).toBe(3);
		expect(stages.next?.criteria.some((c) => !c.met)).toBe(true);
		expect(stages.unlocked).toBe(2);
	});
});

describe('an earlier criterion that regresses', () => {
	it('does not freeze the ladder for someone who already earned the stage', async () => {
		// Stage 2 earned with all twelve keys automatic, then both pair drills are
		// switched off — the criterion that opened it can no longer be met at all.
		// Stage 3 must still be reachable; it was not, because `earned` restarted
		// at 1 every time. Regressed through Settings rather than through
		// card_state, which is the case evaluateStages' own comment names — and
		// deleting pair rows does not regress the criterion anyway, since the
		// key's remaining gtn cards keep it covered.
		await reset();
		await masterPairKeys([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
		expect((await evaluateStages()).unlocked).toBeGreaterThanOrEqual(2);

		await saveSettings({
			activeCardTypes: DEFAULT_SETTINGS.activeCardTypes.filter((t) => t !== 'gt' && t !== 'gtn')
		});
		await recordChainReviews(25, 2400);

		// Exactly 3, not "at least 2": the stored unlockedStages is already 2, so
		// the loose assertion passed even with `earned` reseeding from 1 — the
		// very bug this test exists for.
		const stages = await evaluateStages();
		expect(stages.unlocked).toBe(3);
	});
});

describe('the criteria map', () => {
	// It is the one thing in evaluateStages that does not derive from STAGES, so
	// a stage added to the ladder can arrive with no gate behind it. The
	// placeholder keeps that from crashing Today; this keeps it from shipping.
	it('has a real criterion for every stage past the first', async () => {
		const { STAGES } = await import('../../src/lib/music/cards');
		for (const stage of STAGES.slice(1)) {
			await reset();
			await saveSettings({ unlockedStages: stage.n - 1, stageAutoUnlock: false });
			const status = await evaluateStages();
			expect(status.next?.n).toBe(stage.n);
			expect(status.next?.criteria.length).toBeGreaterThan(0);
			for (const criterion of status.next?.criteria ?? [])
				expect(criterion.label).not.toMatch(/^Open stage \d+ in Settings$/);
		}
	});
});

describe('target constants', () => {
	it('keeps the per-chord gate target and the chain mastery target in step', async () => {
		const { GATE_PER_CHORD_MS } = await import('../../src/lib/data/stages');
		const { TIME_TARGETS } = await import('../../src/lib/music/cards');
		expect(TIME_TARGETS.chain.automatic).toBe(3 * GATE_PER_CHORD_MS);
	});
});

describe('the ear path', () => {
	beforeEach(async () => {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
	});

	async function hearIntervals(n: number, correct: number, mode = 'srs') {
		const conn = await db();
		for (let i = 0; i < n; i++) {
			await conn.run(
				`INSERT INTO reviews (card_id, ts, response_ms, correct, grade, mode)
				 VALUES ('eint:C:P5', ?, 2500, ?, 3, ?)`,
				[Date.now() - (n - i) * 1000, i < correct ? 1 : 0, mode]
			);
		}
	}

	it('opens qualities by ear on accuracy, not on speed or on the theory path', async () => {
		await saveSettings({ unlockedStages: 3, earUnlockedStages: 1 });
		// Every theory stage open, and the ear path unmoved: they are separate
		// ladders and one has never demonstrated the other.
		expect((await evaluateEarPath()).unlocked).toBe(1);

		await hearIntervals(EAR_MIN_SAMPLE, EAR_MIN_SAMPLE);
		const opened = await evaluateEarPath();
		expect(opened.unlocked).toBe(2);
		expect(opened.justUnlocked).toBe(2);
		expect((await getSettings()).earUnlockedStages).toBe(2);
	});

	it('will not open on a small sample, however good it looks', async () => {
		await saveSettings({ earUnlockedStages: 1 });
		await hearIntervals(EAR_MIN_SAMPLE - 1, EAR_MIN_SAMPLE - 1);
		const status = await evaluateEarPath();
		expect(status.unlocked).toBe(1);
		expect(status.accuracy).toBe(1);
		expect(status.next?.criteria[0].met).toBe(false);
	});

	it('will not open below the accuracy bar', async () => {
		await saveSettings({ earUnlockedStages: 1 });
		// 15/20 = 75%, under the 80% gate.
		await hearIntervals(EAR_MIN_SAMPLE, 15);
		expect((await evaluateEarPath()).unlocked).toBe(1);
	});

	// Sprints are excluded everywhere a figure is judged; here they would open a
	// stage off attempts the grader itself refuses to trust.
	it('ignores speed rounds', async () => {
		await saveSettings({ earUnlockedStages: 1 });
		await hearIntervals(EAR_MIN_SAMPLE, EAR_MIN_SAMPLE, 'speed');
		const status = await evaluateEarPath();
		expect(status.attempts).toBe(0);
		expect(status.unlocked).toBe(1);
	});

	it('says which switch is in the way when no interval card can be dealt', async () => {
		await saveSettings({ soundEnabled: false });
		expect((await evaluateEarPath()).next?.criteria[0].label).toContain('Sound');
		await saveSettings({ soundEnabled: true, activeCardTypes: ['gt'] });
		expect((await evaluateEarPath()).next?.criteria[0].label).toContain('intervals-by-ear');
	});
});
