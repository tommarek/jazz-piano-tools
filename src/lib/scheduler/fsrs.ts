/**
 * FSRS wrapper.
 *
 * Kept free of any database or SvelteKit import so the 365-day back-test can
 * drive the exact same code path the app uses.
 */

import { createEmptyCard, fsrs, State, type Card, type Grade } from 'ts-fsrs';

export const REQUEST_RETENTION = 0.9;
export const MAXIMUM_INTERVAL = 365;

const schedulers = new Map<number, ReturnType<typeof fsrs>>();

function schedulerFor(requestRetention: number) {
	let s = schedulers.get(requestRetention);
	if (!s) {
		s = fsrs({
			request_retention: requestRetention,
			maximum_interval: MAXIMUM_INTERVAL,
			enable_fuzz: true
		});
		schedulers.set(requestRetention, s);
	}
	return s;
}

/** The persisted shape of a card's scheduling state. Times are epoch millis. */
export interface SchedulerState {
	due: number;
	stability: number;
	difficulty: number;
	elapsedDays: number;
	scheduledDays: number;
	learningSteps: number;
	reps: number;
	lapses: number;
	/** ts-fsrs State enum: 0 New, 1 Learning, 2 Review, 3 Relearning */
	state: number;
	lastReview: number | null;
}

function toCard(s: SchedulerState): Card {
	return {
		due: new Date(s.due),
		stability: s.stability,
		difficulty: s.difficulty,
		elapsed_days: s.elapsedDays,
		scheduled_days: s.scheduledDays,
		learning_steps: s.learningSteps,
		reps: s.reps,
		lapses: s.lapses,
		state: s.state as State,
		last_review: s.lastReview === null ? undefined : new Date(s.lastReview)
	};
}

function fromCard(c: Card): SchedulerState {
	return {
		due: c.due.getTime(),
		stability: c.stability,
		difficulty: c.difficulty,
		elapsedDays: c.elapsed_days,
		scheduledDays: c.scheduled_days,
		learningSteps: c.learning_steps,
		reps: c.reps,
		lapses: c.lapses,
		state: c.state,
		lastReview: c.last_review ? c.last_review.getTime() : null
	};
}

export function newSchedulerState(now: Date): SchedulerState {
	return fromCard(createEmptyCard(now));
}

export function applyReview(
	state: SchedulerState,
	grade: Grade,
	now: Date,
	requestRetention = REQUEST_RETENTION
): SchedulerState {
	const { card } = schedulerFor(requestRetention).next(toCard(state), now, grade);
	return fromCard(card);
}

/**
 * Ceiling on the interval of a card that has not yet passed the time gate.
 *
 * FSRS optimises for eventual recall, not for speed, so it will happily push a
 * card you answer correctly-but-slowly out to a year. That card would then
 * never get the frequent exposure that turns recall into retrieval — the one
 * thing this deck exists to build. Until a card is 'automatic', it comes back
 * inside three weeks whatever the model says.
 */
export const MAX_DAYS_BEFORE_AUTOMATIC = 21;

export function capUntilAutomatic(
	state: SchedulerState,
	isAutomatic: boolean,
	now: Date
): SchedulerState {
	if (isAutomatic) return state;
	const cap = now.getTime() + MAX_DAYS_BEFORE_AUTOMATIC * 86_400_000;
	if (state.due <= cap) return state;
	return { ...state, due: cap, scheduledDays: MAX_DAYS_BEFORE_AUTOMATIC };
}

/** Probability the card would be recalled right now, 0..1. */
export function retrievability(
	state: SchedulerState,
	now: Date,
	requestRetention = REQUEST_RETENTION
): number {
	if (state.state === State.New) return 0;
	return schedulerFor(requestRetention).get_retrievability(toCard(state), now, false);
}

export { State };
