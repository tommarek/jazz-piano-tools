/**
 * Looking inside a deck. The list has to describe the deck the session would
 * actually deal — a browser that shows cards the queue refuses to serve is
 * describing a different app than the one running.
 */

import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db } from '../../src/lib/db';
import { deckCards } from '../../src/lib/data/browse';
import { saveSettings, DEFAULT_SETTINGS } from '../../src/lib/data/settings';

beforeAll(async () => {
	await useMemoryDb();
});

afterAll(async () => {
	await (await db()).close();
});

beforeEach(async () => {
	const conn = await db();
	await conn.exec('DELETE FROM settings; DELETE FROM card_state; DELETE FROM reviews;');
	await saveSettings({ ...DEFAULT_SETTINGS, unlockedStages: 3, earUnlockedStages: 2 });
});

describe('a deck browsed', () => {
	it('groups a stage by its drills and counts the whole deck', async () => {
		const view = await deckCards({ kind: 'stage', section: 'theory', n: 1 });
		expect(view.groups.map((g) => g.type)).toEqual(['gt', 'gtn', 'ivl']);
		expect(view.total).toBe(view.groups.reduce((n, g) => n + g.cards.length, 0));
		expect(view.counts.unseen).toBe(view.total);
	});

	it('carries the question and the answer, both exactly as the drill has them', async () => {
		const view = await deckCards({ kind: 'type', type: 'gt' });
		const card = view.groups[0].cards.find((c) => c.id === 'gt:C:maj7')!;
		expect(card.title).toBe('Cmaj7');
		expect(card.instruction).toBe('Guide-tone voicing — tap the 3rd and 7th');
		expect(card.answerText).toContain('E');
	});

	// An ear card's question is a sound. A row that printed a description of it
	// would be showing something the drill never shows.
	it('carries the sound of a card whose prompt IS the sound', async () => {
		const ear = await deckCards({ kind: 'type', type: 'eint' });
		const card = ear.groups[0].cards[0];
		expect(card.promptIsSound).toBe(true);
		expect(card.sound?.length).toBeGreaterThan(0);

		const read = await deckCards({ kind: 'type', type: 'gt' });
		expect(read.groups[0].cards[0].promptIsSound).toBe(false);
	});

	// Several extensions hang off the same chord symbol, and identical rows
	// carrying different states is a list nobody can read.
	it('qualifies rows whose title repeats inside their group', async () => {
		const view = await deckCards({ kind: 'type', type: 'ext' });
		const both = view.groups[0].cards.filter((c) => c.title === 'C7');
		expect(both.length).toBeGreaterThan(1);
		expect(both[0].qualifier).toBeTruthy();
		expect(both[0].qualifier).not.toBe(both[1].qualifier);

		// And a deck whose titles are already unique gets no noise.
		const modes = await deckCards({ kind: 'type', type: 'mode' });
		expect(modes.groups[0].cards.every((c) => c.qualifier === null)).toBe(true);

		// Nor does a deck where the title repeats but the instruction is the same
		// every time: every ear card is called "Listen" and asks in identical
		// words, so repeating them per row separates nothing. The group says it
		// once instead.
		const ear = await deckCards({ kind: 'type', type: 'eint' });
		expect(ear.groups[0].cards.every((c) => c.title === 'Listen')).toBe(true);
		expect(ear.groups[0].cards.every((c) => c.qualifier === null)).toBe(true);
		expect(ear.groups[0].sharedInstruction).toBeTruthy();
	});

	it('reports state, due-ness and the median as the scheduler stored them', async () => {
		const conn = await db();
		const soon = Date.now() - 1000;
		await conn.run(
			`INSERT INTO card_state (card_id, due, stability, difficulty, reps, lapses, state, mastery, median_response_ms)
			 VALUES ('mode:C:ii', ?, 1, 5, 4, 1, 2, 'familiar', 2200)`,
			[soon]
		);
		const view = await deckCards({ kind: 'type', type: 'mode' });
		const card = view.groups[0].cards.find((c) => c.id === 'mode:C:ii')!;
		expect(card.mastery).toBe('familiar');
		expect(card.due).toBe(true);
		expect(card.medianResponseMs).toBe(2200);
		expect(card.reps).toBe(4);
		expect(card.lapses).toBe(1);
		expect(view.counts.due).toBe(1);
		expect(view.counts.familiar).toBe(1);
	});

	// Nothing constrains the column, and an import writes the file's own value.
	// A state this build does not know must read as "nothing known yet" rather
	// than take the screen down with it.
	it('reads an unrecognised mastery as unseen', async () => {
		const conn = await db();
		await conn.run(
			`INSERT INTO card_state (card_id, due, stability, difficulty, reps, lapses, state, mastery)
			 VALUES ('gt:C:maj7', 0, 1, 5, 1, 0, 2, 'learning')`
		);
		const view = await deckCards({ kind: 'type', type: 'gt' });
		expect(view.groups[0].cards.find((c) => c.id === 'gt:C:maj7')!.mastery).toBe('unseen');
		expect(view.counts.unseen).toBe(view.total);
	});

	// The same hole, through Object.prototype: a membership test written with
	// `in` answers yes to 'toString', and the row then renders a function.
	it('reads a prototype key as unseen too', async () => {
		const conn = await db();
		await conn.run(
			`INSERT INTO card_state (card_id, due, stability, difficulty, reps, lapses, state, mastery)
			 VALUES ('gt:C:maj7', 0, 1, 5, 1, 0, 2, 'toString')`
		);
		const view = await deckCards({ kind: 'type', type: 'gt' });
		expect(view.groups[0].cards.find((c) => c.id === 'gt:C:maj7')!.mastery).toBe('unseen');
		expect(view.counts.unseen).toBe(view.total);
	});

	it('leaves out a drill that is switched off, like the queue does', async () => {
		await saveSettings({ activeCardTypes: ['gt'] });
		const stage1 = await deckCards({ kind: 'stage', section: 'theory', n: 1 });
		expect(stage1.groups.map((g) => g.type)).toEqual(['gt']);

		const off = await deckCards({ kind: 'type', type: 'ivl' });
		expect(off.total).toBe(0);
		expect(off.groups).toEqual([]);
		expect(off.block).toBe('off');
	});

	// Three switches can empty a deck and they are in three different places on
	// the settings screen. An empty list that blames the drill switches for the
	// sound one sends the learner to the wrong row.
	it('says which switch emptied it', async () => {
		await saveSettings({ soundEnabled: false });
		expect((await deckCards({ kind: 'type', type: 'eint' })).block).toBe('sound');
		// Including the whole ear section, which deckBlock does not speak for.
		expect((await deckCards({ kind: 'section', section: 'ear' })).block).toBe('sound');

		await saveSettings({ soundEnabled: true, activeQualities: ['m7', '7'] });
		const chain = await deckCards({ kind: 'type', type: 'chain' });
		expect(chain.total).toBe(0);
		expect(chain.block).toBe('qualities');

		expect((await deckCards({ kind: 'type', type: 'gt' })).block).toBe(null);
	});

	// The other half of the gate the counts apply. The row on Today is sized with
	// the quality switches on, and it is the thing you tap to get here.
	it('leaves out a quality that is switched off, like the queue does', async () => {
		const before = await deckCards({ kind: 'type', type: 'gt' });
		await saveSettings({ activeQualities: ['maj7', 'm7', '7', 'm7b5', 'mMaj7'] });
		const view = await deckCards({ kind: 'type', type: 'gt' });
		expect(view.total).toBe(before.total - 12);
		expect(view.groups[0].cards.some((c) => c.id.endsWith(':dim7'))).toBe(false);
		expect(view.counts.unseen).toBe(view.total);

		// A progression needs every chord in it, so switching maj7 off empties the
		// whole major chain deck rather than trimming it.
		await saveSettings({ activeQualities: ['m7', '7'] });
		const chains = await deckCards({ kind: 'type', type: 'chain' });
		expect(chains.total).toBe(0);
	});

	// The path suggests an order; it does not hide the cards from someone who
	// wants to look at what is coming.
	it('shows a deck that is ahead of the path', async () => {
		await saveSettings({ unlockedStages: 1 });
		const ahead = await deckCards({ kind: 'stage', section: 'theory', n: 3 });
		expect(ahead.total).toBeGreaterThan(0);
	});
});
