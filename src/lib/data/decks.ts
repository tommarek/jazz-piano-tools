/**
 * Decks: a way to point a session at one part of the catalogue.
 *
 * The default is still everything due, and it is the default on purpose —
 * blocking one drill type feels productive and transfers worse than the mixed
 * queue does. What a deck is for is the case the mixed queue is bad at: a
 * specific weakness you already know about, and the twenty minutes where you
 * want to hammer it. Choosing one is a per-session decision, not a mode the
 * app sits in, so the next session is mixed again unless you say otherwise.
 *
 * A deck is a whole section, a stage of that section's path (the three or four
 * drills that belong together, so interleaving survives inside it), or a single
 * drill type. Nothing here owns scheduling or history: review state is keyed on
 * the card id and a deck is only ever a filter over which cards may be dealt.
 */

import {
	CARD_TYPES,
	CARD_TYPE_LABEL,
	EAR_TYPES,
	SECTION_LABEL,
	SECTION_OF_TYPE,
	STAGE_OF_TYPE,
	stagesOf,
	type CardType,
	type Section
} from '$lib/music/cards';
import { effectiveCardTypes, openStages, type Settings } from './settings';

/**
 * A deck is always inside one section: theory and ear are separate practices
 * and nothing deals across them.
 */
export type DeckRef =
	| { kind: 'section'; section: Section }
	| { kind: 'stage'; section: Section; n: number }
	| { kind: 'type'; type: CardType };

export const ALL_DECK: DeckRef = { kind: 'section', section: 'theory' };
export const EAR_DECK: DeckRef = { kind: 'section', section: 'ear' };

/** The URL form. Kept short and stable — it ends up in a shared link. */
export function deckSlug(deck: DeckRef): string {
	if (deck.kind === 'stage') return deck.section === 'ear' ? `ear-stage-${deck.n}` : `stage-${deck.n}`;
	if (deck.kind === 'type') return deck.type;
	return deck.section;
}

/** Which half of the app a deck belongs to. */
export function deckSection(deck: DeckRef): Section {
	if (deck.kind === 'type') return SECTION_OF_TYPE[deck.type];
	return deck.section;
}

/**
 * Anything unrecognised is the everything deck rather than an error: a stale
 * link or a drill type removed in a later version should start a session, not
 * strand someone on a broken screen.
 */
export function parseDeckSlug(slug: string | null | undefined): DeckRef {
	// 'all' predates the split, when one queue covered both halves. It maps to
	// the theory section, which is what that link's owner was looking at.
	if (!slug || slug === 'all' || slug === 'theory') return ALL_DECK;
	if (slug === 'ear') return EAR_DECK;
	// The number has to name a stage that exists: 'stage-9' is a typo or a link
	// from a version with a longer path, and both are better served by a session
	// than by a deck that can never deal anything.
	const staged = (section: Section, n: number): DeckRef | null =>
		stagesOf(section).some((st) => st.n === n) ? { kind: 'stage', section, n } : null;
	const ear = /^ear-stage-(\d+)$/.exec(slug);
	if (ear) return staged('ear', Number(ear[1])) ?? ALL_DECK;
	const stage = /^stage-(\d+)$/.exec(slug);
	if (stage) return staged('theory', Number(stage[1])) ?? ALL_DECK;
	if ((CARD_TYPES as readonly string[]).includes(slug)) return { kind: 'type', type: slug as CardType };
	return ALL_DECK;
}

export function deckLabel(deck: DeckRef): string {
	if (deck.kind === 'section') return SECTION_LABEL[deck.section];
	if (deck.kind === 'type') return CARD_TYPE_LABEL[deck.type];
	return stagesOf(deck.section).find((s) => s.n === deck.n)?.title ?? `Stage ${deck.n}`;
}

/** The card types a deck names, before any of the settings gates apply. */
export function deckTypes(deck: DeckRef): CardType[] {
	if (deck.kind === 'section')
		return CARD_TYPES.filter((t) => SECTION_OF_TYPE[t] === deck.section);
	if (deck.kind === 'type') return [deck.type];
	return [...(stagesOf(deck.section).find((s) => s.n === deck.n)?.types ?? [])];
}

/**
 * What the deck can actually deal.
 *
 * Two different filters, and which apply depends on how the deck was chosen.
 *
 * A *section* deck is the daily mix, so the path shapes it: a stage that has
 * not opened stays out, which is the whole point of having a path. Naming a
 * stage or a drill is an explicit decision to work on that thing, and the path
 * was never meant to forbid it — it is a suggested order, not a lock, and
 * Settings could always open any stage by hand. Refusing to deal a deck the
 * learner just tapped turned the suggestion into a wall, and left the picker
 * showing four rows of which three did nothing.
 *
 * What no deck can do is deal a drill that is switched off, or an ear drill
 * with the sound off — those are not "not yet", they are "there is no card
 * here to show you".
 */
export function liveDeckTypes(deck: DeckRef, settings: Settings): CardType[] {
	const gated = deck.kind === 'section' ? effectiveCardTypes(settings) : settings.activeCardTypes;
	return deckTypes(deck).filter(
		(t) => gated.includes(t) && (settings.soundEnabled || !EAR_TYPES.includes(t))
	);
}

/**
 * Why a deck cannot be dealt, for a screen that has to say so. 'qualities' —
 * the drills are on but the quality switches leave no card inside them — is
 * the one reason settings alone cannot tell: `deckCounts` adds it, because it
 * is the only caller holding the cards.
 */
export type DeckBlock = 'off' | 'sound' | 'qualities' | null;

export function deckBlock(deck: DeckRef, settings: Settings): DeckBlock {
	if (deck.kind === 'section') return null;
	if (liveDeckTypes(deck, settings).length > 0) return null;
	return deckEmptyReason(deck, settings);
}

/**
 * Why a deck has nothing at all, for a screen that has to say so rather than
 * offer a row. `deckBlock` speaks only for a named deck — a section is never
 * "blocked" in the picker, it is the picker — so a whole section (/deck/ear,
 * a section session) is reasoned about from its own types the same way.
 * Blaming the drill switches for a deck emptied by the sound switch sends the
 * learner to the wrong screen.
 */
export function deckEmptyReason(deck: DeckRef, settings: Settings): DeckBlock {
	const all = deckTypes(deck);
	if (!settings.soundEnabled && all.length > 0 && all.every((t) => EAR_TYPES.includes(t)))
		return 'sound';
	return liveDeckTypes(deck, settings).length === 0 ? 'off' : 'qualities';
}

/**
 * Whether a deck sits past the point the path has reached. Not a block — it can
 * be drilled on request — but worth saying, because its cards will not join the
 * daily mix until the stage opens, and a learner who practises them and then
 * never sees them again deserves to know why.
 */
export function deckAhead(deck: DeckRef, settings: Settings): boolean {
	const types = liveDeckTypes(deck, settings);
	return (
		types.length > 0 &&
		types.every((t) => STAGE_OF_TYPE[t] > openStages(settings, SECTION_OF_TYPE[t]))
	);
}
