/**
 * Turning an attempt into an FSRS grade.
 *
 * Response time is the real signal for this deck. Getting a guide-tone pair
 * right after six seconds of working it out is exactly the state the drill
 * exists to fix, so slow-and-correct must not be scheduled like
 * fast-and-correct, and must never graduate a card to "automatic".
 */

import { Rating, type Grade } from 'ts-fsrs';
import type { CardType } from '$lib/music/cards';
import { TIME_TARGETS } from '$lib/music/cards';

export type Mastery = 'new' | 'familiar' | 'automatic';

/** A correct answer this much slower than the card's median counts as Hard. */
export const HARD_RATIO = 2.0;
/** A correct answer this much faster than the card's median counts as Easy. */
export const EASY_RATIO = 0.6;

/** Consecutive correct answers needed to leave 'new'. */
export const FAMILIAR_STREAK = 3;
/** Consecutive correct answers needed to reach 'automatic'. */
export const AUTOMATIC_STREAK = 5;

/** How many recent reviews the rolling median is taken over. */
export const MEDIAN_WINDOW = 10;

export function median(values: number[]): number | null {
	if (values.length === 0) return null;
	const sorted = [...values].sort((a, b) => a - b);
	const mid = Math.floor(sorted.length / 2);
	return sorted.length % 2 === 1 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
}

/** Rolling median over the most recent {@link MEDIAN_WINDOW} correct attempts. */
export function rollingMedian(recentCorrectMs: number[]): number | null {
	return median(recentCorrectMs.slice(-MEDIAN_WINDOW));
}

export interface GradeInput {
	correct: boolean;
	responseMs: number;
	/** Rolling median for this card; null until it has any correct history. */
	medianMs: number | null;
	cardType: CardType;
}

export function deriveGrade({ correct, responseMs, medianMs, cardType }: GradeInput): Grade {
	if (!correct) return Rating.Again;
	// With no history of its own, a card is judged against the type's baseline.
	const reference = medianMs ?? TIME_TARGETS[cardType].baseline;
	if (responseMs > reference * HARD_RATIO) return Rating.Hard;
	if (responseMs < reference * EASY_RATIO) return Rating.Easy;
	return Rating.Good;
}

export interface MasteryInput {
	consecutiveCorrect: number;
	medianMs: number | null;
	cardType: CardType;
}

/**
 * Mastery is a UI-facing progress label, computed from the streak and the
 * median rather than advanced as a state machine of its own. It is still
 * persisted, in `card_state.mastery`, and re-derived only when that card comes
 * up again: tightening a time gate re-labels a card at its next review, which
 * for one already sitting at 'automatic' can be MAXIMUM_INTERVAL away.
 */
export function deriveMastery({
	consecutiveCorrect,
	medianMs,
	cardType
}: MasteryInput): Mastery {
	const target = TIME_TARGETS[cardType].automatic;
	if (consecutiveCorrect >= AUTOMATIC_STREAK && medianMs !== null && medianMs < target) {
		return 'automatic';
	}
	if (consecutiveCorrect >= FAMILIAR_STREAK) return 'familiar';
	return 'new';
}

/**
 * Every screen that names a mastery state reads this, so the wording cannot
 * drift between the deck browser and Progress. 'unseen' is not a Mastery — a
 * card with no state row has none — but it is the fourth label every such list
 * needs.
 */
export const MASTERY_LABEL: Record<Mastery | 'unseen', string> = {
	unseen: 'Not started',
	// Displayed as "Learning", not "New": everywhere else in the app (and in
	// every other SRS) "new" means never seen, and this state means the
	// opposite — seen, but the streak is still under three.
	new: 'Learning',
	familiar: 'Familiar',
	automatic: 'Automatic'
};
