/**
 * Building a session queue: which cards, in which order.
 *
 * Order matters as much as selection here. Blocking ten Dm7 cards together
 * feels productive and retains badly; interleaving keys and card types feels
 * worse in the session and is what actually transfers.
 */

import { db } from '$lib/db';
import {
	CARD_TYPES,
	EAR_TYPES,
	GT_CLASS_ACCEPTS,
	renderCard,
	parseCardId,
	type CardType,
	type CardView,
	type GtClass
} from '$lib/music/cards';
import { effectiveCardTypes, getSettings, type Settings } from './settings';
import {
	CHAIN_QUALITIES,
	FOURTHS_ORDER,
	GUIDE_INTERVAL_QUALITIES,
	type GuideInterval,
	type Quality
} from '$lib/music/voicings';
import { parseNote, pitchClass } from '$lib/music/theory';

export type SessionMode = 'srs' | 'speed' | 'visualise';

export interface QueueItem {
	card: CardView;
	/** True when this card has never been reviewed. */
	isNew: boolean;
	dueAt: number | null;
}

export function startOfDay(now = Date.now()): number {
	const d = new Date(now);
	d.setHours(0, 0, 0, 0);
	return d.getTime();
}

/**
 * Local-midnight `days` calendar days away from `ts`. Calendar arithmetic, not
 * ts ± 86 400 000: DST days are 23 or 25 hours long, and a fixed-24h step
 * lands mid-day, double-counts an hour, or skips a date outright.
 */
export function addDays(ts: number, days: number): number {
	const d = new Date(ts);
	d.setHours(0, 0, 0, 0);
	d.setDate(d.getDate() + days);
	return d.getTime();
}

export function dateKey(ts: number): string {
	const d = new Date(ts);
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** Cards seen for the first time today — the budget that newCardsPerDay caps. */
export async function newCardsIntroducedToday(now = Date.now()): Promise<number> {
	const conn = await db();
	const dayStart = startOfDay(now);
	const row = await conn.get<{ n: number }>(
		`SELECT COUNT(*) AS n FROM (
		   SELECT card_id FROM reviews WHERE ts >= ?
		   EXCEPT
		   SELECT card_id FROM reviews WHERE ts < ?
		 )`,
		[dayStart, dayStart]
	);
	return row?.n ?? 0;
}

interface CardRow {
	id: string;
	type: string;
	quality: string | null;
}

/**
 * Whether a card's quality is one of the ones being drilled.
 *
 * Several types name no quality of their own but are still answered with one,
 * and for those the rule is "any accepted reading is being drilled": gtn's
 * `quality` column holds a guide-tone interval class, and an n2s card holds a
 * guide interval in its id. Both accept every quality consistent with what is
 * shown, so matching literally — or waving them through — is wrong in the same
 * way: it drops the class named 'maj7' for someone drilling only m7 even though
 * that class IS the m7 pair, and it serves a maj7-only learner an n2s card whose
 * every answer is minor.
 *
 * The progression types store no quality either, but they are *made of* chords,
 * and unlike the two above those are a conjunction rather than a choice: the
 * card is answered by producing all of them. So the rule is "every chord in it
 * is being drilled" — waving them through served a minor chain (iiø, V7,
 * i m maj7) to someone who had switched m7♭5 and m(maj7) off and could not be
 * dealt a single m7♭5 shell. The mode is read off the id, the discriminator
 * stages.ts already uses; rlc is major-only and has no mode segment.
 */
const PROGRESSION_TYPES = ['chain', 'vl', 'gtc', 'rlc'];

/**
 * The chords a progression card actually contains. Only `chain` spans the whole
 * ii–V–I; vl, gtc and rlc are *transition* cards covering one step of it, so
 * demanding the third chord's quality withheld cards it never shows — with maj7
 * off, `vl:C:737:ii-V` is Dm7 → G7 and has no maj7 anywhere in it.
 */
function progressionQualities(type: string, id: string): Quality[] {
	const [ii, V, I] = CHAIN_QUALITIES[id.endsWith(':minor') ? 'minor' : 'major'];
	if (type === 'chain') return [ii, V, I];
	// The transition is a whole id segment, so it cannot collide with a root slug.
	return id.split(':').includes('ii-V') ? [ii, V] : [V, I];
}

function qualityActive(row: CardRow, settings: Settings): boolean {
	const anyActive = (qualities: Quality[]) =>
		qualities.some((q) => settings.activeQualities.includes(q));
	if (row.type === 'gtn') return anyActive(GT_CLASS_ACCEPTS[row.quality as GtClass] ?? []);
	// n2s ids are `n2s:<root>:<guide>`.
	if (row.type === 'n2s')
		return anyActive(GUIDE_INTERVAL_QUALITIES[row.id.split(':')[2] as GuideInterval] ?? []);
	if (PROGRESSION_TYPES.includes(row.type))
		return progressionQualities(row.type, row.id).every((q) =>
			settings.activeQualities.includes(q)
		);
	if (row.quality === null) return true;
	return settings.activeQualities.includes(row.quality as never);
}

/** Every card the deck may draw from: active types and active qualities. */
export async function eligibleIds(settings: Settings): Promise<Set<string>> {
	const conn = await db();
	const types = effectiveCardTypes(settings);
	const rows = await conn.all<CardRow>('SELECT id, type, quality FROM cards');

	return new Set(
		rows
			.filter((r) => types.includes(r.type as never))
			// The quality filter is about which chords you want to drill. It applies
			// to cards that name a chord quality; interval and mode cards have none.
			.filter((r) => qualityActive(r, settings))
			// An ear card's prompt IS the sound; with playback off there is no
			// question on the screen at all, so it must not be dealt.
			.filter((r) => settings.soundEnabled || !EAR_TYPES.includes(r.type as never))
			.map((r) => r.id)
	);
}

export interface BuildQueueOptions {
	mode?: SessionMode;
	now?: number;
	settings?: Settings;
	/** Overrides the settings cap; used by tests. */
	limit?: number;
}

export async function buildQueue(opts: BuildQueueOptions = {}): Promise<QueueItem[]> {
	const conn = await db();
	const now = opts.now ?? Date.now();
	const settings = opts.settings ?? (await getSettings());
	const mode = opts.mode ?? 'srs';
	// A speed round is time-boxed, not card-boxed: the sprint must not end
	// early because the srs session's card cap ran out of queue.
	const limit = opts.limit ?? (mode === 'speed' ? 200 : settings.sessionCardCap);
	const eligible = await eligibleIds(settings);

	if (mode === 'speed') {
		// Throughput on cards that are already automatic — no scheduling involved.
		const rows = await conn.all<{ id: string }>(
			`SELECT card_id AS id FROM card_state WHERE mastery = 'automatic'`
		);
		const items = rows
			.filter((r) => eligible.has(r.id))
			.map((r) => toItem(r.id, false, null))
			.filter((i): i is QueueItem => i !== null);
		return orderQueue(items, limit);
	}

	// Most overdue first, and cut to the cap here rather than leaving it to
	// orderQueue: interleaving shuffles, so a backlog larger than one session
	// would otherwise be sampled at random and the oldest debt could sit
	// unreviewed for weeks while newer due cards cycled past it.
	const due = (
		await conn.all<{ id: string; due: number }>(
			'SELECT card_id AS id, due FROM card_state WHERE due <= ? ORDER BY due',
			[now]
		)
	)
		.filter((r) => eligible.has(r.id))
		.slice(0, limit);

	// New cards only fill space the due pile has left. Without this the deck
	// keeps growing while you are already behind, which is how an SRS deck
	// quietly turns into a chore — the back-test hits the cap every day with a
	// learner who never speeds up.
	const room = Math.max(0, limit - due.length);
	const budget = Math.min(room, Math.max(0, settings.newCardsPerDay - (await newCardsIntroducedToday(now))));
	const unseen = (
		await conn.all<{ id: string; type: string }>(
			`SELECT c.id, c.type FROM cards c
			 LEFT JOIN card_state s ON s.card_id = c.id
			 WHERE s.card_id IS NULL
			 ORDER BY c.rowid`
		)
	).filter((r) => eligible.has(r.id));

	// Where each type's root rotation got to. Counted from what has been
	// introduced rather than kept in memory, so it survives across sessions.
	const seenByType = new Map(
		(
			await conn.all<{ type: string; n: number }>(
				`SELECT c.type AS type, COUNT(*) AS n
				 FROM card_state s JOIN cards c ON c.id = s.card_id
				 GROUP BY c.type`
			)
		).map((r) => [r.type, r.n] as const)
	);

	const fresh = spreadAcrossTypes(unseen, budget, seenByType);

	const items: QueueItem[] = [];
	for (const r of due) {
		const item = toItem(r.id, false, r.due);
		if (item) items.push(item);
	}
	for (const r of fresh) {
		const item = toItem(r.id, true, null);
		if (item) items.push(item);
	}

	return orderQueue(items, limit);
}

/** Position of a root slug in the fourths cycle; unknown slugs sort last. */
function fourthsRank(rootSlug: string): number {
	try {
		const rank = FOURTHS_ORDER.indexOf(pitchClass(parseNote(rootSlug.replace('s', '#'), 4)));
		return rank === -1 ? 99 : rank;
	} catch {
		return 99;
	}
}

/**
 * Take new cards round-robin across the active types, and inside each type
 * round-robin across roots. Straight catalogue order hands you a dozen
 * symbol→notes cards on the same root before anything else — and a type-only
 * round-robin still serves nothing but C for the first week, because every
 * type's catalogue starts at C. Each type also starts its root rotation at a
 * different offset, so even a one-card-per-type day spans several keys. The
 * selection stays deterministic, which SQLite's unordered scan was not.
 *
 * `seenByType` — how many cards of each type have already been introduced —
 * is what carries both rotations between sessions. Without it every session
 * restarts at the same bucket, so a type introducing two cards a day never
 * leaves its first two keys, and stage 2 (which wants an automatic shell in
 * all twelve) stays shut for months; and every session would walk the types
 * from the top, so with a budget smaller than the number of live types the
 * ones at the bottom of the list would never be introduced at all.
 */
export function spreadAcrossTypes<T extends { id: string; type: string }>(
	cards: T[],
	budget: number,
	seenByType: Map<string, number> = new Map()
): T[] {
	if (budget <= 0) return [];
	// The root/key is the second segment of every card id (e.g. "s2n:Db:m7:r3").
	const byType = new Map<string, Map<string, T[]>>();
	for (const card of cards) {
		const root = card.id.split(':')[1] ?? '';
		let roots = byType.get(card.type);
		if (!roots) byType.set(card.type, (roots = new Map()));
		const list = roots.get(root);
		if (list) list.push(card);
		else roots.set(root, [card]);
	}

	const out: T[] = [];
	const types = [...byType.entries()].map(([type, roots]) => ({
		type,
		// Roots enter in circle-of-fourths order, the order jazz practice moves
		// in — chromatic order would follow C with D♭, which shares nothing.
		buckets: [...roots.entries()]
			.sort((a, b) => fourthsRank(a[0]) - fourthsRank(b[0]))
			.map(([, cards]) => cards),
		// The type's fixed catalogue position staggers the types against each
		// other; the seen count resumes this type's own rotation where the last
		// session left it. The position must come from CARD_TYPES, not from this
		// map — the map only holds types with cards left, so its indices shift as
		// types drain and the stagger would wander.
		cursor: Math.max(0, CARD_TYPES.indexOf(type as CardType)) + (seenByType.get(type) ?? 0)
	}));
	// Least-served type first. The loop below stops the moment the budget is
	// full, and a warm deck's budget is a card or two — so walking the types in
	// catalogue order every session would mean the tail of the list (chains,
	// voice leading, the comping drills) is never reached at all. Catalogue
	// position only breaks ties, so the didactic order still decides who goes
	// first among types that are equally far behind.
	types.sort(
		(a, b) =>
			(seenByType.get(a.type) ?? 0) - (seenByType.get(b.type) ?? 0) ||
			CARD_TYPES.indexOf(a.type as CardType) - CARD_TYPES.indexOf(b.type as CardType)
	);
	let progress = true;
	while (out.length < budget && progress) {
		progress = false;
		for (const t of types) {
			if (out.length >= budget) break;
			for (let tried = 0; tried < t.buckets.length; tried++) {
				const bucket = t.buckets[t.cursor % t.buckets.length];
				t.cursor += 1;
				const next = bucket.shift();
				if (next) {
					out.push(next);
					progress = true;
					break;
				}
			}
		}
	}
	return out;
}

function toItem(id: string, isNew: boolean, dueAt: number | null): QueueItem | null {
	const spec = parseCardId(id);
	if (!spec) return null;
	return { card: renderCard(spec), isNew, dueAt };
}

/**
 * Shuffle, then greedily pull apart neighbours that share a root or a card
 * type. Pure interleaving beats blocking; this is the cheap approximation.
 */
export function orderQueue(items: QueueItem[], limit: number): QueueItem[] {
	const pool = shuffle(items);
	const out: QueueItem[] = [];
	while (pool.length > 0 && out.length < limit) {
		const prev = out[out.length - 1];
		let bestIndex = 0;
		let bestPenalty = Number.POSITIVE_INFINITY;
		for (let i = 0; i < pool.length; i++) {
			const penalty = prev ? clash(prev, pool[i]) : 0;
			if (penalty < bestPenalty) {
				bestPenalty = penalty;
				bestIndex = i;
				if (penalty === 0) break;
			}
		}
		out.push(pool.splice(bestIndex, 1)[0]);
	}
	return out;
}

function clash(a: QueueItem, b: QueueItem): number {
	let p = 0;
	if (a.card.rootPitchClass === b.card.rootPitchClass) p += 2;
	if (a.card.type === b.card.type) p += 1;
	return p;
}

function shuffle<T>(input: T[]): T[] {
	const arr = [...input];
	for (let i = arr.length - 1; i > 0; i--) {
		const j = Math.floor(Math.random() * (i + 1));
		[arr[i], arr[j]] = [arr[j], arr[i]];
	}
	return arr;
}

/** Counts for the Today screen. */
export async function queueSummary(now = Date.now()) {
	const conn = await db();
	const settings = await getSettings();
	const eligible = await eligibleIds(settings);

	const dueRows = (
		await conn.all<{ id: string }>('SELECT card_id AS id FROM card_state WHERE due <= ?', [now])
	).filter((r) => eligible.has(r.id));

	const introduced = await newCardsIntroducedToday(now);
	const newAvailable = (
		await conn.all<{ id: string }>(
			`SELECT c.id FROM cards c
			 LEFT JOIN card_state s ON s.card_id = c.id
			 WHERE s.card_id IS NULL`
		)
	).filter((r) => eligible.has(r.id)).length;

	const room = Math.max(0, settings.sessionCardCap - dueRows.length);
	const newToShow = Math.min(newAvailable, room, Math.max(0, settings.newCardsPerDay - introduced));
	return {
		due: dueRows.length,
		new: newToShow,
		total: Math.min(dueRows.length + newToShow, settings.sessionCardCap),
		// "Nothing due" and "your filters exclude every card" look identical on
		// Today, but only one of them gets better by coming back tomorrow.
		deckEmpty: eligible.size === 0,
		// Neither does a zero new-card budget: the cards are there and eligible,
		// and tomorrow's reset of `introduced` changes nothing, because it is a
		// setting rather than a wait.
		newBudgetZero: settings.newCardsPerDay === 0 && newAvailable > 0
	};
}
