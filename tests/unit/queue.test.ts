/**
 * Which cards the deck may draw from, against the real catalogue table.
 */

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db } from '../../src/lib/db';
import { buildQueue, eligibleIds, queueSummary, spreadAcrossTypes } from '../../src/lib/data/queue';
import { DEFAULT_SETTINGS, saveSettings } from '../../src/lib/data/settings';
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

	it('drops a minor progression when the qualities it is made of are off', async () => {
		// A minor ii–V–i is iiø, V7, i(m maj7). Someone who has switched m7♭5 and
		// m(maj7) off cannot be dealt a single m7♭5 shell, so dealing them a chain
		// whose answers are two of those chords is the same card by another route.
		const ids = await eligibleIds({
			...ALL_STAGES,
			activeQualities: ['maj7', 'm7', '7', 'dim7']
		});
		expect(ids.has('s2n:C:m7b5:r3')).toBe(false);
		expect(ids.has('chain:C:737:minor')).toBe(false);
		expect(ids.has('vl:C:737:ii-V:minor')).toBe(false);
		expect(ids.has('gtc:C:ii-V:minor')).toBe(false);
		// The major chain is m7, 7 and maj7 throughout, so it stays.
		expect(ids.has('chain:C:737')).toBe(true);
		expect(ids.has('vl:C:737:ii-V')).toBe(true);
		expect(ids.has('gtc:C:ii-V')).toBe(true);
	});

	it('keeps a chain only while all three of its chords are drilled', async () => {
		// Unlike gtn and n2s, a chain is not answered by picking one reading: all
		// three chords have to be produced, so one switched-off quality is enough
		// to make the card unanswerable as configured.
		const major = await eligibleIds({
			...ALL_STAGES,
			activeQualities: ['maj7', 'm7', '7', 'dim7']
		});
		expect(major.has('chain:C:737')).toBe(true);
		// Rootless comping is major-only, so it follows the major chain.
		expect(major.has('rlc:C:ii-V:A')).toBe(true);

		const noDominant = await eligibleIds({ ...ALL_STAGES, activeQualities: ['maj7', 'm7'] });
		expect(noDominant.has('chain:C:737')).toBe(false);
		expect(noDominant.has('chain:C:737:minor')).toBe(false);
		expect(noDominant.has('rlc:C:ii-V:A')).toBe(false);
		// And a shell of a still-active quality is untouched by all this.
		expect(noDominant.has('s2n:C:m7:r3')).toBe(true);
	});

	it('judges a transition card on the two chords it actually contains', async () => {
		// vl, gtc and rlc cover one step of the ii–V–I, not the whole thing:
		// vl:C:737:ii-V is Dm7 → G7 and has no maj7 in it anywhere, so demanding
		// the tonic's quality withheld a card the user can answer perfectly well.
		const noTonic = await eligibleIds({ ...ALL_STAGES, activeQualities: ['m7', '7'] });
		expect(noTonic.has('vl:C:737:ii-V')).toBe(true);
		expect(noTonic.has('gtc:C:ii-V')).toBe(true);
		expect(noTonic.has('rlc:C:ii-V:A')).toBe(true);
		expect(noTonic.has('vl:C:737:V-I')).toBe(false);
		expect(noTonic.has('gtc:C:V-I')).toBe(false);
		expect(noTonic.has('rlc:C:V-I:A')).toBe(false);
		// The chain is the one that really does ask for all three.
		expect(noTonic.has('chain:C:737')).toBe(false);

		// The other end: with the ii off, V–I survives and ii–V does not.
		const noSupertonic = await eligibleIds({ ...ALL_STAGES, activeQualities: ['7', 'maj7'] });
		expect(noSupertonic.has('vl:C:737:V-I')).toBe(true);
		expect(noSupertonic.has('vl:C:737:ii-V')).toBe(false);

		// Minor transitions read their own chords: iiø–V is m7♭5 and 7.
		const minorFirstHalf = await eligibleIds({ ...ALL_STAGES, activeQualities: ['m7b5', '7'] });
		expect(minorFirstHalf.has('vl:C:737:ii-V:minor')).toBe(true);
		expect(minorFirstHalf.has('vl:C:737:V-I:minor')).toBe(false);
		expect(minorFirstHalf.has('gtc:C:ii-V:minor')).toBe(true);
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

describe('the Today summary', () => {
	async function clean(settings: Partial<typeof DEFAULT_SETTINGS>) {
		const conn = await db();
		await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
		await saveSettings({ ...DEFAULT_SETTINGS, ...settings });
	}

	it('flags a zero new-card budget, which no amount of waiting fixes', async () => {
		// "Come back tomorrow" is false forever here: tomorrow's reset of the
		// introduced count changes nothing, because the budget is a setting.
		await clean({ newCardsPerDay: 0 });
		const summary = await queueSummary();
		expect(summary.total).toBe(0);
		expect(summary.deckEmpty).toBe(false);
		expect(summary.newBudgetZero).toBe(true);
	});

	it('does not flag it when new cards are still on offer', async () => {
		await clean({ newCardsPerDay: 8 });
		const summary = await queueSummary();
		expect(summary.new).toBeGreaterThan(0);
		expect(summary.newBudgetZero).toBe(false);
	});
});
