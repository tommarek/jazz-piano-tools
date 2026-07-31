/**
 * Stored settings against the real settings table, including blobs written by
 * older versions of the app.
 */

import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db } from '../../src/lib/db';
import { effectiveCardTypes, getSettings, saveSettings } from '../../src/lib/data/settings';
import { CARD_TYPES } from '../../src/lib/music/cards';
import { QUALITIES } from '../../src/lib/music/voicings';

beforeAll(async () => {
	await useMemoryDb();
});

afterAll(async () => {
	await (await db()).close();
});

beforeEach(async () => {
	await (await db()).exec('DELETE FROM settings');
});

/** Writes a settings blob directly, the way an older build would have left it. */
async function storeBlob(blob: Record<string, unknown>) {
	const conn = await db();
	for (const [key, value] of Object.entries(blob)) {
		await conn.run(
			`INSERT INTO settings (key, value) VALUES (?, ?)
			 ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
			[key, JSON.stringify(value)]
		);
	}
}

describe('a drill type added after the settings were written', () => {
	it('arrives in the deck instead of being frozen out by the stored list', async () => {
		// The whole object is re-serialised on every save, so an older build's
		// full type list is sitting in the database of everyone who has ever had
		// a stage unlock. Treating that as an allow-list means a new drill never
		// reaches them, silently and forever.
		const older = CARD_TYPES.filter((t) => t !== 'eint' && t !== 'eqal');
		await storeBlob({
			activeCardTypes: older,
			knownCardTypes: older,
			unlockedStages: 2
		});

		const s = await getSettings();
		expect(s.activeCardTypes).toContain('eint');
		expect(s.activeCardTypes).toContain('eqal');
		expect(s.knownCardTypes).toEqual([...CARD_TYPES]);
	});

	it('leaves a type the user actually switched off alone', async () => {
		await storeBlob({
			activeCardTypes: CARD_TYPES.filter((t) => t !== 'ext'),
			knownCardTypes: [...CARD_TYPES]
		});
		expect((await getSettings()).activeCardTypes).not.toContain('ext');
	});

	it('does the same for a newly added chord quality', async () => {
		const older = QUALITIES.filter((q) => q !== 'mMaj7');
		await storeBlob({ activeQualities: older, knownQualities: older });
		expect((await getSettings()).activeQualities).toContain('mMaj7');
	});

	it('re-offers everything to a blob that predates the known-lists', async () => {
		// Such a blob records nothing about what was on offer when it was written,
		// so nothing in it can be read as a deliberate no.
		await storeBlob({ activeCardTypes: ['gt'], activeQualities: ['m7'], unlockedStages: 4 });
		const s = await getSettings();
		expect(s.activeCardTypes).toEqual([...CARD_TYPES]);
		expect(s.activeQualities).toEqual([...QUALITIES]);
	});

	it('keeps a deliberate choice across a save once the lists are recorded', async () => {
		await saveSettings({ activeCardTypes: ['gt'], activeQualities: ['m7'] });
		await saveSettings({ newCardsPerDay: 3 });
		const s = await getSettings();
		expect(s.activeCardTypes).toEqual(['gt']);
		expect(s.activeQualities).toEqual(['m7']);
	});
});

describe('answering on tap', () => {
	// The opposite default to soundEnabled, and for a reason: every settings blob
	// written before this existed belongs to someone who has never been asked. A
	// silent yes would turn each of their stray taps into a graded wrong answer.
	it('stays off for a blob that predates it, and for a corrupt value', async () => {
		await storeBlob({ sessionMinutes: 6 });
		expect((await getSettings()).instantAnswer).toBe(false);

		await storeBlob({ instantAnswer: 'yes please' });
		expect((await getSettings()).instantAnswer).toBe(false);
	});

	it('survives a save once it is actually asked for', async () => {
		await saveSettings({ instantAnswer: true });
		expect((await getSettings()).instantAnswer).toBe(true);
		// A save of something else must not quietly put it back.
		await saveSettings({ sessionMinutes: 9 });
		expect((await getSettings()).instantAnswer).toBe(true);
	});
});

describe('the ear path, split out of the theory one', () => {
	// The ear drills used to ride on the theory stages: intervals in stage 1,
	// qualities in stage 2. Anyone practising qualities-by-ear before the split
	// had theory stage 2 open, and taking the drill away from them because the
	// setting is new would be the migration losing their progress.
	it('inherits its opening from where the old path had got to', async () => {
		await storeBlob({ unlockedStages: 3 });
		expect((await getSettings()).earUnlockedStages).toBe(2);

		await (await db()).exec('DELETE FROM settings');
		await storeBlob({ unlockedStages: 1 });
		expect((await getSettings()).earUnlockedStages).toBe(1);
	});

	it('starts a fresh install at the first ear stage', async () => {
		expect((await getSettings()).earUnlockedStages).toBe(1);
	});

	it('gates the ear drills on the ear ladder, not the theory one', async () => {
		const s = await saveSettings({ unlockedStages: 3, earUnlockedStages: 1 });
		const live = effectiveCardTypes(s);
		expect(live).toContain('eint');
		// Every theory stage is open and qualities-by-ear still is not: the two
		// ladders have nothing to say about each other.
		expect(live).toContain('rootless');
		expect(live).not.toContain('eqal');

		const both = await saveSettings({ earUnlockedStages: 2 });
		expect(effectiveCardTypes(both)).toContain('eqal');
	});
});

describe('two saves that overlap', () => {
	// Route preloading starts the next page's loader while the current one is
	// still running, and both paths auto-unlock through saveSettings. Every
	// field is re-serialised on every save, so a read taken outside the
	// transaction would have each call writing its stale copy of the other's
	// keys — silently re-locking a stage the app had just announced.
	it('both land, whichever order they run in', async () => {
		await saveSettings({ unlockedStages: 1, earUnlockedStages: 1 });
		await Promise.all([
			saveSettings({ unlockedStages: 3 }),
			saveSettings({ earUnlockedStages: 2 })
		]);
		const s = await getSettings();
		expect(s.unlockedStages).toBe(3);
		expect(s.earUnlockedStages).toBe(2);
	});
});
