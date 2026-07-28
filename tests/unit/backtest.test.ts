/**
 * Scheduler back-test.
 *
 * Runs a synthetic learner through 630 days of the real scheduler and asserts
 * the properties that are otherwise invisible for months: that the intervals
 * deliver the retention they promise, that the daily load does not blow up, and
 * that the mastery gate cannot be passed by a slow learner.
 *
 * Honest limitation on the retention assertion: the learner forgets according
 * to FSRS's own forgetting curve, parameterised by the stability the scheduler
 * itself is tracking. That makes it a test of *configuration and interval
 * arithmetic* — request_retention actually being honoured — and not a test of
 * whether FSRS models human memory. The load and starvation assertions do not
 * depend on that assumption.
 */

import { describe, expect, it } from 'vitest';
import { default_w, forgetting_curve, State, type Grade } from 'ts-fsrs';
import {
	applyReview,
	capUntilAutomatic,
	newSchedulerState,
	MAX_DAYS_BEFORE_AUTOMATIC,
	REQUEST_RETENTION
} from '../../src/lib/scheduler/fsrs';
import { deriveGrade, deriveMastery, rollingMedian } from '../../src/lib/scheduler/grading';
import { buildCatalogue } from '../../src/lib/music/cards';
import type { SchedulerState } from '../../src/lib/scheduler/fsrs';
import type { CardType } from '../../src/lib/music/cards';

const DAY = 86_400_000;
const START = Date.UTC(2026, 0, 1);
// 21 months, not 12: the deck grew to 1296 cards, and at the shipped 8-a-day
// pace plus review load a full introduction takes ~19 months. The invariant
// is that it completes and the load stays flat — not that it fits a year.
const DAYS = 630;
/** Same cap the app ships with, so the simulation feels the same ceiling. */
const NEW_PER_DAY = 8;
const SESSION_CAP = 30;

/** Deterministic RNG — a fixed seed makes every assertion reproducible. */
function mulberry32(seed: number) {
	return function () {
		seed |= 0;
		seed = (seed + 0x6d2b79f5) | 0;
		let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
		t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

interface SimCard {
	id: string;
	type: CardType;
	state: SchedulerState;
	introduced: boolean;
	correctTimes: number[];
	consecutiveCorrect: number;
	lastReviewDay: number;
	mastery: string;
}

interface SimResult {
	cards: SimCard[];
	dailyLoad: number[];
	scheduledAttempts: number;
	scheduledCorrect: number;
	/** Longest gap in days between reviews, for a card that was not yet automatic. */
	worstStarvationDays: number;
}

interface Learner {
	/** Response time in ms for a card the learner recalls. */
	responseMs: (rng: () => number, type: CardType) => number;
	/** Overrides recall probability; defaults to the FSRS forgetting curve. */
	recall?: (card: SimCard, elapsedDays: number, rng: () => number) => boolean;
}

function simulate(learner: Learner, seed: number): SimResult {
	const rng = mulberry32(seed);
	const catalogue = buildCatalogue();
	const cards: SimCard[] = catalogue.map((spec) => ({
		id: spec.id,
		type: spec.type,
		state: newSchedulerState(new Date(START)),
		introduced: false,
		correctTimes: [],
		consecutiveCorrect: 0,
		lastReviewDay: -1,
		mastery: 'new'
	}));

	const dailyLoad: number[] = [];
	let scheduledAttempts = 0;
	let scheduledCorrect = 0;
	let worstStarvationDays = 0;

	for (let day = 0; day < DAYS; day++) {
		const now = new Date(START + day * DAY);
		const nowMs = now.getTime();

		const due = cards.filter((c) => c.introduced && c.state.due <= nowMs);
		// Mirrors buildQueue: new cards only fill what the due pile leaves free.
		const room = Math.max(0, SESSION_CAP - due.length);
		const fresh = cards
			.filter((c) => !c.introduced)
			.slice(0, Math.min(NEW_PER_DAY, room));
		const todays = [...due, ...fresh].slice(0, SESSION_CAP);

		for (const card of todays) {
			const wasIntroduced = card.introduced;
			card.introduced = true;

			const elapsedDays = card.state.lastReview
				? (nowMs - card.state.lastReview) / DAY
				: 0;

			let recalled: boolean;
			if (!wasIntroduced) {
				// First sight of a card: the learner does not know it yet.
				recalled = false;
			} else if (learner.recall) {
				recalled = learner.recall(card, elapsedDays, rng);
			} else {
				// The default weights, not [REQUEST_RETENTION] — this overload wants
				// the full FSRS parameter vector and silently yields NaN otherwise.
				const p = forgetting_curve(
					default_w,
					elapsedDays,
					Math.max(0.1, card.state.stability)
				);
				recalled = rng() < p;
			}

			if (wasIntroduced && card.state.state === State.Review) {
				scheduledAttempts += 1;
				if (recalled) scheduledCorrect += 1;
				if (card.lastReviewDay >= 0 && card.mastery !== 'automatic') {
					worstStarvationDays = Math.max(worstStarvationDays, day - card.lastReviewDay);
				}
			}

			const responseMs = recalled ? learner.responseMs(rng, card.type) : 20_000;
			const priorMedian = rollingMedian(card.correctTimes);
			const grade: Grade = deriveGrade({
				correct: recalled,
				responseMs,
				medianMs: priorMedian,
				cardType: card.type
			});

			const scheduled = applyReview(card.state, grade, now);
			card.consecutiveCorrect = recalled ? card.consecutiveCorrect + 1 : 0;
			if (recalled) card.correctTimes.push(responseMs);
			card.mastery = deriveMastery({
				consecutiveCorrect: card.consecutiveCorrect,
				medianMs: rollingMedian(card.correctTimes),
				cardType: card.type
			});
			card.state = capUntilAutomatic(scheduled, card.mastery === 'automatic', now);
			card.lastReviewDay = day;
		}

		dailyLoad.push(todays.length);
	}

	return { cards, dailyLoad, scheduledAttempts, scheduledCorrect, worstStarvationDays };
}

/** A learner who answers quickly once a card is known. */
const fastLearner: Learner = {
	responseMs: (rng) => 800 + Math.floor(rng() * 600)
};

/** A learner who is always right but always slow. */
const slowLearner: Learner = {
	responseMs: (rng, type) => (type === 'chain' ? 14_000 : 5000) + Math.floor(rng() * 1000),
	recall: () => true
};

describe('630-day back-test', () => {
	const run = simulate(fastLearner, 12345);

	it('delivers roughly the retention it requests', () => {
		const achieved = run.scheduledCorrect / run.scheduledAttempts;
		expect(run.scheduledAttempts).toBeGreaterThan(1000);
		expect(achieved).toBeGreaterThan(REQUEST_RETENTION - 0.03);
		expect(achieved).toBeLessThan(REQUEST_RETENTION + 0.03);
	});

	it('settles to a daily load that does not blow up', () => {
		const tail = run.dailyLoad.slice(-90);
		const sorted = [...tail].sort((a, b) => a - b);
		const medianLoad = sorted[Math.floor(sorted.length / 2)];
		expect(medianLoad).toBeGreaterThan(0);
		// No day in the settled period may be a runaway spike.
		expect(Math.max(...tail)).toBeLessThanOrEqual(Math.max(10, medianLoad * 3));
		// And the load must not still be climbing at the end of the year.
		const firstHalf = average(run.dailyLoad.slice(DAYS - 185, DAYS - 95));
		const secondHalf = average(run.dailyLoad.slice(DAYS - 90, DAYS));
		expect(secondHalf).toBeLessThanOrEqual(firstHalf * 1.5);
	});

	it('introduces the whole catalogue within the horizon', () => {
		expect(run.cards.every((c) => c.introduced)).toBe(true);
	});

	it('never starves a card that is not yet automatic for more than 90 days', () => {
		// Without capUntilAutomatic this reaches ~150 days: FSRS is happy to park
		// a correct-but-slow card for months, which is exactly the card that most
		// needs coming back.
		expect(run.worstStarvationDays).toBeLessThanOrEqual(90);
	});

	it('keeps non-automatic cards inside the interval ceiling', () => {
		// Slack for days when the session cap crowds a due card out.
		expect(run.worstStarvationDays).toBeLessThanOrEqual(MAX_DAYS_BEFORE_AUTOMATIC + 14);
	});

	it('gets a fast learner to automatic on most of the deck', () => {
		const automatic = run.cards.filter((c) => c.mastery === 'automatic').length;
		expect(automatic / run.cards.length).toBeGreaterThan(0.5);
	});

	it('is deterministic for a given seed', () => {
		const again = simulate(fastLearner, 12345);
		expect(again.dailyLoad).toEqual(run.dailyLoad);
		expect(again.scheduledCorrect).toBe(run.scheduledCorrect);
	});
});

describe('the time gate', () => {
	it('never lets an always-slow learner reach automatic', () => {
		// The point of the whole design: correct-but-laboured is not mastered.
		const run = simulate(slowLearner, 999);
		expect(run.cards.every((c) => c.mastery !== 'automatic')).toBe(true);
		expect(run.cards.filter((c) => c.mastery === 'familiar').length).toBeGreaterThan(200);
	});

	it('stops handing a struggling learner new material', () => {
		// A learner who never gets faster keeps every card on a 21-day leash, so
		// the due pile fills the session. The right response is to stop
		// introducing cards, not to let the session overflow.
		const run = simulate(slowLearner, 999);
		expect(Math.max(...run.dailyLoad)).toBeLessThanOrEqual(SESSION_CAP);
		const introduced = run.cards.filter((c) => c.introduced).length;
		expect(introduced).toBeLessThan(run.cards.length);
	});

	it('keeps a fast learner comfortably under the session cap', () => {
		const run = simulate(fastLearner, 12345);
		expect(average(run.dailyLoad.slice(-90))).toBeLessThan(SESSION_CAP);
	});
});

function average(xs: number[]): number {
	return xs.reduce((a, b) => a + b, 0) / (xs.length || 1);
}
