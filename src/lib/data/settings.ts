import { db } from '$lib/db';
import { CARD_TYPES, STAGE_OF_TYPE, type CardType } from '$lib/music/cards';
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
	 * Highest stage of the path currently open, 1..4. Later stages' drills stay
	 * out of the deck until their stage is reached — adding four-note voicings
	 * while two-note ones are still being worked out dilutes both.
	 */
	unlockedStages: number;
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
	unlockedStages: 1,
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
	// Settings stored before the path existed have no unlockedStages at all: the
	// only gate back then was rootlessUnlocked, so every other drill was already
	// being served. Falling through to the default would demote someone who had
	// been practising for months to stage 1 and empty most of their schedule, so
	// a legacy blob maps to "everything but the rootless stage" — or to the last
	// stage if the rootless gate had already opened. Only a blob that was
	// actually stored counts: a fresh install has no rows and starts at stage 1.
	// Applied before the defaults merge, which would otherwise mask the absence.
	if (rows.length > 0 && !('unlockedStages' in stored)) {
		stored.unlockedStages = stored.rootlessUnlocked === true ? 4 : 3;
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
	const next = sanitise({ ...(await getSettings()), ...patch });
	await conn.tx(async () => {
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
		unlockedStages: clamp(s.unlockedStages, 1, 4, 1),
		stageAutoUnlock: s.stageAutoUnlock !== false
	};
}

/** Card types the deck may draw from right now: active AND inside an open stage. */
export function effectiveCardTypes(s: Settings): CardType[] {
	return s.activeCardTypes.filter((t) => STAGE_OF_TYPE[t] <= s.unlockedStages);
}
