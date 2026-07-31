import { db } from '$lib/db';
import {
	CARD_TYPES,
	EAR_STAGES,
	SECTION_OF_TYPE,
	STAGES,
	STAGE_OF_TYPE,
	type CardType,
	type Section
} from '$lib/music/cards';
import { QUALITIES, type Quality } from '$lib/music/voicings';
import { REQUEST_RETENTION } from '$lib/scheduler/fsrs';

export interface Settings {
	/** Hard cap on a session, in minutes. Short and frequent beats long. */
	sessionMinutes: number;
	/** Hard cap on cards per session, whichever limit is hit first. */
	sessionCardCap: number;
	/** New cards introduced per day. Keeps the daily load from spiking. */
	newCardsPerDay: number;
	activeQualities: Quality[];
	activeCardTypes: CardType[];
	/**
	 * What was on offer when the deck lists above were last written. Without it
	 * a stored list is indistinguishable from an allow-list, and since every
	 * field is re-serialised whenever anything is saved, a drill added in a later
	 * version would never reach anyone already using the app.
	 */
	knownCardTypes: CardType[];
	knownQualities: Quality[];
	targetRetention: number;
	/** Blank the keyboard for this long before input, in ms. 0 disables. */
	visualiseDelayMs: number;
	/**
	 * Play the answer when a card is revealed — and, because an ear card's
	 * prompt IS the sound, whether the two ear decks are dealt at all.
	 */
	soundEnabled: boolean;
	/**
	 * Submit a one-tap card the moment its answer is tapped, with no Check.
	 * Only the drills a single tap can finish — quality, mode and interval —
	 * are affected; anything asking for a root as well, or for keys, still has
	 * a half-made answer to protect. Off by default: it trades a mis-tap, which
	 * is now unrecoverable, for a tap saved on every card, and which of those
	 * costs more is a matter of thumbs.
	 */
	instantAnswer: boolean;
	/**
	 * Highest stage of the theory path currently open, 1..3. Later stages'
	 * drills stay out of the deck until their stage is reached — adding
	 * four-note voicings while two-note ones are still being worked out dilutes
	 * both.
	 */
	unlockedStages: number;
	/**
	 * Which shape of the theory path this blob was written against. Bumped when
	 * the stages are renumbered, so an old stage number can be mapped rather
	 * than guessed at. 2 = the three-stage guide-tone path.
	 */
	pathVersion: number;
	/**
	 * The same for the ear path, 1..2. A separate number because it is a
	 * separate ladder: hearing intervals well enough to hear chord qualities has
	 * nothing to do with how fast you can spell a rootless voicing.
	 */
	earUnlockedStages: number;
	/** Let the app open the next stage itself when its criteria are met. */
	stageAutoUnlock: boolean;
}

export const DEFAULT_SETTINGS: Settings = {
	sessionMinutes: 6,
	sessionCardCap: 30,
	newCardsPerDay: 8,
	activeQualities: [...QUALITIES],
	activeCardTypes: [...CARD_TYPES],
	knownCardTypes: [...CARD_TYPES],
	knownQualities: [...QUALITIES],
	targetRetention: REQUEST_RETENTION,
	visualiseDelayMs: 0,
	soundEnabled: true,
	instantAnswer: false,
	unlockedStages: 1,
	pathVersion: 2,
	earUnlockedStages: 1,
	stageAutoUnlock: true
};

export async function getSettings(): Promise<Settings> {
	const conn = await db();
	const rows = await conn.all<{ key: string; value: string }>('SELECT key, value FROM settings');
	const stored: Record<string, unknown> = {};
	for (const row of rows) {
		try {
			stored[row.key] = JSON.parse(row.value);
		} catch {
			// A corrupt row falls back to the default rather than taking the app down.
		}
	}
	// Held before the renumbering below rewrites it: the ear migration asks what
	// the learner had reached on the OLD ladder, and reading the mapped number
	// only happens to give the same answer under today's mapping.
	let earSourceStage = Number(stored.unlockedStages ?? 1);
	// Settings stored before the path existed have no unlockedStages at all: the
	// only gate back then was rootlessUnlocked, so every other drill was already
	// being served. Falling through to the default would demote someone who had
	// been practising for months to stage 1 and empty most of their schedule, so
	// a legacy blob maps to "everything but the rootless stage" — or to the last
	// stage if the rootless gate had already opened. Only a blob that was
	// actually stored counts: a fresh install has no rows and starts at stage 1.
	// Applied before the defaults merge, which would otherwise mask the absence.
	if (rows.length > 0 && !('unlockedStages' in stored)) {
		stored.unlockedStages = stored.rootlessUnlocked === true ? 3 : 2;
		earSourceStage = Number(stored.unlockedStages);
	}
	// A blob from the four-stage path (shells → ii–V–I → guide tones →
	// rootless) has no pathVersion. Its stage number is renumbered into the
	// three-stage guide-tone path: the old guide-tone stage (3) folds into the
	// new ii–V–I (2), old rootless (4) becomes 3. Keyed on the version marker,
	// not the value — a new-era 3 means rootless is open and must not be
	// demoted. Nothing writes the marker until the next save, so this runs on
	// every load until then and MUST stay idempotent: it maps the stored value,
	// it never steps the live one, or a learner would lose a stage per launch.
	else if (rows.length > 0 && stored.pathVersion !== 2) {
		const old = Number(stored.unlockedStages);
		stored.unlockedStages = old >= 4 ? 3 : old === 3 ? 2 : old;
	}
	// The ear drills used to ride on the theory path — intervals-by-ear in stage
	// 1, qualities-by-ear in stage 2 — before they became a section with a
	// ladder of its own. A blob from then has no earUnlockedStages, and falling
	// through to the default would take qualities-by-ear away from someone who
	// has been practising it for months. Their old theory stage says whether it
	// had opened, so it is the one honest answer available.
	if (rows.length > 0 && !('earUnlockedStages' in stored)) {
		stored.earUnlockedStages = earSourceStage >= 2 ? 2 : 1;
	}
	// A blob written before the known-lists existed records nothing about what
	// was on offer at the time, so every drill and quality counts as new to it
	// and arrives switched on. That re-offers anything deliberately switched off,
	// once — the alternative is that whatever the blob happens to hold becomes a
	// permanent allow-list and later drills never reach that device at all.
	// Applied before the defaults merge, which would otherwise mask the absence.
	if (rows.length > 0) {
		if (!('knownCardTypes' in stored)) stored.knownCardTypes = [];
		if (!('knownQualities' in stored)) stored.knownQualities = [];
	}
	return sanitise({ ...DEFAULT_SETTINGS, ...stored });
}

export async function saveSettings(patch: Partial<Settings>): Promise<Settings> {
	const conn = await db();
	let next!: Settings;
	// The read belongs INSIDE the transaction: every field is re-serialised on
	// every save, so a read taken off the tx chain lets two overlapping saves
	// both start from the pre-write blob and the second one write its stale copy
	// of the first one's keys back. Route preloading makes that ordinary — Today
	// auto-unlocks a theory stage while Ear's loader is auto-unlocking an ear
	// one — and the unlock announced on screen would be gone from the database.
	// getSettings only reads, so nesting it here cannot re-enter tx().
	await conn.tx(async () => {
		next = sanitise({ ...(await getSettings()), ...patch });
		for (const [key, value] of Object.entries(next)) {
			await conn.run(
				`INSERT INTO settings (key, value) VALUES (?, ?)
				 ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
				[key, JSON.stringify(value)]
			);
		}
	});
	await conn.persist();
	return next;
}

function clamp(n: unknown, min: number, max: number, fallback: number): number {
	const v = typeof n === 'number' && Number.isFinite(n) ? n : fallback;
	return Math.min(max, Math.max(min, v));
}

/** Never let stored settings produce an empty deck or an unbounded session. */
function sanitise(s: Settings): Settings {
	const qualities = (Array.isArray(s.activeQualities) ? s.activeQualities : []).filter(
		(q): q is Quality => QUALITIES.includes(q)
	);
	const types = (Array.isArray(s.activeCardTypes) ? s.activeCardTypes : []).filter(
		(t): t is CardType => CARD_TYPES.includes(t)
	);
	const knownTypes = Array.isArray(s.knownCardTypes) ? s.knownCardTypes : [];
	const knownQualities = Array.isArray(s.knownQualities) ? s.knownQualities : [];
	// Anything the stored settings never knew about is new to this user, and new
	// drills join the deck rather than waiting to be discovered in Settings.
	const activeTypes = CARD_TYPES.filter((t) => types.includes(t) || !knownTypes.includes(t));
	const activeQualities = QUALITIES.filter(
		(q) => qualities.includes(q) || !knownQualities.includes(q)
	);
	return {
		sessionMinutes: clamp(s.sessionMinutes, 1, 30, DEFAULT_SETTINGS.sessionMinutes),
		sessionCardCap: clamp(s.sessionCardCap, 5, 200, DEFAULT_SETTINGS.sessionCardCap),
		newCardsPerDay: clamp(s.newCardsPerDay, 0, 50, DEFAULT_SETTINGS.newCardsPerDay),
		activeQualities: activeQualities.length ? activeQualities : [...QUALITIES],
		activeCardTypes: activeTypes.length ? activeTypes : [...CARD_TYPES],
		knownCardTypes: [...CARD_TYPES],
		knownQualities: [...QUALITIES],
		targetRetention: clamp(s.targetRetention, 0.7, 0.98, DEFAULT_SETTINGS.targetRetention),
		visualiseDelayMs: clamp(s.visualiseDelayMs, 0, 10000, DEFAULT_SETTINGS.visualiseDelayMs),
		soundEnabled: s.soundEnabled !== false,
		// The other way round from soundEnabled: an absent or corrupt value means
		// off, because turning this on for someone who never asked for it makes
		// every stray tap a wrong answer.
		instantAnswer: s.instantAnswer === true,
		unlockedStages: clamp(s.unlockedStages, 1, STAGES.length, 1),
		pathVersion: 2,
		earUnlockedStages: clamp(s.earUnlockedStages, 1, EAR_STAGES.length, 1),
		stageAutoUnlock: s.stageAutoUnlock !== false
	};
}

/**
 * Card types the deck may draw from right now: active AND inside an open stage
 * of their own section. The two paths are independent ladders, so a drill is
 * measured against its own section's progress and never the other's.
 */
export function effectiveCardTypes(s: Settings): CardType[] {
	return s.activeCardTypes.filter((t) => STAGE_OF_TYPE[t] <= openStages(s, SECTION_OF_TYPE[t]));
}

export function openStages(s: Settings, section: Section): number {
	return section === 'ear' ? s.earUnlockedStages : s.unlockedStages;
}
