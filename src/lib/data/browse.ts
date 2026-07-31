/**
 * Looking inside a deck.
 *
 * Every other screen answers "what should I do now"; this one answers "what is
 * in here, and how am I doing on it" — which is the question you ask when
 * something feels weak and you want to see whether it actually is.
 *
 * It shows each card exactly as the drill poses it — prompt, instruction and
 * answer together — which is what makes it useful for checking your own deck:
 * "what does this card actually ask, and what does it want back". That is the
 * one place in the app where the two appear side by side, and it is a
 * deliberate exception rather than an oversight. The drill itself still never
 * shows them together, and this screen is not on the way to a session.
 *
 * An ear card's question is a sound, so those rows carry the sound rather than
 * a description of it — printing "two notes, low to high" is not showing the
 * question.
 */

import { db } from '$lib/db';
import {
	parseCardId,
	renderCard,
	CARD_TYPE_LABEL,
	type CardType
} from '$lib/music/cards';
import { MASTERY_LABEL, type Mastery } from '$lib/scheduler/grading';
import { getSettings } from './settings';
import { qualityActive } from './queue';
import { deckEmptyReason, liveDeckTypes, type DeckBlock, type DeckRef } from './decks';

export interface BrowseCard {
	id: string;
	type: CardType;
	/** What the drill shows you — the prompt, never the answer. */
	title: string;
	instruction: string;
	answerText: string;
	/** The card's prompt IS this sound (the ear decks), so the row can play it. */
	promptIsSound: boolean;
	/** Note groups to sound, for any card that has them. */
	sound: number[][] | null;
	/**
	 * Set when the title alone does not identify the card inside its own group:
	 * the extensions deck lists C7 five times, once per colour, and five
	 * identical rows with different states is a list you cannot read.
	 */
	qualifier: string | null;
	mastery: Mastery | 'unseen';
	dueAt: number | null;
	/** True when it is due now, which is what the list sorts and filters on. */
	due: boolean;
	medianResponseMs: number | null;
	reps: number;
	lapses: number;
}

export interface BrowseGroup {
	type: CardType;
	label: string;
	/**
	 * Set when every card in the group asks the same way — the ear decks all say
	 * "two notes, low to high", and printing that on 132 rows is 132 lines of
	 * the same sentence between you and the answers you came to read.
	 */
	sharedInstruction: string | null;
	cards: BrowseCard[];
}

export interface DeckBrowse {
	groups: BrowseGroup[];
	total: number;
	counts: { unseen: number; new: number; familiar: number; automatic: number; due: number };
	/** Why the deck is empty, when it is, in the same terms the pickers use. */
	block: DeckBlock;
}

/**
 * The cards a deck can deal, with their state, grouped by drill.
 *
 * Drawn from the same `liveDeckTypes` every other screen uses and filtered
 * through the same `qualityActive` the queue and the deck counts apply, so a
 * drill switched off in Settings — or a chord quality — is absent here too. A
 * browser that lists cards the session will never deal is describing a
 * different app than the one running, and it is reached by tapping a count that
 * was computed with both gates on.
 */
export async function deckCards(deck: DeckRef, now = Date.now()): Promise<DeckBrowse> {
	const conn = await db();
	const settings = await getSettings();
	const types = liveDeckTypes(deck, settings);
	if (types.length === 0) {
		return {
			groups: [],
			total: 0,
			counts: { unseen: 0, new: 0, familiar: 0, automatic: 0, due: 0 },
			block: deckEmptyReason(deck, settings)
		};
	}

	// One query for the whole deck, in catalogue order: a deck reads drill by
	// drill and chromatically inside each, which is a stable order the deck
	// itself defines rather than an alphabetical shuffle of its ids. It is not
	// the queue's introduction order — that is circle-of-fourths — because this
	// screen is for checking a deck, not for predicting what it deals next.
	const rows = await conn.all<{
		id: string;
		type: string;
		quality: string | null;
		mastery: Mastery | null;
		due: number | null;
		med: number | null;
		reps: number | null;
		lapses: number | null;
	}>(
		`SELECT c.id, c.type, c.quality, s.mastery, s.due, s.median_response_ms AS med, s.reps, s.lapses
		   FROM cards c LEFT JOIN card_state s ON s.card_id = c.id
		  ORDER BY c.rowid`
	);

	const counts = { unseen: 0, new: 0, familiar: 0, automatic: 0, due: 0 };
	const groups = new Map<CardType, BrowseCard[]>();
	for (const type of types) groups.set(type, []);

	for (const row of rows) {
		const type = row.type as CardType;
		if (!groups.has(type)) continue;
		if (!qualityActive(row, settings)) continue;
		const spec = parseCardId(row.id);
		// A row the catalogue can no longer render belongs to a card type this
		// build has dropped; the session would skip it too.
		if (!spec) continue;
		const view = renderCard(spec);
		// Not just NULL: nothing constrains the column to the three states, and an
		// imported backup writes whatever its file said. An unknown state reaching
		// MASTERY_LABEL renders the whole screen as an error page, so it is read
		// as the state a card with nothing known about it is in. Own properties
		// only — `in` also answers yes to 'toString', which then renders a
		// function and throws exactly the error this guard exists to prevent.
		const mastery =
			row.mastery && Object.hasOwn(MASTERY_LABEL, row.mastery) ? row.mastery : 'unseen';
		const due = row.due !== null && row.due <= now;
		counts[mastery] += 1;
		if (due) counts.due += 1;
		groups.get(type)!.push({
			id: row.id,
			type,
			title: view.title,
			instruction: view.instruction,
			answerText: view.answerText,
			promptIsSound: !!view.promptIsSound,
			sound: view.sound?.groups ?? null,
			qualifier: null,
			mastery,
			dueAt: row.due,
			due,
			medianResponseMs: row.med,
			reps: row.reps ?? 0,
			lapses: row.lapses ?? 0
		});
	}

	// Only where it actually tells two rows apart. A repeated title is not
	// enough on its own: every interval-by-ear card is called "Listen" and asks
	// in exactly the same words, so the instruction distinguishes nothing there
	// and would print the same sentence on 132 rows. What separates those is the
	// answer, which is on the row anyway.
	for (const cards of groups.values()) {
		const byTitle = new Map<string, BrowseCard[]>();
		for (const c of cards) {
			const list = byTitle.get(c.title);
			if (list) list.push(c);
			else byTitle.set(c.title, [c]);
		}
		for (const sharing of byTitle.values()) {
			if (sharing.length < 2) continue;
			const varies = sharing.some((c) => c.instruction !== sharing[0].instruction);
			if (varies) for (const c of sharing) c.qualifier = c.instruction;
		}
	}

	const ordered: BrowseGroup[] = types
		.map((type) => {
			const cards = groups.get(type) ?? [];
			const first = cards[0]?.instruction ?? '';
			const shared = cards.length > 1 && cards.every((c) => c.instruction === first);
			return {
				type,
				label: CARD_TYPE_LABEL[type],
				sharedInstruction: shared ? first : null,
				cards
			};
		})
		.filter((g) => g.cards.length > 0);

	const total = ordered.reduce((n, g) => n + g.cards.length, 0);
	return {
		groups: ordered,
		total,
		counts,
		block: total === 0 ? deckEmptyReason(deck, settings) : null
	};
}
