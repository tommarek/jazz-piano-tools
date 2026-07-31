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
	stagesOf,
	GT_CLASS_ACCEPTS,
	renderCard,
	parseCardId,
	sectionOfId,
	type CardType,
	type CardView,
	type GtClass,
	type Section
} from '$lib/music/cards';
import { getSettings, type Settings } from './settings';
import {
	ALL_DECK,
	deckAhead,
	deckBlock,
	deckLabel,
	deckSection,
	deckSlug,
	liveDeckTypes,
	type DeckBlock,
	type DeckRef
} from './decks';
import { CHAIN_QUALITIES, FOURTHS_ORDER, type Quality } from '$lib/music/voicings';
import { DIATONIC } from '$lib/music/theory-drills';
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

/**
 * Cards seen for the first time today — the budget that newCardsPerDay caps.
 *
 * Counted per section, because the sections are separate practices and one
 * pool made them compete: a theory session first thing spent the whole day's
 * allowance, so `/ear` introduced nothing that day, and a learner who always
 * opens Theory first never got a first `eint` card at all — the ear ladder
 * gates on 20 heard intervals, so it could never start.
 */
export async function newCardsIntroducedToday(
	now = Date.now(),
	section: Section = 'theory'
): Promise<number> {
	const conn = await db();
	const dayStart = startOfDay(now);
	const rows = await conn.all<{ card_id: string }>(
		`SELECT card_id FROM reviews WHERE ts >= ?
		 EXCEPT
		 SELECT card_id FROM reviews WHERE ts < ?`,
		[dayStart, dayStart]
	);
	return rows.filter((r) => sectionOfId(r.card_id) === section).length;
}

export interface CardRow {
	id: string;
	type: string;
	quality: string | null;
}

/**
 * Whether a card's quality is one of the ones being drilled.
 *
 * gtn names no quality of its own but is still answered with one: its
 * `quality` column holds a guide-tone interval class, and every quality
 * consistent with the pair is accepted — so the rule is "any accepted reading
 * is being drilled". Matching the column literally would drop the class named
 * 'maj7' for someone drilling only m7, even though that class IS the m7 pair.
 *
 * The progression types store no quality either, but they are *made of* chords,
 * and unlike the two above those are a conjunction rather than a choice: the
 * card is answered by producing all of them. So the rule is "every chord in it
 * is being drilled" — waving them through served a minor chain (iiø, V7,
 * i m maj7) to someone who had switched m7♭5 and m(maj7) off and could not be
 * dealt a single m7♭5 guide-tone pair. The mode is read off the id, the
 * discriminator stages.ts already uses; rlc is major-only and has no mode
 * segment.
 *
 * The degree types store no quality either, and they were the last hole: with
 * m7♭5 off, `dia:C:vii` still asked for Bm7♭5 by name and `mode:C:vii` still
 * titled itself Bm7♭5. The degree fixes the chord, so the switch decides which
 * rungs of the diatonic ladder get drilled — the same way it decides which
 * chains do.
 */
const PROGRESSION_TYPES = ['chain', 'gtc', 'rlc'];
const DEGREE_TYPES = ['dia', 'mode'];

/**
 * The chords a progression card actually contains. Only `chain` spans the whole
 * ii–V–I; gtc and rlc are *transition* cards covering one step of it, so
 * demanding the third chord's quality withheld cards they never show — with
 * maj7 off, `gtc:C:ii-V` is Dm7 → G7 and has no maj7 anywhere in it.
 */
function progressionQualities(type: string, id: string): Quality[] {
	const [ii, V, I] = CHAIN_QUALITIES[id.endsWith(':minor') ? 'minor' : 'major'];
	if (type === 'chain') return [ii, V, I];
	// The transition is a whole id segment, so it cannot collide with a root slug.
	return id.split(':').includes('ii-V') ? [ii, V] : [V, I];
}

/** The chord a degree card names, off the numeral its id carries. */
function degreeQuality(id: string): Quality | null {
	return DIATONIC.find((d) => d.numeral === id.split(':')[2])?.quality ?? null;
}

/**
 * The single chord quality a card is about, or null where no one quality is:
 * gtn's column is an interval class several qualities fit, a progression spans
 * all of its chords at once, and the interval drills name none. It is the
 * answer for most types and for `dia`, whose answer is root + quality; for
 * `mode` it is the chord in the prompt, since naming the mode over Bm7♭5 is
 * still m7♭5 recall. Filing a card under a quality — on Progress, say — is only
 * honest where this returns one, which is not the same question as which cards
 * a quality gates.
 */
export function soleQuality(row: CardRow): Quality | null {
	if (row.type === 'gtn' || PROGRESSION_TYPES.includes(row.type)) return null;
	if (DEGREE_TYPES.includes(row.type)) return degreeQuality(row.id);
	return row.quality as Quality | null;
}

export function qualityActive(row: CardRow, settings: Settings): boolean {
	const anyActive = (qualities: Quality[]) =>
		qualities.some((q) => settings.activeQualities.includes(q));
	if (row.type === 'gtn') return anyActive(GT_CLASS_ACCEPTS[row.quality as GtClass] ?? []);
	if (DEGREE_TYPES.includes(row.type)) {
		const quality = degreeQuality(row.id);
		return quality ? settings.activeQualities.includes(quality) : true;
	}
	if (PROGRESSION_TYPES.includes(row.type))
		return progressionQualities(row.type, row.id).every((q) =>
			settings.activeQualities.includes(q)
		);
	if (row.quality === null) return true;
	return settings.activeQualities.includes(row.quality as never);
}

/**
 * Every card the deck may draw from: active types and active qualities, and —
 * when a session is pointed at one deck — that deck's types as well. Which
 * gates the deck itself carries is `liveDeckTypes`'s business: a section deck
 * applies the path, a stage or drill deck deliberately does not. What no deck
 * can widen is a drill switched off, or an ear drill with the sound off.
 */
export async function eligibleIds(settings: Settings, deck: DeckRef = ALL_DECK): Promise<Set<string>> {
	const conn = await db();
	const types = liveDeckTypes(deck, settings);
	const rows = await conn.all<CardRow>('SELECT id, type, quality FROM cards');

	return new Set(
		rows
			.filter((r) => types.includes(r.type as never))
			// The quality filter is about which chords you want to drill. It applies
			// to every card that names one — directly, or through the degree or the
			// progression it is built on; the interval drills name none.
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
	/** Restrict the session to one deck. Defaults to everything eligible. */
	deck?: DeckRef;
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
	const deck = opts.deck ?? ALL_DECK;
	const eligible = await eligibleIds(settings, deck);

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
	const budget = Math.min(
		room,
		Math.max(0, settings.newCardsPerDay - (await newCardsIntroducedToday(now, deckSection(deck))))
	);
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
 * symbol→guide-tone cards on the same root before anything else — and a type-only
 * round-robin still serves nothing but C for the first week, because every
 * type's catalogue starts at C. Each type also starts its root rotation at a
 * different offset, so even a one-card-per-type day spans several keys. The
 * selection stays deterministic, which SQLite's unordered scan was not.
 *
 * `seenByType` — how many cards of each type have already been introduced —
 * is what carries both rotations between sessions. Without it every session
 * restarts at the same bucket, so a type introducing two cards a day never
 * leaves its first two keys, and stage 2 (which wants an automatic guide-tone
 * pair in all twelve) stays shut for months; and every session would walk the types
 * from the top, so with a budget smaller than the number of live types the
 * ones at the bottom of the list would never be introduced at all.
 */
export function spreadAcrossTypes<T extends { id: string; type: string }>(
	cards: T[],
	budget: number,
	seenByType: Map<string, number> = new Map()
): T[] {
	if (budget <= 0) return [];
	// The root/key is the second segment of every card id (e.g. "gt:Db:m7").
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
	// catalogue order every session would mean the tail of the list (the modes
	// and the ear drills) is never reached at all. Catalogue
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

export interface DeckCount {
	slug: string;
	label: string;
	due: number;
	/** New cards this deck could introduce right now, inside today's budget. */
	new: number;
	total: number;
	/** Every card the deck could ever deal, whatever its state. */
	size: number;
	block: DeckBlock;
	/** Past where the path has reached: drillable on request, not in the mix. */
	ahead: boolean;
}

/**
 * Due and new counts per deck, for the picker on Today.
 *
 * One pass over the card table for all of them: a query per deck would be
 * fourteen round trips to the database on every load of Today, and five more
 * on Ear.
 *
 * Each deck's `new` is counted as if it were the one you picked, because that
 * is the question the row answers. They are therefore NOT additive — the
 * new-card budget belongs to the day and to this section, and four decks each
 * showing today's whole budget reads as four times as many cards as exist.
 * Whoever renders these owns saying so once; `due` and `size` are the honestly
 * additive ones.
 */
export async function deckCounts(
	section: Section = 'theory',
	now = Date.now()
): Promise<{
	stages: DeckCount[];
	types: Record<number, DeckCount[]>;
	/** The whole section as one deck — what its Start button deals. */
	section: DeckCount;
	/** New cards left in today's budget for this section, shared by every deck above. */
	newBudget: number;
}> {
	const conn = await db();
	const settings = await getSettings();

	// Quality-filtered here rather than by type alone: the two lists gate one
	// deck, and a row counted on its type advertised cards its own session then
	// refused to deal — with 7 switched off, every chain fails qualityActive and
	// the chain row still offered its whole 24.
	const cardRows = (
		await conn.all<CardRow>('SELECT id, type, quality FROM cards')
	).filter((r) => qualityActive(r, settings));
	const typeOf = new Map(cardRows.map((r) => [r.id, r.type] as const));
	const sizeByType = new Map<string, number>();
	for (const r of cardRows) sizeByType.set(r.type, (sizeByType.get(r.type) ?? 0) + 1);
	const dueByType = new Map<string, number>();
	for (const r of await conn.all<{ id: string }>(
		'SELECT card_id AS id FROM card_state WHERE due <= ?',
		[now]
	)) {
		const t = typeOf.get(r.id);
		if (t) dueByType.set(t, (dueByType.get(t) ?? 0) + 1);
	}
	const unseenByType = new Map<string, number>();
	for (const r of await conn.all<{ id: string }>(
		`SELECT c.id FROM cards c LEFT JOIN card_state s ON s.card_id = c.id WHERE s.card_id IS NULL`
	)) {
		const t = typeOf.get(r.id);
		if (t) unseenByType.set(t, (unseenByType.get(t) ?? 0) + 1);
	}
	const budget = Math.max(0, settings.newCardsPerDay - (await newCardsIntroducedToday(now, section)));

	// Counted on the deck's live types only: a drill switched off contributes
	// nothing to the stage above it, so a stage row cannot advertise cards that
	// its own session would then refuse to deal.
	const count = (deck: DeckRef): DeckCount => {
		const live = liveDeckTypes(deck, settings);
		const due = live.reduce((n, t) => n + (dueByType.get(t) ?? 0), 0);
		const unseen = live.reduce((n, t) => n + (unseenByType.get(t) ?? 0), 0);
		const room = Math.max(0, settings.sessionCardCap - due);
		const fresh = Math.min(unseen, room, budget);
		const size = live.reduce((n, t) => n + (sizeByType.get(t) ?? 0), 0);
		// Its drills are on and its stage is live, but the quality switches leave
		// nothing inside them. deckBlock cannot see this — it reads settings, not
		// the deck — so the third reason is added here, where the cards are.
		const block =
			deckBlock(deck, settings) ?? (deck.kind !== 'section' && size === 0 ? 'qualities' : null);
		return {
			slug: deckSlug(deck),
			label: deckLabel(deck),
			due,
			new: fresh,
			total: Math.min(due + fresh, settings.sessionCardCap),
			size,
			block,
			ahead: deckAhead(deck, settings)
		};
	};

	const stages = stagesOf(section).map((st) => count({ kind: 'stage', section, n: st.n }));
	const types: Record<number, DeckCount[]> = {};
	for (const st of stagesOf(section))
		types[st.n] = st.types.map((t) => count({ kind: 'type', type: t }));
	return { stages, types, section: count({ kind: 'section', section }), newBudget: budget };
}

/** Counts for the Today screen — the theory section's, like everything on it. */
export async function queueSummary(now = Date.now()) {
	const conn = await db();
	const settings = await getSettings();
	const eligible = await eligibleIds(settings);

	const dueRows = (
		await conn.all<{ id: string }>('SELECT card_id AS id FROM card_state WHERE due <= ?', [now])
	).filter((r) => eligible.has(r.id));

	const introduced = await newCardsIntroducedToday(now, 'theory');
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
