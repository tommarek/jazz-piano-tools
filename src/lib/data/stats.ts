import { db } from '$lib/db';
import { median, type Mastery } from '$lib/scheduler/grading';
import { addDays, dateKey, eligibleIds, startOfDay } from './queue';
import { getSettings } from './settings';
import { GATE_PER_CHORD_MS, keyScores, recentChainTimes } from './stages';
import { keyLabel } from '$lib/music/voicings';

export interface DayPoint {
	date: string;
	/** Sprint-free, like everything daily_stats stores — the quality population. */
	reviews: number;
	correct: number;
	accuracy: number;
	medianResponseMs: number | null;
	minutes: number;
	/**
	 * Every attempt of the day, sprints included. "Did you practise" is a
	 * different question from "how well did you do", and answering it out of the
	 * sprint-free column told a speed-round-only day it had not happened.
	 */
	attempts: number;
}

export interface KeyCell {
	pitchClass: number;
	label: string;
	total: number;
	automatic: number;
	familiar: number;
	newOrUnseen: number;
	/** 0..1 — share of the key's cards that are automatic. */
	score: number;
	medianResponseMs: number | null;
}

export interface Stats {
	headline: {
		chainMedianMs: number | null;
		chainSampleSize: number;
		chainPerChordMs: number | null;
		targetPerChordMs: number;
	};
	today: { reviews: number; correct: number; minutes: number };
	streakDays: number;
	byDay: DayPoint[];
	heatmap: KeyCell[];
	retention: { reviewed: number; correct: number; rate: number | null };
	states: { unseen: number; new: number; familiar: number; automatic: number; total: number };
	byQuality: { quality: string; medianResponseMs: number | null; accuracy: number | null }[];
}

/**
 * Day bucketing happens in JavaScript, not in SQL. SQLite's `localtime` depends
 * on the process timezone, which is not necessarily the one the UI is using —
 * and getting that wrong silently shifts every chart by a day.
 */
export async function getStats(now = Date.now(), days = 60): Promise<Stats> {
	const conn = await db();
	const sinceKey = dateKey(addDays(now, -(days - 1)));

	const dayRows = await conn.all<{
		date: string;
		reviews: number;
		correct: number;
		median_response_ms: number | null;
		minutes: number;
	}>('SELECT * FROM daily_stats WHERE date >= ? ORDER BY date', [sinceKey]);

	const sprints = await sprintDays(addDays(now, -(days - 1)));
	const stored = new Map(dayRows.map((r) => [r.date, r]));
	// The union, not just the stored rows: a day of nothing but speed rounds is
	// a real day of practice that daily_stats deliberately records as zero.
	const dates = [...new Set([...stored.keys(), ...sprints.keys()])].sort();

	const byDay: DayPoint[] = dates.map((date) => {
		const r = stored.get(date);
		const reviews = r?.reviews ?? 0;
		return {
			date,
			reviews,
			correct: r?.correct ?? 0,
			accuracy: reviews > 0 ? (r?.correct ?? 0) / reviews : 0,
			medianResponseMs: r?.median_response_ms ?? null,
			minutes: r?.minutes ?? 0,
			attempts: reviews + (sprints.get(date) ?? 0)
		};
	});

	const todayKey = dateKey(now);
	const today = byDay.find((d) => d.date === todayKey) ?? {
		date: todayKey,
		reviews: 0,
		correct: 0,
		accuracy: 0,
		medianResponseMs: null,
		minutes: 0,
		attempts: 0
	};

	// Headline: the same measure the gate uses — correct major chains only, so
	// introducing minor chains does not appear to undo months of progress on
	// the number the whole app is steering by.
	const chainTimes = await recentChainTimes();
	const chainMedianMs = median(chainTimes);

	const stateRows = await conn.all<{
		id: string;
		type: string;
		quality: string | null;
		pc: number;
		mastery: Mastery | null;
		med: number | null;
	}>(
		`SELECT c.id, c.type, c.quality, c.root_pitch_class AS pc, s.mastery, s.median_response_ms AS med
		 FROM cards c LEFT JOIN card_state s ON s.card_id = c.id`
	);

	// The heatmap is not its own measure: it renders keyScores(), the same
	// function the stage-4 keys criterion is judged on, so the caption's claim
	// that they are one measure is enforced rather than merely believed. Only
	// the per-key median is added here — the criterion has no use for it.
	const medianOf = new Map(stateRows.map((r) => [r.id, r.med]));
	const heatmap: KeyCell[] = (await keyScores()).map((k) => ({
		pitchClass: k.pitchClass,
		label: keyLabel(k.pitchClass),
		total: k.total,
		automatic: k.automatic,
		familiar: k.familiar,
		newOrUnseen: k.total - k.automatic - k.familiar,
		score: k.score,
		medianResponseMs: median(
			k.ids.map((id) => medianOf.get(id) ?? null).filter((m): m is number => m != null)
		)
	}));

	const eligible = await eligibleIds(await getSettings());

	// "Cards by state" counts the deck the user can actually study — showing
	// locked or deselected cards as "not started" would misstate the job left.
	const eligibleRows = stateRows.filter((r) => eligible.has(r.id));
	const counts = { unseen: 0, new: 0, familiar: 0, automatic: 0 };
	for (const r of eligibleRows) counts[r.mastery ?? 'unseen'] += 1;

	const reviews = await conn.all<{
		card_id: string;
		ts: number;
		correct: number;
		mode: string;
	}>('SELECT card_id, ts, correct, mode FROM reviews ORDER BY ts');

	return {
		headline: {
			chainMedianMs,
			chainSampleSize: chainTimes.length,
			chainPerChordMs: chainMedianMs === null ? null : Math.round(chainMedianMs / 3),
			targetPerChordMs: GATE_PER_CHORD_MS
		},
		// "Done today" is an activity count, so it includes sprints; correct and
		// minutes stay on the sprint-free population they are judged against.
		today: { reviews: today.attempts, correct: today.correct, minutes: today.minutes },
		streakDays: await currentStreak(now),
		byDay,
		heatmap,
		retention: retentionOf(reviews),
		states: { ...counts, total: eligibleRows.length },
		byQuality: qualityBreakdown(stateRows, await reviewTimes())
	};
}

/**
 * Retention: the first attempt each day at a card that was already known before
 * that day. That is the population the scheduler actually predicts.
 */
function retentionOf(
	reviews: { card_id: string; ts: number; correct: number; mode: string }[]
): Stats['retention'] {
	const firstSeenDay = new Map<string, string>();
	const firstOfDay = new Map<string, { correct: number; day: string; card: string }>();

	for (const r of reviews) {
		const day = dateKey(r.ts);
		if (!firstSeenDay.has(r.card_id)) firstSeenDay.set(r.card_id, day);
		// Speed rounds don't reschedule cards, so they say nothing about retention.
		// Visualise sessions schedule exactly like srs and count the same.
		if (r.mode === 'speed') continue;
		const key = `${r.card_id}|${day}`;
		if (!firstOfDay.has(key)) {
			firstOfDay.set(key, { correct: r.correct, day, card: r.card_id });
		}
	}

	let reviewed = 0;
	let correct = 0;
	for (const entry of firstOfDay.values()) {
		const known = firstSeenDay.get(entry.card);
		// Only counts if the card was first seen on an earlier day.
		if (!known || known >= entry.day) continue;
		reviewed += 1;
		correct += entry.correct;
	}
	return { reviewed, correct, rate: reviewed ? correct / reviewed : null };
}

async function reviewTimes(): Promise<{ card_id: string; response_ms: number; correct: number }[]> {
	const conn = await db();
	// Sprint rows are excluded everywhere medians or accuracy are computed.
	return conn.all("SELECT card_id, response_ms, correct FROM reviews WHERE mode != 'speed'");
}

function qualityBreakdown(
	cards: { id: string; type: string; quality: string | null }[],
	times: { card_id: string; response_ms: number; correct: number }[]
): Stats['byQuality'] {
	// The catalogue's own quality column, not a hand-kept list of the id shapes
	// that happen to carry one: that list had already gone stale twice, silently
	// leaving whole decks out of a screen that claims to cover the deck.
	const qualityOf = new Map<string, string>();
	for (const c of cards) {
		// gtn's column holds a guide-tone interval class ('maj7' meaning "a 3rd
		// and 7th a fifth apart"), which is not the quality it drills — bucketing
		// it here would file m7 and m7♭5 reps under maj7.
		if (c.quality === null || c.type === 'gtn') continue;
		qualityOf.set(c.id, c.quality);
	}

	const buckets = new Map<string, { ms: number[]; correct: number; total: number }>();
	for (const t of times) {
		const q = qualityOf.get(t.card_id);
		if (!q) continue;
		const b = buckets.get(q) ?? { ms: [], correct: 0, total: 0 };
		if (t.correct === 1) {
			b.correct += 1;
			b.ms.push(t.response_ms);
		}
		b.total += 1;
		buckets.set(q, b);
	}

	return [...buckets.entries()].map(([quality, b]) => ({
		quality,
		accuracy: b.total ? b.correct / b.total : null,
		medianResponseMs: median(b.ms)
	}));
}

/**
 * Sprint attempts per local day, keyed like daily_stats. Bucketed in JS for the
 * reason getStats explains — SQLite's `localtime` is not necessarily the UI's.
 */
async function sprintDays(since?: number): Promise<Map<string, number>> {
	const conn = await db();
	const rows = await conn.all<{ ts: number }>(
		`SELECT ts FROM reviews WHERE mode = 'speed'${since === undefined ? '' : ' AND ts >= ?'}`,
		since === undefined ? [] : [since]
	);
	const out = new Map<string, number>();
	for (const r of rows) {
		const key = dateKey(r.ts);
		out.set(key, (out.get(key) ?? 0) + 1);
	}
	return out;
}

/** Consecutive days up to today with at least one attempt of any kind. */
export async function currentStreak(now = Date.now()): Promise<number> {
	const conn = await db();
	const rows = await conn.all<{ date: string }>(
		'SELECT date FROM daily_stats WHERE reviews > 0'
	);
	const seen = new Set(rows.map((r) => r.date));
	// daily_stats holds the sprint-free count, so a speed-only day reads as zero
	// there. Breaking somebody's streak on a day they practised is the one thing
	// the streak must never do.
	for (const key of (await sprintDays()).keys()) seen.add(key);
	let streak = 0;
	let cursor = startOfDay(now);
	// Today not yet practised does not break a streak that ran through yesterday.
	if (!seen.has(dateKey(cursor))) cursor = addDays(cursor, -1);
	while (seen.has(dateKey(cursor))) {
		streak += 1;
		cursor = addDays(cursor, -1);
	}
	return streak;
}

