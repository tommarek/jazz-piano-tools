/**
 * Which cards the deck may draw from, against the real catalogue table.
 */

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db } from '../../src/lib/db';
import { buildQueue, eligibleIds, spreadAcrossTypes } from '../../src/lib/data/queue';
import { DEFAULT_SETTINGS } from '../../src/lib/data/settings';
import { CARD_TYPES } from '../../src/lib/music/cards';

beforeAll(async () => {
	await useMemoryDb();
});

afterAll(async () => {
	await (await db()).close();
});

const ALL_STAGES = { ...DEFAULT_SETTINGS, unlockedStages: 4 };

describe('eligibility', () => {
	it('drops the ear drills when sound is off, and nothing else', async () => {
		// An ear card's prompt is the sound: with playback off it would come up
		// with no question on the screen at all.
		const withSound = await eligibleIds(ALL_STAGES);
		const withoutSound = await eligibleIds({ ...ALL_STAGES, soundEnabled: false });

		expect(withSound.has('eint:C:P5')).toBe(true);
		expect(withSound.has('eqal:C:m7')).toBe(true);
		expect(withoutSound.has('eint:C:P5')).toBe(false);
		expect(withoutSound.has('eqal:C:m7')).toBe(false);

		const dropped = [...withSound].filter((id) => !withoutSound.has(id));
		expect(dropped.every((id) => id.startsWith('eint:') || id.startsWith('eqal:'))).toBe(true);
		expect(dropped).toHaveLength(12 * 11 + 12 * 6);
	});

	it('still filters ear chords by the qualities being drilled', async () => {
		// A quality switched off in Settings is off everywhere, including the ear.
		const ids = await eligibleIds({ ...ALL_STAGES, activeQualities: ['m7'] });
		expect(ids.has('eqal:C:m7')).toBe(true);
		expect(ids.has('eqal:C:dim7')).toBe(false);
		// Intervals name no chord, so the quality filter leaves them alone.
		expect(ids.has('eint:C:d5')).toBe(true);
	});

	it('keeps a guide-tone class whose readings include an active quality', async () => {
		// A gtn card's quality column is an interval class, not a chord quality:
		// the class named 'maj7' is the 3rd–7th of maj7, m7 AND m7♭5 alike, and
		// all three are accepted answers. Matching the column literally lost every
		// gtn card for anyone drilling only m7.
		const ids = await eligibleIds({ ...ALL_STAGES, activeQualities: ['m7'] });
		expect(ids.has('gtn:C:maj7')).toBe(true);
		// The tritone class reads as 7 or °7, and the minor 6th only as m(maj7).
		expect(ids.has('gtn:C:7')).toBe(false);
		expect(ids.has('gtn:C:mMaj7')).toBe(false);
		// The plain guide-tone card does name its quality, so it still filters.
		expect(ids.has('gt:C:m7')).toBe(true);
		expect(ids.has('gt:C:maj7')).toBe(false);
	});
});

describe('notes→symbol cards follow the qualities being drilled', () => {
	it('keeps a shell whose readings include an active quality, drops the rest', async () => {
		// An n2s card carries a guide interval, not a quality — but it is answered
		// with a quality, so drilling only maj7 must not serve a card whose every
		// accepted answer is minor.
		const major = await eligibleIds({ ...ALL_STAGES, activeQualities: ['maj7'] });
		// A major 3rd over the root reads as maj7 or 7; a minor 3rd never as maj7.
		expect(major.has('n2s:C:M3')).toBe(true);
		expect(major.has('n2s:C:M7')).toBe(true);
		expect(major.has('n2s:C:m3')).toBe(false);
		expect(major.has('n2s:C:m7')).toBe(false);
		expect(major.has('n2s:C:d7')).toBe(false);

		// The ♭♭7 shell only ever reads as °7 — the case that was special-cased.
		const dim = await eligibleIds({ ...ALL_STAGES, activeQualities: ['dim7'] });
		expect(dim.has('n2s:C:d7')).toBe(true);
		expect(dim.has('n2s:C:M3')).toBe(false);
	});
});

describe('a backlog bigger than the session', () => {
	it('serves the most overdue cards, not an arbitrary slice of the pile', async () => {
		const conn = await db();
		await conn.exec('DELETE FROM card_state; DELETE FROM reviews;');
		const now = Date.now();
		const ids = [...(await eligibleIds(ALL_STAGES))].sort().slice(0, 40);
		// Oldest debt first: ids[0] is a month overdue, ids[39] a day.
		for (let i = 0; i < ids.length; i++) {
			await conn.run(
				`INSERT INTO card_state
				 (card_id, due, stability, difficulty, reps, lapses, state, consecutive_correct, mastery)
				 VALUES (?, ?, 10, 5, 3, 0, 2, 1, 'learning')`,
				[ids[i], now - (40 - i) * 86_400_000]
			);
		}

		const queue = await buildQueue({ settings: ALL_STAGES, now, limit: 10 });
		expect(queue).toHaveLength(10);
		// Interleaving may order them however it likes — but only the ten oldest
		// may be in the session at all, or the oldest debt never comes up again.
		expect(queue.map((q) => q.card.id).sort()).toEqual(ids.slice(0, 10).sort());
		await conn.exec('DELETE FROM card_state;');
	});
});

describe('spreading new cards across the types', () => {
	// One card per type per key, which is what the catalogue looks like from the
	// spreader's side.
	const deck = () =>
		CARD_TYPES.flatMap((type) =>
			['C', 'F', 'Bb', 'Eb'].map((root) => ({ id: `${type}:${root}:x`, type }))
		);

	it('reaches every type even when a day introduces fewer cards than there are types', () => {
		// A warm deck has room for a card or two a day against fifteen live types.
		// Walking the type list from the top every session starves everything past
		// the budget — the chains, the voice leading and the comping drills — for
		// as long as the deck stays warm, which is forever.
		const remaining = deck();
		const seenByType = new Map<string, number>();
		const introduced = new Set<string>();

		for (let session = 0; session < 5; session++) {
			const picked = spreadAcrossTypes(remaining, 3, seenByType);
			expect(picked).toHaveLength(3);
			for (const card of picked) {
				introduced.add(card.type);
				seenByType.set(card.type, (seenByType.get(card.type) ?? 0) + 1);
				remaining.splice(remaining.indexOf(card), 1);
			}
		}

		expect([...introduced].sort()).toEqual([...CARD_TYPES].sort());
	});

	it('serves the type that is furthest behind first', () => {
		const seenByType = new Map<string, number>(CARD_TYPES.map((t) => [t, 5]));
		seenByType.set('rlc', 0);
		const picked = spreadAcrossTypes(deck(), 1, seenByType);
		expect(picked[0].type).toBe('rlc');
	});
});
