/**
 * Evaluating the didactic path.
 *
 * Three theory stages (defined in cards.ts), each opened by demonstrated
 * mastery of the one before — a readiness ladder, not a paywall. The next stage's
 * criteria render as a checklist on Today, and Settings can open any stage by
 * hand for the impatient.
 */

import { db } from '$lib/db';
import { median } from '$lib/scheduler/grading';
import { EAR_STAGES, STAGES } from '$lib/music/cards';
import { getSettings, saveSettings } from './settings';
import { eligibleIds } from './queue';
import { CHAIN_QUALITIES, QUALITY_SUFFIX, keyLabel, type Quality } from '$lib/music/voicings';

/** Median per chord, in ms, that counts as automatic (opens the rootless stage). */
export const GATE_PER_CHORD_MS = 2000;
/** How many chain attempts the median must be drawn from before it means anything. */
export const GATE_MIN_SAMPLE = 20;
/** Share of each key's guide-tone cards that must be automatic for the key to be "green". */
export const GATE_KEY_SCORE = 0.5;

/**
 * The cards whose mastery the rootless-stage keys criterion — and the Progress
 * heatmap, which promises to be "the same measure" — are computed over: the
 * guide-tone family. Minor progressions are excluded so a freshly introduced
 * minor chain does not reopen a question the major ones already answered.
 */
export function isGtFamilyCard(type: string, id: string): boolean {
	return (
		type === 'gt' ||
		type === 'gtn' ||
		((type === 'chain' || type === 'gtc') && !id.endsWith(':minor'))
	);
}

export interface KeyScore {
	pitchClass: number;
	/** The cards scored, so a caller can join its own per-card data onto them. */
	ids: string[];
	total: number;
	automatic: number;
	familiar: number;
	/** 0..1 — share of the key's guide-tone-family cards that are automatic. */
	score: number;
}

/**
 * The twelve keys scored on the guide-tone family — the single measure behind
 * both the stage-3 keys criterion and the Progress heatmap, which captions
 * itself as that same measure.
 *
 * It has to live in one place because the two ends disagreed in a way neither
 * screen admitted: Progress filtered by the user's current stage lock, while
 * the criteria deliberately judge as if every stage were open (see
 * evaluateStages). On stage 1 that hides the chain and comping cards from one
 * screen and not the other, so the same key could read 100% on Progress and
 * 40% against the gate. Eligibility is resolved the criterion's way: the number
 * has to mean "how close is this key to opening the next stage".
 */
export async function keyScores(): Promise<KeyScore[]> {
	const conn = await db();
	const settings = await getSettings();
	const eligible = await eligibleIds({ ...settings, unlockedStages: STAGES.length });
	const rows = await conn.all<{ id: string; type: string; pc: number; mastery: string | null }>(
		`SELECT c.id, c.type, c.root_pitch_class AS pc, s.mastery
		 FROM cards c LEFT JOIN card_state s ON s.card_id = c.id`
	);
	const cells = rows.filter((r) => isGtFamilyCard(r.type, r.id) && eligible.has(r.id));

	const out: KeyScore[] = [];
	for (let pc = 0; pc < 12; pc++) {
		const ofKey = cells.filter((r) => r.pc === pc);
		const automatic = ofKey.filter((r) => r.mastery === 'automatic').length;
		out.push({
			pitchClass: pc,
			ids: ofKey.map((r) => r.id),
			total: ofKey.length,
			automatic,
			familiar: ofKey.filter((r) => r.mastery === 'familiar').length,
			score: ofKey.length ? automatic / ofKey.length : 0
		});
	}
	return out;
}

/**
 * Correct major-chain response times, newest first — the one population the
 * stage criteria and the Today headline draw their median from.
 */
export async function recentChainTimes(): Promise<number[]> {
	const conn = await db();
	// mode != 'speed' for the same reason the per-card median excludes sprints
	// (review.ts): sprint times are systematically faster, and here they would
	// loosen the bar — a stage could open off data the grader refuses to trust.
	const rows = await conn.all<{ response_ms: number }>(
		`SELECT response_ms FROM reviews
		 WHERE card_id LIKE 'chain:%' AND card_id NOT LIKE '%:minor' AND correct = 1
		   AND mode != 'speed'
		 ORDER BY ts DESC LIMIT 30`
	);
	return rows.map((r) => r.response_ms);
}

export interface StageCriterion {
	met: boolean;
	label: string;
}

/** Attempts the ear gate needs before its accuracy means anything. */
export const EAR_MIN_SAMPLE = 20;
/** Accuracy on heard intervals that opens qualities by ear. */
export const EAR_GATE_ACCURACY = 0.8;

export interface EarStatus {
	unlocked: number;
	justUnlocked: number | null;
	next: { n: number; title: string; criteria: StageCriterion[] } | null;
	/** Accuracy over the counted window, or null before there is one. */
	accuracy: number | null;
	attempts: number;
}

/**
 * The ear path, which is its own ladder: hearing chord qualities is heard as
 * the intervals inside them, so intervals come first and qualities open on
 * demonstrated accuracy rather than on anything the theory path did.
 *
 * Accuracy, not speed. The theory gates are all about time because recall
 * should become automatic; perception does not work that way, and a
 * three-second interval named correctly is worth more than a fast guess.
 * Speed rounds are excluded for the same reason they are everywhere else.
 */
export async function evaluateEarPath(): Promise<EarStatus> {
	const conn = await db();
	const settings = await getSettings();
	const rows = await conn.all<{ correct: number }>(
		`SELECT correct FROM reviews
		 WHERE card_id LIKE 'eint:%' AND mode != 'speed'
		 ORDER BY ts DESC LIMIT ?`,
		[EAR_MIN_SAMPLE]
	);
	const attempts = rows.length;
	const accuracy = attempts ? rows.filter((r) => r.correct === 1).length / attempts : null;
	const earActive = settings.activeCardTypes.includes('eint') && settings.soundEnabled;

	const criterion: StageCriterion = !earActive
		? {
				met: false,
				// Two ways to have no interval cards at all, and only one of them is
				// the drill's own tick — the ear decks leave the deck with the sound.
				label: settings.soundEnabled
					? 'Turn the intervals-by-ear drill on in Settings to work toward this'
					: 'Turn Sound on in Settings — the ear drills are the sound'
			}
		: {
				met: attempts >= EAR_MIN_SAMPLE && (accuracy ?? 0) >= EAR_GATE_ACCURACY,
				label:
					`${Math.round(EAR_GATE_ACCURACY * 100)}% on heard intervals over ` +
					`${EAR_MIN_SAMPLE} attempts` +
					(attempts
						? ` — at ${Math.round((accuracy ?? 0) * 100)}% over ${attempts}${
								attempts < EAR_MIN_SAMPLE ? `/${EAR_MIN_SAMPLE}` : ''
							}`
						: '')
			};

	let unlocked = Math.max(1, Math.min(EAR_STAGES.length, settings.earUnlockedStages));
	let justUnlocked: number | null = null;
	if (settings.stageAutoUnlock && unlocked < EAR_STAGES.length && criterion.met) {
		unlocked += 1;
		await saveSettings({ earUnlockedStages: unlocked });
		justUnlocked = unlocked;
	}

	const nextStage = EAR_STAGES.find((s) => s.n === unlocked + 1) ?? null;
	return {
		unlocked,
		justUnlocked,
		next: nextStage
			? { n: nextStage.n, title: nextStage.title, criteria: [criterion] }
			: null,
		accuracy,
		attempts
	};
}

/** Why no major chain can be dealt: its drill is off, or one of its chords is. */
export type ChainBlock = 'type' | 'qualities' | null;

/** "m7, 7 and maj7" — the qualities named the way Settings labels its ticks. */
function qualityList(qualities: Quality[]): string {
	const names = qualities.map((q) => QUALITY_SUFFIX[q]);
	if (names.length <= 1) return names.join('');
	return `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
}

export interface StagesStatus {
	/** Highest open stage, 1..STAGES.length. */
	unlocked: number;
	/** Stage that opened during this evaluation, announced once. */
	justUnlocked: number | null;
	auto: boolean;
	/** The next locked stage and what opens it; null when everything is open. */
	next: { n: number; title: string; criteria: StageCriterion[] } | null;
	/** Headline helpers for the Today screen. */
	keysMet: boolean;
	rootlessActive: boolean;
	/** Set when no major chain can be dealt, so Today can name the cause. */
	chainBlocked: ChainBlock;
}

export async function evaluateStages(): Promise<StagesStatus> {
	const conn = await db();
	const settings = await getSettings();
	// Criteria are judged as if every stage were open: they measure readiness
	// for the NEXT stage, so filtering by the current stage lock would make the
	// ladder climbable only one rung per visit and stall migrated progress.
	const eligible = await eligibleIds({ ...settings, unlockedStages: STAGES.length });
	// Both chain criteria and the Today headline read recentChainTimes(), which
	// counts MAJOR chains only — so it is dealability, not the type's tick, that
	// decides whether they can ever move. Switch m7, 7 or maj7 off and every
	// major chain leaves the deck while minor ones keep coming: the median would
	// sit at null forever behind a criterion that never says why.
	const chainsActive = settings.activeCardTypes.includes('chain');
	const chainsDealable = [...eligible].some(
		(id) => id.startsWith('chain:') && !id.endsWith(':minor')
	);
	const chainBlocked: ChainBlock = !chainsActive ? 'type' : chainsDealable ? null : 'qualities';
	// The type being on with all three qualities on always yields a dealable
	// major chain, so the 'qualities' branch always has something to name.
	const chainBlockedLabel = () =>
		chainBlocked === 'type'
			? 'Turn the ii–V–I chain drill on in Settings to work toward this'
			: `The ii–V–I chain needs ${qualityList([...CHAIN_QUALITIES.major])} — turn ` +
				`${qualityList(CHAIN_QUALITIES.major.filter((q) => !settings.activeQualities.includes(q)))} ` +
				'back on in Settings';

	const rows = await conn.all<{ id: string; type: string; pc: number; mastery: string | null }>(
		`SELECT c.id, c.type, c.root_pitch_class AS pc, s.mastery
		 FROM cards c LEFT JOIN card_state s ON s.card_id = c.id`
	);

	// ---- Stage 2 criterion: an automatic guide-tone pair in all twelve keys
	// Only cards the deck can actually serve count — scoring a quality the user
	// has switched off would make a stage unreachable.
	const pairCells = rows.filter(
		(r) => (r.type === 'gt' || r.type === 'gtn') && eligible.has(r.id)
	);
	const coveredKeys = new Set(
		pairCells.filter((r) => r.mastery === 'automatic').map((r) => r.pc)
	).size;
	// With both pair drills switched off nothing can ever be counted, so the
	// criterion would sit at a frozen 0/12 with no hint why — the same trap the
	// chain criteria below explain their way out of.
	const pairsActive =
		settings.activeCardTypes.includes('gt') || settings.activeCardTypes.includes('gtn');
	const stage2 = [
		pairsActive
			? {
					met: coveredKeys >= 12,
					label: `An automatic guide-tone pair in all twelve keys — ${coveredKeys}/12`
				}
			: {
					met: false,
					label: 'Turn a guide-tone drill on in Settings to work toward this'
				}
	];

	// ---- Stage 3 criteria: the rootless gate --------------------------------
	// Shared with the Progress heatmap, which promises to be this same measure.
	const times = await recentChainTimes();
	const chainMedian = median(times);
	const perChordMs = chainMedian === null ? null : Math.round(chainMedian / 3);
	const chainTimeCriterion = (targetMs: number): StageCriterion =>
		chainBlocked
			? { met: false, label: chainBlockedLabel() }
			: {
					met:
						perChordMs !== null && perChordMs < targetMs && times.length >= GATE_MIN_SAMPLE,
					label:
						`Chains under ${(targetMs / 1000).toFixed(1)}s per chord` +
						(perChordMs !== null
							? ` — at ${(perChordMs / 1000).toFixed(1)}s over ${times.length}${
									times.length < GATE_MIN_SAMPLE ? `/${GATE_MIN_SAMPLE}` : ''
								} correct chains`
							: '')
				};
	const scored = await keyScores();
	const familyTotal = scored.reduce((n, k) => n + k.total, 0);
	const weak = scored
		.filter((r) => r.score < GATE_KEY_SCORE)
		.sort((a, b) => a.score - b.score)
		.slice(0, 4);
	const keysMet = familyTotal > 0 && weak.length === 0;
	// "Weakest" needs a contrast: an empty deck, or one where every key sits
	// identically at zero, has no weakest key to name.
	const weakest =
		familyTotal && scored.some((r) => r.score > 0)
			? weak.map((r) => keyLabel(r.pitchClass))
			: [];
	const stage3 = [
		chainTimeCriterion(GATE_PER_CHORD_MS),
		// With no guide-tone-family card in the deck at all there is nothing to
		// score, so the criterion would sit frozen and unnamed — the same trap the
		// pair criterion above and the chain ones beside it explain their way out
		// of.
		familyTotal === 0
			? { met: false, label: 'Turn a guide-tone drill on in Settings to work toward this' }
			: {
					met: keysMet,
					label:
						'Every key at least half automatic on guide tones' +
						(weakest.length ? ` — weakest ${weakest.join(', ')}` : '')
				}
	];

	// Hand-kept, and the one derivation from STAGES that does not scale with it:
	// a stage added to the ladder without a criterion here would read as
	// `undefined` and take Today's loader down with it. Typed as partial so both
	// readers have to say what happens then — an unmet placeholder, so a stage
	// nobody has written a gate for never opens itself. `stages.test.ts` pins the
	// map against STAGES so it stays unreachable.
	const criteriaFor: Partial<Record<number, StageCriterion[]>> = { 2: stage2, 3: stage3 };
	const criteria = (n: number): StageCriterion[] =>
		criteriaFor[n] ?? [{ met: false, label: `Open stage ${n} in Settings` }];

	// The ladder opens rung by rung, never skipping one on a fluke — but it
	// starts from where the user actually stands, not from stage 1. A stage
	// opened by hand in Settings counts as satisfied: re-judging it would pin
	// `earned` below `unlockedStages` forever, so no later stage could ever open
	// again and Today would render the next stage's fully ticked checklist with
	// nothing happening. The same freeze caught legitimate unlockers whenever a
	// settings change dropped an earlier criterion back under its threshold.
	// Seeding from the user's position also keeps Today honest by construction:
	// the checklist it shows for `unlocked + 1` is exactly what `earned` is
	// judged on, so an earlier stage can never be the silent blocker.
	let earned = Math.max(1, Math.min(STAGES.length, settings.unlockedStages));
	for (let n = earned + 1; n <= STAGES.length; n++) {
		if (criteria(n).every((c) => c.met)) earned = n;
		else break;
	}

	let unlocked = settings.unlockedStages;
	let justUnlocked: number | null = null;
	if (settings.stageAutoUnlock && earned > unlocked) {
		await saveSettings({ unlockedStages: earned });
		justUnlocked = earned;
		unlocked = earned;
	}

	const nextStage = STAGES.find((s) => s.n === unlocked + 1) ?? null;

	return {
		unlocked,
		justUnlocked,
		auto: settings.stageAutoUnlock,
		next: nextStage
			? { n: nextStage.n, title: nextStage.title, criteria: criteria(nextStage.n) }
			: null,
		keysMet,
		rootlessActive: settings.activeCardTypes.includes('rootless'),
		chainBlocked
	};
}
