/**
 * Stored settings against the real settings table, including blobs written by
 * older versions of the app.
 */

import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db } from '../../src/lib/db';
import { getSettings, saveSettings } from '../../src/lib/data/settings';
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
		await storeBlob({ activeCardTypes: ['s2n'], activeQualities: ['m7'], unlockedStages: 4 });
		const s = await getSettings();
		expect(s.activeCardTypes).toEqual([...CARD_TYPES]);
		expect(s.activeQualities).toEqual([...QUALITIES]);
	});

	it('keeps a deliberate choice across a save once the lists are recorded', async () => {
		await saveSettings({ activeCardTypes: ['s2n'], activeQualities: ['m7'] });
		await saveSettings({ newCardsPerDay: 3 });
		const s = await getSettings();
		expect(s.activeCardTypes).toEqual(['s2n']);
		expect(s.activeQualities).toEqual(['m7']);
	});
});
