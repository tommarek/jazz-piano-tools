/**
 * Decks: what a session gets when it is pointed at one part of the catalogue.
 *
 * The load-bearing property is that a deck NARROWS and never widens. Every gate
 * the settings apply — a locked stage, a switched-off drill, the ear decks with
 * sound off — has to survive a deck being named, because the deck arrives in a
 * URL and a URL is the one input the app does not control.
 */

import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db } from '../../src/lib/db';
import { buildQueue, deckCounts, eligibleIds } from '../../src/lib/data/queue';
import { DEFAULT_SETTINGS, saveSettings, type Settings } from '../../src/lib/data/settings';
import {
	deckAhead,
	deckBlock,
	deckLabel,
	deckSlug,
	deckTypes,
	liveDeckTypes,
	parseDeckSlug,
	type DeckRef
} from '../../src/lib/data/decks';
import { CARD_TYPES, SECTION_OF_TYPE, STAGES } from '../../src/lib/music/cards';

beforeAll(async () => {
	await useMemoryDb();
});

afterAll(async () => {
	await (await db()).close();
});

beforeEach(async () => {
	const conn = await db();
	await conn.exec('DELETE FROM settings');
	await conn.exec('DELETE FROM card_state');
	await conn.exec('DELETE FROM reviews');
});

const settings = (patch: Partial<Settings> = {}): Settings => ({
	...DEFAULT_SETTINGS,
	unlockedStages: 3,
	...patch
});

describe('deck slugs', () => {
	it('round-trip through the URL form', () => {
		const decks: DeckRef[] = [
			{ kind: 'section', section: 'theory' },
			{ kind: 'stage', section: 'theory', n: 3 },
			{ kind: 'type', type: 'rootless' }
		];
		for (const deck of decks) expect(parseDeckSlug(deckSlug(deck))).toEqual(deck);
	});

	// 'all' is the slug from before the split, and it is a branch of its own
	// rather than a case the fallback happens to catch: a link written then was
	// pointing at the queue that is now Theory, and it must still land there if
	// an unknown slug ever becomes an error the way /deck/[slug] treats one.
	it('resolve the pre-split slug to the theory section', () => {
		expect(parseDeckSlug('all')).toEqual({ kind: 'section', section: 'theory' });
		expect(parseDeckSlug('ear')).toEqual({ kind: 'section', section: 'ear' });
	});

	// A shared link outlives the version that wrote it, and a drill type can be
	// renamed. Starting the mixed session beats stranding someone on an error.
	it('fall back to everything rather than failing', () => {
		for (const slug of [null, undefined, '', 'stage-9', 'stage-0', 'nonsense', 'STAGE-1']) {
			expect(parseDeckSlug(slug)).toEqual({ kind: 'section', section: 'theory' });
		}
	});

	it('name every stage and every drill', () => {
		for (const stage of STAGES) {
			expect(deckLabel({ kind: 'stage', section: 'theory', n: stage.n })).toBe(stage.title);
			expect(deckTypes({ kind: 'stage', section: 'theory', n: stage.n })).toEqual(stage.types);
		}
		for (const type of CARD_TYPES) expect(deckLabel({ kind: 'type', type })).toBeTruthy();
	});

	// Spelled out rather than derived from EAR_TYPES: writing the expectation as
	// the implementation's own filter makes this pass however the two sections
	// are divided, which is the one thing it is here to hold still.
	it('put every drill in the section it belongs to', () => {
		expect(deckTypes({ kind: 'section', section: 'theory' })).toEqual([
			'chain',
			'gt',
			'gtn',
			'gtc',
			'rootless',
			'rlc',
			'ext',
			'dia',
			'ivl',
			'mode'
		]);
		expect(deckTypes({ kind: 'section', section: 'ear' })).toEqual(['eint', 'eqal']);
		for (const type of CARD_TYPES) {
			expect(SECTION_OF_TYPE[type]).toBe(type === 'eint' || type === 'eqal' ? 'ear' : 'theory');
		}
	});
});

describe('the path shapes the mix, not what you may choose', () => {
	// The path is a suggested order, not a lock — Settings could always open any
	// stage by hand. So a deck NAMED by the learner is dealt, and only the daily
	// mix is held to the path. The picker showing rows that do nothing was the
	// suggestion behaving like a wall.
	it('deals a stage that has not opened yet, when it is asked for by name', () => {
		const s = settings({ unlockedStages: 1 });
		expect(liveDeckTypes({ kind: 'stage', section: 'theory', n: 3 }, s)).toEqual([
			'rootless',
			'rlc',
			'ext',
			'mode'
		]);
		expect(liveDeckTypes({ kind: 'type', type: 'rootless' }, s)).toEqual(['rootless']);
		// Not blocked, but flagged: its cards will not join the mix until the
		// stage opens, and practising something that then vanishes is confusing.
		expect(deckBlock({ kind: 'stage', section: 'theory', n: 3 }, s)).toBe(null);
		expect(deckAhead({ kind: 'stage', section: 'theory', n: 3 }, s)).toBe(true);
		expect(deckAhead({ kind: 'stage', section: 'theory', n: 1 }, s)).toBe(false);
	});

	it('still keeps an unopened stage out of the daily mix', async () => {
		const s = settings({ unlockedStages: 1 });
		// The section deck IS the mix, and it is the one place the path applies.
		const mix = liveDeckTypes({ kind: 'section', section: 'theory' }, s);
		expect(mix).not.toContain('rootless');
		expect(mix).toContain('gt');

		const ids = await eligibleIds(s, { kind: 'section', section: 'theory' });
		expect([...ids].some((id) => id.startsWith('rootless:'))).toBe(false);
	});

	it('cannot reach a drill switched off in settings', () => {
		const s = settings({ activeCardTypes: ['gt'] });
		expect(liveDeckTypes({ kind: 'type', type: 'ivl' }, s)).toEqual([]);
		expect(deckBlock({ kind: 'type', type: 'ivl' }, s)).toBe('off');
		// The stage above it still deals what is left on.
		expect(liveDeckTypes({ kind: 'stage', section: 'theory', n: 1 }, s)).toEqual(['gt']);
		expect(deckBlock({ kind: 'stage', section: 'theory', n: 1 }, s)).toBe(null);
	});

	it('cannot reach an ear drill with sound off — its prompt would not exist', () => {
		const s = settings({ soundEnabled: false });
		expect(liveDeckTypes({ kind: 'type', type: 'eint' }, s)).toEqual([]);
		expect(deckBlock({ kind: 'type', type: 'eint' }, s)).toBe('sound');
		expect(deckBlock({ kind: 'type', type: 'gt' }, s)).toBe(null);
	});

	it('deals only the deck it was given', async () => {
		const s = settings();
		const ids = await eligibleIds(s, { kind: 'type', type: 'mode' });
		expect(ids.size).toBeGreaterThan(0);
		for (const id of ids) expect(id.startsWith('mode:')).toBe(true);

		const stage1 = await eligibleIds(s, { kind: 'stage', section: 'theory', n: 1 });
		const types = new Set([...stage1].map((id) => id.split(':')[0]));
		expect([...types].sort()).toEqual([...STAGES[0].types].sort());

		// And the everything deck is still everything.
		const all = await eligibleIds(s);
		expect(all.size).toBeGreaterThan(stage1.size);
	});

	it('builds a session out of one drill only', async () => {
		await saveSettings(settings({ newCardsPerDay: 20 }));
		const queue = await buildQueue({ deck: { kind: 'type', type: 'ivl' } });
		expect(queue.length).toBeGreaterThan(0);
		for (const item of queue) expect(item.card.type).toBe('ivl');
	});

	it('builds a session ahead of the path when one is asked for', async () => {
		await saveSettings(settings({ unlockedStages: 1, newCardsPerDay: 20 }));
		const ahead = await buildQueue({ deck: { kind: 'stage', section: 'theory', n: 3 } });
		expect(ahead.length).toBeGreaterThan(0);
		expect(ahead.every((i) => ['rootless', 'rlc', 'ext', 'mode'].includes(i.card.type))).toBe(true);
		// And the mix that same learner gets is still stage 1 only.
		const mix = await buildQueue({ deck: { kind: 'section', section: 'theory' } });
		expect(mix.every((i) => ['gt', 'gtn', 'ivl'].includes(i.card.type))).toBe(true);
	});

	// A drill switched off is not "not yet": there is no card to show at all,
	// and no amount of choosing makes one.
	it('deals nothing from a drill that is switched off', async () => {
		await saveSettings(settings({ activeCardTypes: ['gt'], newCardsPerDay: 20 }));
		expect(await buildQueue({ deck: { kind: 'type', type: 'ivl' } })).toEqual([]);
	});
});

describe('the counts on the picker', () => {
	it('add up to what the deck can actually deal', async () => {
		const conn = await db();
		await saveSettings(settings({ newCardsPerDay: 8 }));
		// One due card in every stage, or the due half of the sum is 0 = 0 and
		// holds however wrongly the counts attribute a due card.
		for (const stage of STAGES) {
			const card = (await conn.get<{ id: string }>(
				'SELECT id FROM cards WHERE type = ? ORDER BY rowid LIMIT 1',
				[stage.types[0]]
			))!;
			await conn.run(
				`INSERT INTO card_state (card_id, due, stability, difficulty, reps, lapses, state, mastery)
				 VALUES (?, ?, 1, 5, 1, 0, 2, 'new')`,
				[card.id, Date.now() - 1000]
			);
		}
		const { stages, types } = await deckCounts();

		expect(stages).toHaveLength(STAGES.length);
		for (const stage of STAGES) {
			const row = stages.find((d) => d.slug === `stage-${stage.n}`)!;
			const drills = types[stage.n];
			expect(drills.map((d) => d.slug).sort()).toEqual([...stage.types].sort());
			// A stage is its drills: counting them separately would let the two
			// disagree on the same screen.
			expect(row.size).toBe(drills.reduce((n, d) => n + d.size, 0));
			expect(row.due).toBe(1);
			expect(row.due).toBe(drills.reduce((n, d) => n + d.due, 0));
		}
	});

	it('offers a stage ahead of the path, marked as ahead', async () => {
		await saveSettings(settings({ unlockedStages: 1 }));
		const { stages } = await deckCounts();
		const ahead = stages.find((d) => d.slug === 'stage-3')!;
		expect(ahead.block).toBe(null);
		expect(ahead.ahead).toBe(true);
		expect(ahead.size).toBeGreaterThan(0);
		const open = stages.find((d) => d.slug === 'stage-1')!;
		expect(open.ahead).toBe(false);
	});

	it('says so when the qualities, not the drills, empty a deck', async () => {
		// The chain needs m7, 7 and maj7 together. Counting by card type alone,
		// the row advertised its whole 24 and then dealt nothing — the exact
		// thing the picker's "block" reason exists to prevent.
		await saveSettings(
			settings({ activeQualities: ['maj7', 'm7', 'm7b5', 'dim7', 'mMaj7'], newCardsPerDay: 8 })
		);
		const { types } = await deckCounts();
		const chain = types[2].find((d) => d.slug === 'chain')!;
		expect(chain.size).toBe(0);
		expect(chain.new).toBe(0);
		expect(chain.block).toBe('qualities');
		expect(await buildQueue({ deck: { kind: 'type', type: 'chain' } })).toEqual([]);
	});

	it('counts a due card against exactly one deck', async () => {
		const conn = await db();
		await saveSettings(settings({ newCardsPerDay: 0 }));
		await conn.run(
			`INSERT INTO card_state (card_id, due, stability, difficulty, reps, lapses, state, mastery)
			 VALUES ('ivl:C:P5', ?, 1, 5, 1, 0, 2, 'new')`,
			[Date.now() - 1000]
		);
		const { stages, types } = await deckCounts();
		expect(types[1].find((d) => d.slug === 'ivl')!.due).toBe(1);
		expect(types[1].find((d) => d.slug === 'gt')!.due).toBe(0);
		expect(stages.find((d) => d.slug === 'stage-1')!.due).toBe(1);
		expect(stages.find((d) => d.slug === 'stage-2')!.due).toBe(0);
	});
});
