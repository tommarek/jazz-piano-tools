import { db } from '$lib/db';
import { median, type Mastery } from '$lib/scheduler/grading';
import { ALL_DECK } from './decks';
import { addDays, dateKey, eligibleIds, soleQuality, startOfDay } from './queue';
import { getSettings } from './settings';
import { GATE_PER_CHORD_MS, keyScores, recentChainTimes } from './stages';
import { keyLabel } from '$lib/music/voicings';
import {
	CARD_TYPE_LABEL,
	EAR_TYPES,
	sectionOfId,
	type CardType,
	type Section
} from '$lib/music/cards';

/** A card id's type is its first segment — the one join available offline. */
function typeOfId(id: string): string {
	return id.split(':')[0];
}

export interface DayPoint {
	date: string;
	/**
	 * Sprint-free AND section-scoped: the population the accuracy and median on
	 * this point are computed over. Reading a chord and hearing one are
	 * different skills at different speeds, and averaging them produced a
	 * number describing neither.
	 */
	reviews: number;
	correct: number;
	accuracy: number;
	medianResponseMs: number | null;
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
	/**
	 * "Done today" — every attempt of the day, both sections and sprints
	 * included, because it answers "did you practise" rather than "how well".
	 * There is deliberately no correct or minutes beside it: those are judged on
	 * the sprint-free theory population, and three numbers over three different
	 * populations under one heading is a screen contradicting itself.
	 */
	today: { reviews: number };
	streakDays: number;
	byDay: DayPoint[];
	heatmap: KeyCell[];
	retention: { reviewed: number; correct: number; rate: number | null };
	states: { unseen: number; new: number; familiar: number; automatic: number; total: number };
	byQuality: { quality: string; medianResponseMs: number | null; accuracy: number | null }[];
}

export interface EarTypeStats {
	type: CardType;
	label: string;
	attempts: number;
	accuracy: number | null;
	/** On correct answers only, like every other median here. */
	medianResponseMs: number | null;
}

export interface EarStats {
	byType: EarTypeStats[];
	byDay: DayPoint[];
	attempts: number;
	accuracy: number | null;
}

/**
 * Day bucketing happens in JavaScript, not in SQL. SQLite's `localtime` depends
 * on the process timezone, which is not necessarily the one the UI is using —
 * and getting that wrong silently shifts every chart by a day.
 */
export async function getStats(now = Date.now(), days = 60): Promise<Stats> {
	const conn = await db();
	const sinceKey = dateKey(addDays(now, -(days - 1)));

	const dayRows = await conn.all<{ date: string; reviews: number }>(
		'SELECT date, reviews FROM daily_stats WHERE date >= ? ORDER BY date',
		[sinceKey]
	);

	// daily_stats rolls up BOTH sections together, so every quality figure is
	// recomputed here from the rows themselves. The rollup is still read for the
	// practice count: a day whose review rows were purged with a cut card type is
	// a day that happened, and the streak — which reads daily_stats directly —
	// already counts it. Dropping it off the axis, or leaving it there at zero,
	// makes the same screen say both.
	const allReviews = await conn.all<{
		card_id: string;
		ts: number;
		correct: number;
		mode: string;
		response_ms: number;
	}>('SELECT card_id, ts, correct, mode, response_ms FROM reviews ORDER BY ts');
	const since = startOfDay(addDays(now, -(days - 1)));
	const windowed = allReviews.filter((r) => r.ts >= since);

	const byDay = daySeries(windowed, 'theory', dayRows);

	const todayKey = dateKey(now);
	const today = byDay.find((d) => d.date === todayKey);

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
	// function the stage-3 keys criterion is judged on, so the caption's claim
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

	// Named rather than left to the default: this is the theory section's screen,
	// and folding 204 ear cards into "not started" here — they have their own
	// screen and their own counts — overstates the theory job.
	const eligible = await eligibleIds(await getSettings(), ALL_DECK);

	// "Cards by state" counts the deck the user can actually study — showing
	// locked or deselected cards as "not started" would misstate the job left.
	const eligibleRows = stateRows.filter((r) => eligible.has(r.id));
	const counts = { unseen: 0, new: 0, familiar: 0, automatic: 0 };
	// Not just NULL, for the reason browse.ts gives: nothing constrains the column
	// to the three states and an imported backup writes whatever its file said. An
	// unknown one would make its own bucket NaN and leave the four bars summing to
	// less than the total they are drawn against — and `in` would let 'toString'
	// through into a bucket of its own, which is the same miscount.
	for (const r of eligibleRows)
		counts[r.mastery && Object.hasOwn(counts, r.mastery) ? r.mastery : 'unseen'] += 1;

	// Retention is a theory figure on a theory screen. An ear card recalled is a
	// different claim about a different faculty, and the ear section reports it.
	const reviews = allReviews.filter((r) => sectionOfId(r.card_id) === 'theory');

	return {
		headline: {
			chainMedianMs,
			chainSampleSize: chainTimes.length,
			chainPerChordMs: chainMedianMs === null ? null : Math.round(chainMedianMs / 3),
			targetPerChordMs: GATE_PER_CHORD_MS
		},
		// An activity count, so it spans both sections and includes sprints.
		today: { reviews: today?.attempts ?? 0 },
		streakDays: await currentStreak(now),
		byDay,
		heatmap,
		retention: retentionOf(reviews),
		states: { ...counts, total: eligibleRows.length },
		byQuality: qualityBreakdown(
			stateRows,
			(await reviewTimes()).filter((t) => sectionOfId(t.card_id) === 'theory')
		)
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


/**
 * Per-day quality figures for one section, plus a practice count for the day
 * that deliberately spans everything.
 *
 * `attempts` counts every review of the day — both sections, sprints included —
 * because it answers "did you practise", and a day of nothing but ear training
 * or nothing but a speed round is a day you practised. Everything else on the
 * point is scoped to the section and excludes sprints, which are systematically
 * faster and would flatter both the median and the accuracy.
 */
function daySeries(
	reviews: { card_id: string; ts: number; correct: number; mode: string; response_ms: number }[],
	section: Section,
	rollup: Iterable<{ date: string; reviews: number }> = []
): DayPoint[] {
	const days = new Map<
		string,
		{ reviews: number; correct: number; ms: number[]; attempts: number }
	>();
	const bucket = (date: string) => {
		let d = days.get(date);
		if (!d) days.set(date, (d = { reviews: 0, correct: 0, ms: [], attempts: 0 }));
		return d;
	};
	for (const r of reviews) {
		const date = dateKey(r.ts);
		const d = bucket(date);
		d.attempts += 1;
		if (r.mode === 'speed' || sectionOfId(r.card_id) !== section) continue;
		d.reviews += 1;
		if (r.correct === 1) {
			d.correct += 1;
			d.ms.push(r.response_ms);
		}
	}
	// Days the rollup knows about but this window's rows do not still belong on
	// the axis, and with their count: a day whose review rows went with a purged
	// card type is a day, and the streak still counts it. The rollup is the floor
	// rather than the value because it excludes sprints, which `attempts` counts.
	for (const { date, reviews } of rollup) {
		const d = bucket(date);
		d.attempts = Math.max(d.attempts, reviews);
	}

	return [...days.entries()]
		.sort(([a], [b]) => a.localeCompare(b))
		.map(([date, d]) => ({
			date,
			reviews: d.reviews,
			correct: d.correct,
			accuracy: d.reviews > 0 ? d.correct / d.reviews : 0,
			medianResponseMs: median(d.ms),
			attempts: d.attempts
		}));
}

/**
 * The ear section's own figures. Accuracy leads rather than speed: perception
 * is slow long after it is reliable, and the ear path gates on being right.
 */
export async function earStats(now = Date.now(), days = 60): Promise<EarStats> {
	const conn = await db();
	const since = startOfDay(addDays(now, -(days - 1)));
	const reviews = await conn.all<{
		card_id: string;
		ts: number;
		correct: number;
		mode: string;
		response_ms: number;
	}>('SELECT card_id, ts, correct, mode, response_ms FROM reviews ORDER BY ts');
	const ear = reviews.filter(
		(r) => sectionOfId(r.card_id) === 'ear' && r.mode !== 'speed'
	);

	// Attempts, not card states: the ear path gates on being right, and the
	// mastery breakdown is a theory-screen figure. Counting states here as well
	// gave two totals that disagreed by design — one eligibility-filtered, one
	// not — and neither was ever rendered.
	const byType: EarTypeStats[] = EAR_TYPES.map((type) => {
		const rows = ear.filter((r) => typeOfId(r.card_id) === type);
		return {
			type,
			label: CARD_TYPE_LABEL[type],
			attempts: rows.length,
			accuracy: rows.length ? rows.filter((r) => r.correct === 1).length / rows.length : null,
			medianResponseMs: median(rows.filter((r) => r.correct === 1).map((r) => r.response_ms))
		};
	});

	return {
		byType,
		byDay: daySeries(
			reviews.filter((r) => r.ts >= since),
			'ear'
		),
		attempts: ear.length,
		accuracy: ear.length ? ear.filter((r) => r.correct === 1).length / ear.length : null
	};
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
	// soleQuality, not the catalogue's quality column: a hand-kept list of the id
	// shapes that carry one had already gone stale twice, and the column alone is
	// no better — it is NULL for dia and mode, whose chord the numeral in the id
	// fixes instead, so two drills went missing from a screen that claims to
	// cover the deck. What is left out is left out because no ONE
	// quality describes the attempt: gtn is answered by any quality its pair
	// fits, a progression by all of its chords at once, and the interval drills
	// name no chord at all.
	const qualityOf = new Map<string, string>();
	for (const c of cards) {
		const quality = soleQuality(c);
		if (quality === null) continue;
		qualityOf.set(c.id, quality);
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
async function sprintDays(): Promise<Map<string, number>> {
	const conn = await db();
	const rows = await conn.all<{ ts: number }>(`SELECT ts FROM reviews WHERE mode = 'speed'`);
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

