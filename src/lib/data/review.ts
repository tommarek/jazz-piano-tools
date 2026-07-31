import { db } from '$lib/db';
import { parseCardId, type CardType } from '$lib/music/cards';
import {
	MEDIAN_WINDOW,
	deriveGrade,
	deriveMastery,
	median,
	rollingMedian,
	type Mastery
} from '$lib/scheduler/grading';
import {
	applyReview,
	capUntilAutomatic,
	newSchedulerState,
	type SchedulerState
} from '$lib/scheduler/fsrs';
import { getSettings } from './settings';
import { addDays, dateKey, startOfDay, type SessionMode } from './queue';
import type { Grade } from 'ts-fsrs';

export interface ReviewInput {
	cardId: string;
	correct: boolean;
	responseMs: number;
	answerGiven?: unknown;
	sessionId?: string;
	mode?: SessionMode;
	ts?: number;
}

export interface ReviewResult {
	cardId: string;
	grade: Grade;
	correct: boolean;
	responseMs: number;
	/** Rolling median before this attempt — what the response time is judged against. */
	previousMedianMs: number | null;
	medianMs: number | null;
	mastery: Mastery;
	consecutiveCorrect: number;
	dueAt: number;
}

interface StateRow {
	due: number;
	stability: number;
	difficulty: number;
	elapsed_days: number;
	scheduled_days: number;
	learning_steps: number;
	reps: number;
	lapses: number;
	state: number;
	last_review: number | null;
	consecutive_correct: number;
	median_response_ms: number | null;
	mastery: Mastery;
}

/**
 * All session writes are serialised through one chain: conn.tx is not
 * reentrant, and a speed round's auto-advance can start the next card's write
 * — or the session-end write — while the previous persist() is still flushing.
 */
let writeChain: Promise<unknown> = Promise.resolve();

function serialise<T>(fn: () => Promise<T>): Promise<T> {
	const run = writeChain.then(fn);
	writeChain = run.catch(() => {});
	return run;
}

export function recordReview(input: ReviewInput): Promise<ReviewResult> {
	return serialise(() => recordReviewNow(input));
}

async function recordReviewNow(input: ReviewInput): Promise<ReviewResult> {
	const conn = await db();
	const ts = input.ts ?? Date.now();
	const now = new Date(ts);
	const mode: SessionMode = input.mode ?? 'srs';
	const settings = await getSettings();

	const spec = parseCardId(input.cardId);
	if (!spec) throw new Error(`Unknown card: ${input.cardId}`);
	const cardType: CardType = spec.type;

	// Oldest-first, so rollingMedian's tail slice keeps the newest attempts.
	// Speed-round times are excluded: a sprint is played faster than deliberate
	// practice, and letting it into the median would tighten the bar that later
	// srs attempts are graded Hard/Good/Easy against.
	const priorTimes = (
		await conn.all<{ response_ms: number }>(
			`SELECT response_ms FROM reviews
			 WHERE card_id = ? AND correct = 1 AND mode != 'speed'
			 ORDER BY ts DESC, id DESC LIMIT ?`,
			[input.cardId, MEDIAN_WINDOW]
		)
	)
		.map((r) => r.response_ms)
		.reverse();
	const previousMedianMs = rollingMedian(priorTimes);

	const grade = deriveGrade({
		correct: input.correct,
		responseMs: input.responseMs,
		medianMs: previousMedianMs,
		cardType
	});

	const existing = await conn.get<StateRow>('SELECT * FROM card_state WHERE card_id = ?', [
		input.cardId
	]);

	const prevState: SchedulerState = existing
		? {
				due: existing.due,
				stability: existing.stability,
				difficulty: existing.difficulty,
				elapsedDays: existing.elapsed_days,
				scheduledDays: existing.scheduled_days,
				learningSteps: existing.learning_steps,
				reps: existing.reps,
				lapses: existing.lapses,
				state: existing.state,
				lastReview: existing.last_review
			}
		: newSchedulerState(now);

	// A speed round is pure throughput practice on cards that are already
	// automatic — "no scheduling involved" means card_state is not touched at
	// all. Moving due dates would wreck the schedule, and resetting the streak
	// or mastery on one mis-tap in a 60-second blitz would demote a card the
	// scheduler thinks is solid while its far-future due date keeps it from
	// ever being re-drilled. The attempt is still logged to `reviews`.
	if (mode === 'speed') {
		await conn.tx(async () => {
			await insertReview(conn, input, ts, grade, mode);
		});
		await rollUpDay(ts);
		await conn.persist();
		return {
			cardId: input.cardId,
			grade,
			correct: input.correct,
			responseMs: input.responseMs,
			previousMedianMs,
			medianMs: existing?.median_response_ms ?? previousMedianMs,
			mastery: existing?.mastery ?? 'new',
			consecutiveCorrect: existing?.consecutive_correct ?? 0,
			dueAt: prevState.due
		};
	}

	const scheduled = applyReview(prevState, grade, now, settings.targetRetention);

	const consecutiveCorrect = input.correct ? (existing?.consecutive_correct ?? 0) + 1 : 0;
	const nextTimes = input.correct ? [...priorTimes, input.responseMs] : priorTimes;
	const medianMs = rollingMedian(nextTimes);
	const mastery = deriveMastery({ consecutiveCorrect, medianMs, cardType });
	const nextState = capUntilAutomatic(scheduled, mastery === 'automatic', now);

	await conn.tx(async () => {
		await conn.run(
			`INSERT INTO card_state
			 (card_id, due, stability, difficulty, elapsed_days, scheduled_days, learning_steps,
			  reps, lapses, state, last_review, median_response_ms, consecutive_correct, mastery)
			 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
			 ON CONFLICT(card_id) DO UPDATE SET
			   due = excluded.due, stability = excluded.stability, difficulty = excluded.difficulty,
			   elapsed_days = excluded.elapsed_days, scheduled_days = excluded.scheduled_days,
			   learning_steps = excluded.learning_steps, reps = excluded.reps,
			   lapses = excluded.lapses, state = excluded.state, last_review = excluded.last_review,
			   median_response_ms = excluded.median_response_ms,
			   consecutive_correct = excluded.consecutive_correct, mastery = excluded.mastery`,
			[
				input.cardId,
				nextState.due,
				nextState.stability,
				nextState.difficulty,
				nextState.elapsedDays,
				nextState.scheduledDays,
				nextState.learningSteps,
				nextState.reps,
				nextState.lapses,
				nextState.state,
				ts,
				medianMs,
				consecutiveCorrect,
				mastery
			]
		);
		await insertReview(conn, input, ts, grade, mode);
	});

	await rollUpDay(ts);
	await conn.persist();

	return {
		cardId: input.cardId,
		grade,
		correct: input.correct,
		responseMs: input.responseMs,
		previousMedianMs,
		medianMs,
		mastery,
		consecutiveCorrect,
		dueAt: nextState.due
	};
}

async function insertReview(
	conn: Awaited<ReturnType<typeof db>>,
	input: ReviewInput,
	ts: number,
	grade: Grade,
	mode: SessionMode
): Promise<void> {
	await conn.run(
		`INSERT INTO reviews (card_id, ts, grade, response_ms, correct, answer_given, session_id, mode)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		[
			input.cardId,
			ts,
			grade,
			input.responseMs,
			input.correct ? 1 : 0,
			input.answerGiven === undefined ? null : JSON.stringify(input.answerGiven),
			input.sessionId ?? null,
			mode
		]
	);
}

/**
 * Recompute a day's rollup from the review log. Cheap (one day is a few hundred
 * rows) and keeps `daily_stats` a derived cache rather than a second source of
 * truth that can drift.
 */
export async function rollUpDay(ts: number): Promise<void> {
	const conn = await db();
	const dayStart = startOfDay(ts);
	const dayEnd = addDays(dayStart, 1);
	// Sprint rows are excluded here like everywhere else medians or accuracy
	// are computed — one 60-second blitz would otherwise rewrite the day's
	// chart point at sprint pace. A day already stored with sprint rows heals
	// itself: the next review of that day recomputes it from the log.
	const rows = await conn.all<{ response_ms: number; correct: number }>(
		"SELECT response_ms, correct FROM reviews WHERE ts >= ? AND ts < ? AND mode != 'speed'",
		[dayStart, dayEnd]
	);

	const correct = rows.filter((r) => r.correct === 1).length;
	// Correct attempts only, like every other fluency median in the app — a
	// fast "No idea" tap must not read as fluency.
	const med = median(rows.filter((r) => r.correct === 1).map((r) => r.response_ms));
	const minutes = rows.reduce((acc, r) => acc + r.response_ms, 0) / 60_000;

	// Through conn.tx even though it is one statement: a bare run() is not
	// serialised against an open transaction elsewhere, so it would be committed
	// or rolled back with whatever BEGIN happened to be in flight (db/index.ts).
	await conn.tx(async () => {
		await conn.run(
			`INSERT INTO daily_stats (date, reviews, correct, median_response_ms, minutes)
			 VALUES (?, ?, ?, ?, ?)
			 ON CONFLICT(date) DO UPDATE SET
			   reviews = excluded.reviews, correct = excluded.correct,
			   median_response_ms = excluded.median_response_ms, minutes = excluded.minutes`,
			[dateKey(dayStart), rows.length, correct, med, Math.round(minutes * 100) / 100]
		);
	});
}

export async function startSession(id: string, mode: SessionMode): Promise<void> {
	const conn = await db();
	await conn.tx(async () => {
		await conn.run(
			'INSERT OR REPLACE INTO sessions (id, started_at, ended_at, card_count, mode) VALUES (?, ?, NULL, 0, ?)',
			[id, Date.now(), mode]
		);
	});
}

export function endSession(id: string, cardCount: number): Promise<void> {
	return serialise(async () => {
		const conn = await db();
		await conn.tx(async () => {
			await conn.run('UPDATE sessions SET ended_at = ?, card_count = ? WHERE id = ?', [
				Date.now(),
				Math.max(0, Math.round(cardCount)),
				id
			]);
		});
		await conn.persist();
	});
}
