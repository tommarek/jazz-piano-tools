/**
 * The card catalogue.
 *
 * Cards are generated deterministically from the theory engine, and their ids
 * are stable slugs — so the catalogue can grow without orphaning review
 * history. Nothing here touches the database.
 */

import { INTERVALS, INTERVAL_LABEL, midi, noteName, parseNote, pitchClass, prettyNoteName, transpose, simplifyIfExtreme, prefersFlats } from './theory';
import type { IntervalName, Note } from './theory';
import {
	DIATONIC,
	DRILLED_INTERVALS,
	EXTENSIONS,
	diatonicRoot,
	type DiatonicDegree
} from './theory-drills';
import {
	CHAIN_MODES,
	CHAIN_MODE_LABEL,
	CHORD_ROOTS,
	KEY_CENTERS,
	MINOR_KEY_CENTERS,
	QUALITIES,
	QUALITY_LABEL,
	ROOTLESS_FORMS,
	ROOTLESS_QUALITIES,
	ROOT_OCTAVE,
	buildChain,
	buildChord,
	buildRootless,
	chordRootName,
	chordSymbol,
	type ChainMode,
	type Chord,
	type Quality,
	type RootlessForm,
	type RootlessQuality,
	type Transition
} from './voicings';

export type CardType =
	| 'chain'
	| 'gt'
	| 'gtn'
	| 'gtc'
	| 'rootless'
	| 'rlc'
	| 'ext'
	| 'dia'
	| 'ivl'
	| 'mode'
	| 'eint'
	| 'eqal';

export const CARD_TYPES: CardType[] = [
	'chain',
	'gt',
	'gtn',
	'gtc',
	'rootless',
	'rlc',
	'ext',
	'dia',
	'ivl',
	'mode',
	'eint',
	'eqal'
];

/**
 * The card types whose prompt is a sound and nothing else. With playback off
 * they have no question at all, so the queue drops them — see `eligibleIds`.
 */
export const EAR_TYPES: CardType[] = ['eint', 'eqal'];

/**
 * The two halves of the app.
 *
 * Reading a chord and hearing one are different skills on different clocks:
 * naming a symbol you can see is recall, and naming an interval you can only
 * hear is perception, which is slower for a long time and improves on its own
 * schedule. They were interleaved in one path, and that made every shared
 * number — the medians, the session, the stage criteria — an average of two
 * things that have no business being averaged. So they are separate sections
 * with separate paths, separate sessions and separate figures, over one
 * database and one scheduler.
 */
export type Section = 'theory' | 'ear';

export const SECTIONS: Section[] = ['theory', 'ear'];

export const SECTION_LABEL: Record<Section, string> = {
	theory: 'Theory',
	ear: 'Ear training'
};

/**
 * A didactic path: stages unlocked by demonstrated mastery of the one before
 * (or by hand in Settings). Each section has its own, numbered from 1 — a
 * stage number is only meaningful next to its section.
 */
export interface Stage {
	n: number;
	id: string;
	title: string;
	types: CardType[];
}

/**
 * The theory path. Guide tones first: the 3rd and 7th are the two notes that
 * name a chord's quality and the two that barely move through a progression,
 * so everything later — the timed chain, the rootless forms that wrap them —
 * is built out of them. (Root-based shells used to be stage 1; they were cut
 * because the pair is the thing worth automating, and the root belongs to the
 * bass player.)
 */
export const STAGES: Stage[] = [
	{ n: 1, id: 'guide-tones', title: 'Guide tones', types: ['gt', 'gtn', 'ivl'] },
	{ n: 2, id: 'two-five', title: 'The ii–V–I', types: ['chain', 'gtc', 'dia'] },
	{ n: 3, id: 'rootless', title: 'Rootless & colours', types: ['rootless', 'rlc', 'ext', 'mode'] }
];

/**
 * The ear path. Intervals first because a chord quality is heard as the
 * intervals inside it: someone who cannot hear a minor 3rd against a major 3rd
 * is guessing at m7 against 7, and guessing trains nothing.
 */
export const EAR_STAGES: Stage[] = [
	{ n: 1, id: 'ear-intervals', title: 'Intervals by ear', types: ['eint'] },
	{ n: 2, id: 'ear-qualities', title: 'Qualities by ear', types: ['eqal'] }
];

export function stagesOf(section: Section): Stage[] {
	return section === 'ear' ? EAR_STAGES : STAGES;
}

export const SECTION_OF_TYPE: Record<CardType, Section> = Object.fromEntries(
	CARD_TYPES.map((t) => [t, EAR_TYPES.includes(t) ? 'ear' : 'theory'])
) as Record<CardType, Section>;

/**
 * Which half of the app a card belongs to, read off its id's first segment —
 * the only join available to code holding a review row rather than a card.
 * A type this build no longer knows counts as theory: it cannot be dealt
 * either way, and the theory figures are where its history already sat.
 */
export function sectionOfId(id: string): Section {
	return SECTION_OF_TYPE[id.split(':')[0] as CardType] ?? 'theory';
}

/**
 * Which stage of ITS OWN section a drill belongs to. Never compare one across
 * sections — ear stage 2 and theory stage 2 are different ladders.
 */
export const STAGE_OF_TYPE: Record<CardType, number> = Object.fromEntries(
	[...STAGES, ...EAR_STAGES].flatMap((s) => s.types.map((t) => [t, s.n]))
) as Record<CardType, number>;

export const CARD_TYPE_LABEL: Record<CardType, string> = {
	chain: 'ii–V–I chain',
	gt: 'Symbol → guide tones',
	gtn: 'Guide tones → symbol',
	gtc: 'Guide-tone comping',
	rootless: 'Rootless A/B',
	rlc: 'Rootless A/B comping',
	ext: 'Extensions & alterations',
	dia: 'Diatonic harmony',
	ivl: 'Intervals',
	mode: 'Scales & modes',
	eint: 'Intervals by ear',
	eqal: 'Qualities by ear'
};

export const CARD_TYPE_HINT: Record<CardType, string> = {
	chain: 'The guide tones of a whole ii–V–I, timed as one — major and minor',
	gt: 'Tap the 3rd and 7th — the pair a bassist frees your hand to play',
	gtn: 'Two guide tones, 3rd marked — name a quality they fit',
	gtc: 'Comp a ii–V–I in guide-tone voicings: one note holds, one moves',
	rootless: 'Four-note A and B forms, tapped bottom-up',
	rlc: 'Alternate the A and B forms through a ii–V–I, tapped bottom-up',
	ext: 'Find the ♭9, ♯11, 13 and friends',
	dia: 'Which chord is the ii, the IV, the vii?',
	ivl: 'Raw interval recall',
	mode: 'Which mode fits which chord',
	eint: 'Two notes played — name the interval you heard',
	eqal: 'A chord played — name the quality you heard'
};

/**
 * The three interval classes a guide-tone pair can form, keyed by a canonical
 * quality. Two guide tones fix neither the quality nor even the root: F and C
 * (a 5th apart) are the 3–7 of D♭maj7 and equally the ♭3–♭7 of Dm7 or Dm7♭5.
 * Every reading in a class is accepted at answer time.
 */
export type GtClass = 'maj7' | '7' | 'mMaj7';
export const GT_CLASSES: GtClass[] = ['maj7', '7', 'mMaj7'];
export const GT_CLASS_ACCEPTS: Record<GtClass, Quality[]> = {
	// 3rd and 7th a perfect 5th apart
	maj7: ['maj7', 'm7', 'm7b5'],
	// a tritone apart
	'7': ['7', 'dim7'],
	// a minor 6th apart — the one unambiguous pair
	mMaj7: ['mMaj7']
};

/**
 * Per-type response-time constants, in milliseconds.
 *
 * `baseline` stands in for the rolling median until a card has enough history.
 * `automatic` is the median a card must beat before it counts as mastered —
 * without that gate, "mastered" would only mean "eventually correct".
 */
export const TIME_TARGETS: Record<CardType, { baseline: number; automatic: number }> = {
	chain: { baseline: 12000, automatic: 6000 },
	gt: { baseline: 4000, automatic: 2000 },
	gtn: { baseline: 5000, automatic: 2500 },
	gtc: { baseline: 4500, automatic: 2200 },
	// Four ordered taps: anything under gt's 1000 ms/tap would make the gated,
	// harder card stricter per action than the guide-tone pair it graduates from.
	rootless: { baseline: 8000, automatic: 4500 },
	rlc: { baseline: 8000, automatic: 4500 },
	ext: { baseline: 4000, automatic: 2000 },
	dia: { baseline: 5000, automatic: 2500 },
	ivl: { baseline: 3500, automatic: 1800 },
	mode: { baseline: 4500, automatic: 2200 },
	// The clock starts with the prompt, and on an ear card the prompt takes time
	// to happen: the second note of an interval only arrives 0.7s in, and a chord
	// has to ring before it is anything but an attack. So both targets carry ~1.5s
	// of listening that no amount of fluency removes — eint's 3500 ms automatic is
	// ivl's 1800 ms of naming with the sound's own length added, not a softer bar.
	eint: { baseline: 6000, automatic: 3500 },
	// Six qualities off one strike is a harder discrimination than an interval,
	// and replaying is expected rather than a failure, so the baseline is looser.
	eqal: { baseline: 7000, automatic: 4000 }
};

export const TRANSITIONS: Transition[] = ['ii-V', 'V-I'];

export type CardSpec =
	// The chain is played entirely in guide-tone pairs — one card per key per
	// mode, because a 3–7 pair has no root to hang a variant on.
	| { id: string; type: 'chain'; key: string; mode: ChainMode }
	| { id: string; type: 'gt'; root: string; quality: Quality }
	// gtn's quality is the canonical reading of an interval class — every quality
	// sharing the same 3rd→7th distance is accepted at answer time.
	| { id: string; type: 'gtn'; root: string; quality: GtClass }
	| { id: string; type: 'gtc'; key: string; transition: Transition; mode: ChainMode }
	| { id: string; type: 'rootless'; root: string; quality: RootlessQuality; form: RootlessForm }
	| { id: string; type: 'rlc'; key: string; transition: Transition; form: RootlessForm }
	| { id: string; type: 'ext'; root: string; quality: Quality; interval: IntervalName }
	| { id: string; type: 'dia'; key: string; numeral: string }
	| { id: string; type: 'ivl'; root: string; interval: IntervalName }
	| { id: string; type: 'mode'; key: string; numeral: string }
	// The root of an ear card is never shown and never asked — it is only there
	// because the same interval from a different starting note is a different
	// rep for the ear, and because a card needs something to vary over.
	| { id: string; type: 'eint'; root: string; interval: IntervalName }
	| { id: string; type: 'eqal'; root: string; quality: Quality };

/** '#' is not URL- or filename-friendly; 's' is unambiguous here because
 *  flats are already written 'b' and no root is named 'Ds'. */
function slug(name: string): string {
	return name.replace('#', 's');
}

function unslug(name: string): string {
	return name.length === 2 && name[1] === 's' ? name[0] + '#' : name;
}

/** Distributive Omit, so the union's discriminant survives. */
type WithoutId<T> = T extends unknown ? Omit<T, 'id'> : never;

export function cardId(spec: WithoutId<CardSpec>): string {
	switch (spec.type) {
		// Deliberately NOT the old shell-chain ids (chain:C:737): the guide-tone
		// chain is a different question, and inheriting the shell chains' review
		// history would schedule it as if it had already been practised.
		case 'chain':
			return `chain:${slug(spec.key)}${spec.mode === 'minor' ? ':minor' : ''}`;
		case 'gt':
			return `gt:${slug(spec.root)}:${spec.quality}`;
		case 'gtn':
			return `gtn:${slug(spec.root)}:${spec.quality}`;
		case 'gtc':
			return `gtc:${slug(spec.key)}:${spec.transition}${spec.mode === 'minor' ? ':minor' : ''}`;
		case 'rootless':
			return `rootless:${slug(spec.root)}:${spec.quality}:${spec.form}`;
		case 'rlc':
			return `rlc:${slug(spec.key)}:${spec.transition}:${spec.form}`;
		case 'ext':
			return `ext:${slug(spec.root)}:${spec.quality}:${spec.interval}`;
		case 'dia':
			return `dia:${slug(spec.key)}:${spec.numeral}`;
		case 'ivl':
			return `ivl:${slug(spec.root)}:${spec.interval}`;
		case 'mode':
			return `mode:${slug(spec.key)}:${spec.numeral}`;
		case 'eint':
			return `eint:${slug(spec.root)}:${spec.interval}`;
		case 'eqal':
			return `eqal:${slug(spec.root)}:${spec.quality}`;
	}
}

function push(cards: CardSpec[], spec: WithoutId<CardSpec>) {
	cards.push({ id: cardId(spec), ...spec } as CardSpec);
}

/** The full deck. */
export function buildCatalogue(): CardSpec[] {
	const cards: CardSpec[] = [];

	for (const root of CHORD_ROOTS) {
		for (const quality of QUALITIES) {
			push(cards, { type: 'gt', root, quality });
		}
		for (const cls of GT_CLASSES) {
			push(cards, { type: 'gtn', root, quality: cls });
		}
		for (const quality of ROOTLESS_QUALITIES) {
			for (const form of ROOTLESS_FORMS) {
				push(cards, { type: 'rootless', root, quality, form });
			}
		}
		for (const [quality, extensions] of Object.entries(EXTENSIONS)) {
			for (const ext of extensions) {
				push(cards, { type: 'ext', root, quality: quality as Quality, interval: ext.interval });
			}
		}
		for (const interval of DRILLED_INTERVALS) {
			push(cards, { type: 'ivl', root, interval });
			push(cards, { type: 'eint', root, interval });
		}
		for (const quality of QUALITIES) {
			push(cards, { type: 'eqal', root, quality });
		}
	}

	for (const mode of CHAIN_MODES) {
		const keys = mode === 'major' ? KEY_CENTERS : MINOR_KEY_CENTERS;
		for (const key of keys) {
			push(cards, { type: 'chain', key, mode });
		}
	}

	for (const mode of CHAIN_MODES) {
		const keys = mode === 'major' ? KEY_CENTERS : MINOR_KEY_CENTERS;
		for (const key of keys) {
			for (const transition of TRANSITIONS) {
				push(cards, { type: 'gtc', key, transition, mode });
			}
		}
	}

	// Rootless comping is major-only: the minor tonic is m(maj7), which has no
	// rootless form in this deck.
	for (const key of KEY_CENTERS) {
		for (const transition of TRANSITIONS) {
			for (const form of ROOTLESS_FORMS) {
				push(cards, { type: 'rlc', key, transition, form });
			}
		}
	}

	for (const key of KEY_CENTERS) {
		for (const degree of DIATONIC) {
			push(cards, { type: 'dia', key, numeral: degree.numeral });
			push(cards, { type: 'mode', key, numeral: degree.numeral });
		}
	}

	return cards;
}

// ---------------------------------------------------------------------------
// Rendering a card into everything the UI needs
// ---------------------------------------------------------------------------

export interface AnswerStep {
	/** 'ii' / 'V' / 'I' for chains, empty for single-chord cards */
	position: string;
	symbol: string;
	answerLabel: string;
	/** Pitch classes the learner must select */
	expected: number[];
	/**
	 * When true the taps must arrive in this exact order. Rootless A and B forms
	 * are the same four pitch classes in a different voice order, so with the
	 * answer graded by pitch class nothing but the tap order tells them apart.
	 */
	ordered?: boolean;
	/** Note names, as spelled */
	names: string[];
}

export interface CardView {
	id: string;
	type: CardType;
	/** Large text at the top of the card */
	title: string;
	/** Smaller line under it saying what to produce */
	instruction: string;
	/** How the answer is entered */
	input: 'keys' | 'chord-name' | 'quality-name' | 'mode-name' | 'interval-name';
	/**
	 * The card asks a sound, not a symbol: there is nothing to read, so the
	 * prompt plays itself when the card appears and offers a replay button. The
	 * notes stay off the keyboard until the reveal — showing them would answer
	 * the question.
	 */
	promptIsSound?: boolean;
	/** Keys already lit on the prompt keyboard (notes → symbol, voice leading) */
	given: number[];
	/** Which of the given keys is the root — marked so the prompt is unambiguous */
	rootGiven?: number;
	/** Label for the rootGiven marker; defaults to 'R'. Guide-tone cards mark
	 *  the 3rd instead, because the voicing has no root to mark. */
	givenMarkerLabel?: string;
	/** For 'keys' input: the steps to be answered, in order */
	steps: AnswerStep[];
	/**
	 * For 'chord-name' input. Graded on `rootPc`, not on `root`: the IV of G♭ is
	 * C♭ and the vii of B is A♯, neither of which is on the root picker, and
	 * failing someone for tapping B or B♭ would be teaching the wrong lesson.
	 * The spelled name is shown in the feedback instead.
	 *
	 * `alsoAccept` lists every quality graded as correct — notes → symbol cards
	 * accept all the qualities the shell is consistent with, because two notes
	 * never pin down one chord. Absent means only `quality` is right.
	 */
	expectedChord?: { root: string; rootPc: number; quality: Quality; alsoAccept?: Quality[] };
	/** For 'mode-name' input */
	expectedMode?: string;
	/** For 'interval-name' input. Graded on the interval alone — the ear card it
	 *  belongs to never names the note it was measured from. */
	expectedInterval?: IntervalName;
	/** Plain-text answer, shown on reveal */
	answerText: string;
	/** One-line reason, shown on reveal */
	rationale: string;
	/** Reference topic this card sends you to when you ask why */
	topic: string;
	/** Pitch classes of the root, for the 12-key heatmap */
	rootPitchClass: number;
	timeTarget: { baseline: number; automatic: number };
	/**
	 * What the card sounds like, played on reveal. MIDI numbers rather than
	 * pitch classes, because the register is half of what makes a voicing
	 * recognisable; grouped so a chain or an interval can be played in time
	 * rather than as one pile of notes.
	 */
	sound?: { groups: number[][] };
}

/**
 * The chord an extension card sounds its colour over.
 *
 * Root, 3rd and 7th: the 5th is what a pianist drops first, and leaving it out
 * keeps the colour on top uncluttered. Except when the 5th is the altered one —
 * root–♭3–♭7 is m7's guide-tone sound, so an m7♭5 card without its ♭5 plays a
 * plain m7 and the ♭13 over it reads as a ♭6 of the wrong chord. dim7 is listed
 * for the same reason, against the day EXTENSIONS grows a dim7 row; it has none
 * today, so only the m7♭5 half of the test is ever taken.
 */
function extensionBed(chord: Chord): Note[] {
	const altered = chord.quality === 'm7b5' || chord.quality === 'dim7';
	return altered
		? [chord.tones[0], chord.tones[1], chord.tones[2], chord.tones[3]]
		: [chord.tones[0], chord.tones[1], chord.tones[3]];
}

/**
 * Playback for a card, from the notes the theory engine already built: they
 * carry their octaves, so a single voicing sounds where it was spelled. A card
 * of several groups is registered by {@link voiceLed} first — there the octaves
 * off the builders are the thing that has to be corrected.
 */
function sound(...groups: Note[][]): { groups: number[][] } {
	return { groups: groups.map((g) => g.map(midi)) };
}

/** The register playback stays inside — the same window the audio tests pin. */
const SOUND_LOW = 36;
const SOUND_HIGH = 84;

/**
 * Playback for a card whose subject is the movement between two voicings.
 *
 * Every chord is built from its own root at ROOT_OCTAVE, so a ii–V–I arrives as
 * chords in unrelated registers: the F a gtc card calls "held" would sound F3
 * then F4, and the guide tone that "falls a semitone" would leap down a major
 * 7th — the audio contradicting the rationale on exactly the cards about voice
 * leading. Each group after the first is re-registered against the previous one
 * *as already registered*, so a chain drifts with the harmony instead of
 * snapping back to the first chord.
 *
 * Anchoring a group on its lowest note cannot do this: roots fall in fourths,
 * so the bottom voice is the one that legitimately moves. What is chosen
 * instead is the octave transposition — plus, where a rotation cannot change
 * what the voicing IS, the inversion — that moves the voices least.
 * `invertible` is off by default, and the one caller that takes the default is
 * rlc: an A form rotated by two voices is the B form, the same four pitch
 * classes in the other order, so a "better register" would play the opposite
 * form from the one the card is asking for.
 */
function voiceLed(groups: Note[][], opts: { invertible?: boolean } = {}): { groups: number[][] } {
	const out: number[][] = [];
	for (const group of groups) {
		const raw = group.map(midi).sort((a, b) => a - b);
		const prev = out[out.length - 1];
		out.push(prev ? nearestVoicing(raw, prev, opts.invertible ?? false) : raw);
	}
	return { groups: out };
}

/**
 * The re-voicing of `notes` that sits closest to `prev`, measured as the total
 * distance from each voice to the nearest note of the group before it. Ties go
 * to the register the theory engine actually built, so a voicing that is
 * already in place stays where it was written.
 */
function nearestVoicing(notes: number[], prev: number[], invertible: boolean): number[] {
	let best = notes;
	let bestCost = Number.POSITIVE_INFINITY;
	let bestShift = Number.POSITIVE_INFINITY;
	for (const rotation of invertible ? rotations(notes) : [notes]) {
		for (let octaves = -4; octaves <= 4; octaves++) {
			const candidate = rotation.map((n) => n + octaves * 12).sort((a, b) => a - b);
			if (candidate.some((n) => n < SOUND_LOW || n > SOUND_HIGH)) continue;
			const cost = candidate.reduce(
				(sum, n) => sum + Math.min(...prev.map((p) => Math.abs(n - p))),
				0
			);
			const shift = candidate.reduce((sum, n, i) => sum + Math.abs(n - notes[i]), 0);
			if (cost < bestCost || (cost === bestCost && shift < bestShift)) {
				best = candidate;
				bestCost = cost;
				bestShift = shift;
			}
		}
	}
	return best;
}

/** Every inversion of a voicing: the bottom voice moved up an octave, again and again. */
function rotations(notes: number[]): number[][] {
	const out: number[][] = [];
	let current = notes;
	for (let i = 0; i < notes.length; i++) {
		out.push(current);
		current = [...current.slice(1), current[0] + 12];
	}
	return out;
}

function extensionLabel(quality: Quality, interval: IntervalName): string {
	return (
		EXTENSIONS[quality]?.find((e) => e.interval === interval)?.label ??
		INTERVAL_LABEL[interval]
	);
}

export function renderCard(spec: CardSpec): CardView {
	const timeTarget = TIME_TARGETS[spec.type];

	switch (spec.type) {
		case 'chain': {
			// The chords come from the same builder as before; the voicings do not.
			// Each step is the 3rd and 7th only — the pair that names the quality
			// and the pair that barely moves. No variant: a rootless pair has no
			// root to hang a 737/373 choice on, which is exactly the ambiguity the
			// old shell chains kept tripping over.
			const { chords, positions } = buildChain(spec.key, spec.mode);
			const pairs = chords.map((c) => [c.tones[1], c.tones[3]] as [Note, Note]);
			const heading = `${CHAIN_MODE_LABEL[spec.mode]} in ${prettyNoteName(spec.key)}${spec.mode === 'minor' ? ' minor' : ''}`;
			// Every transition of a fifths-fall does the same dance: the 3rd holds
			// as the next 7th, the 7th falls to the next 3rd. Said from the actual
			// notes so major's semitone and minor's whole tone both come out true.
			const fall = (i: number) => {
				const semis =
					(pitchClass(pairs[i][1]) - pitchClass(pairs[i + 1][0]) + 12) % 12;
				return `${chords[i].symbol}'s 7th (${noteName(pairs[i][1])}) falls ${
					semis === 1 ? 'a semitone' : 'a whole tone'
				} to ${chords[i + 1].symbol}'s 3rd (${noteName(pairs[i + 1][0])})`;
			};
			return {
				id: spec.id,
				type: spec.type,
				title: heading,
				instruction: 'Guide tones only — the 3rd and 7th of each chord',
				input: 'keys',
				given: [],
				steps: chords.map((chord, i) => ({
					position: positions[i],
					symbol: chord.symbol,
					answerLabel: '3rd and 7th',
					expected: [pitchClass(pairs[i][0]), pitchClass(pairs[i][1])],
					names: [noteName(pairs[i][0]), noteName(pairs[i][1])]
				})),
				answerText: chords
					.map((c, i) => `${c.symbol}: ${noteName(pairs[i][0])}–${noteName(pairs[i][1])}`)
					.join('   '),
				rationale: `${fall(0)}; ${fall(1)} — the other note holds each time.`,
				topic: spec.mode === 'minor' ? 'minor-two-five' : 'guide-tones',
				rootPitchClass: pitchClass(parseNote(spec.key, ROOT_OCTAVE)),
				timeTarget,
				// Pairs have no root to stand on, so later groups may invert as well
				// as re-register — same rule as gtc, the drill this one chains up.
				sound: voiceLed(
					pairs.map((pair) => [...pair]),
					{ invertible: true }
				)
			};
		}

		case 'rootless': {
			const voicing = buildRootless(spec.root, spec.quality, spec.form);
			return {
				id: spec.id,
				type: spec.type,
				title: voicing.symbol,
				instruction: `Rootless ${spec.form} form — tap the four notes bottom-up`,
				input: 'keys',
				given: [],
				steps: [
					{
						position: spec.form,
						symbol: voicing.symbol,
						answerLabel: `${spec.form} form`,
						expected: [...voicing.pitchClasses],
						ordered: true,
						names: [...voicing.names]
					}
				],
				answerText: `${voicing.names.join(' – ')}  (${voicing.stackLabel})`,
				rationale:
					spec.form === 'A'
						? `The A form puts the 3rd on the bottom: ${voicing.stackLabel}.`
						: `The B form puts the 7th on the bottom: ${voicing.stackLabel} — the A form's top two voices moved underneath.`,
				topic: 'rootless',
				rootPitchClass: pitchClass(parseNote(spec.root, ROOT_OCTAVE)),
				timeTarget,
				sound: sound([...voicing.notes])
			};
		}

		case 'gt': {
			const chord = buildChord(spec.root, spec.quality);
			const third = chord.tones[1];
			const seventh = chord.tones[3];
			return {
				id: spec.id,
				type: spec.type,
				title: chord.symbol,
				instruction: 'Guide-tone voicing — tap the 3rd and 7th',
				input: 'keys',
				given: [],
				steps: [
					{
						position: '',
						symbol: chord.symbol,
						answerLabel: 'guide tones',
						expected: [pitchClass(third), pitchClass(seventh)],
						names: [noteName(third), noteName(seventh)]
					}
				],
				answerText: `${noteName(third)} – ${noteName(seventh)}`,
				rationale: `${QUALITY_LABEL[spec.quality]}: the guide tones of ${chord.symbol} are its 3rd (${noteName(third)}) and 7th (${noteName(seventh)}). The root drops once a bassist is carrying it.`,
				topic: 'guide-tones',
				rootPitchClass: pitchClass(chord.tones[0]),
				timeTarget,
				sound: sound([third, seventh])
			};
		}

		case 'gtn': {
			const chord = buildChord(spec.root, spec.quality);
			const third = chord.tones[1];
			const seventh = chord.tones[3];
			const accepts = GT_CLASS_ACCEPTS[spec.quality];
			// The other readings share the pair but hang it on a different root: a
			// minor 3rd below the marked note. Down a m3 is spelled as up a M6.
			// Spelled off the 3rd it lands on roots no chart ever carries — F♯♯m7,
			// B♯m7 — so the pitch class is renamed from the root list instead.
			const altRoot = chordRootName(pitchClass(transpose(third, INTERVALS.M6)));
			const readings =
				spec.quality === 'maj7'
					? [chord.symbol, chordSymbol(altRoot, 'm7'), chordSymbol(altRoot, 'm7b5')]
					: spec.quality === '7'
						? [chord.symbol, chordSymbol(altRoot, 'dim7')]
						: [chord.symbol];
			return {
				id: spec.id,
				type: spec.type,
				title: 'Which chord could this be?',
				instruction: 'The 3rd is marked — name a quality these guide tones fit',
				input: 'quality-name',
				given: [pitchClass(third), pitchClass(seventh)],
				rootGiven: pitchClass(third),
				givenMarkerLabel: '3',
				steps: [],
				expectedChord: {
					root: spec.root,
					rootPc: pitchClass(chord.tones[0]),
					quality: accepts[0],
					alsoAccept: accepts
				},
				answerText: readings.join(', '),
				rationale:
					readings.length > 1
						? `Guide tones fix neither the quality nor the root: ${noteName(third)} + ${noteName(seventh)} serves ${readings.join(' and ')} alike. The root and the 5th — the notes that would separate them — are exactly the ones a guide-tone voicing leaves out.`
						: `A 3rd and 7th a minor 6th apart only happens on ${chord.symbol} — the one guide-tone pair that does name its chord.`,
				topic: 'guide-tones',
				rootPitchClass: pitchClass(chord.tones[0]),
				timeTarget,
				sound: sound([third, seventh])
			};
		}

		case 'gtc': {
			const chain = buildChain(spec.key, spec.mode);
			const i = spec.transition === 'ii-V' ? 0 : 1;
			const from = chain.chords[i];
			const to = chain.chords[i + 1];
			const pair = (c: Chord): [number, number] => [pitchClass(c.tones[1]), pitchClass(c.tones[3])];
			const pairNotes = (c: Chord): Note[] => [c.tones[1], c.tones[3]];
			const toNames = [noteName(to.tones[1]), noteName(to.tones[3])];
			// Roots fall a fifth, so the 3rd is held as the next 7th while the 7th
			// falls to the next 3rd — the mechanism the whole drill exists to teach.
			return {
				id: spec.id,
				type: spec.type,
				title: `${from.symbol} → ${to.symbol}`,
				instruction: `The lit keys are ${from.symbol}'s guide tones. Tap ${to.symbol}'s — one holds, one moves.`,
				input: 'keys',
				given: pair(from),
				steps: [
					{
						position: spec.transition,
						symbol: to.symbol,
						answerLabel: `guide tones of ${to.symbol}`,
						expected: pair(to),
						names: toNames
					}
				],
				answerText: toNames.join(' – '),
				rationale: `${from.symbol}'s 3rd (${noteName(from.tones[1])}) is held as ${to.symbol}'s 7th, while its 7th (${noteName(from.tones[3])}) falls to ${to.symbol}'s 3rd (${noteName(to.tones[1])}).`,
				topic: spec.mode === 'minor' ? 'minor-two-five' : 'guide-tones',
				rootPitchClass: pitchClass(parseNote(spec.key, ROOT_OCTAVE)),
				timeTarget,
				// Guide-tone pairs have no root to stand on, so the second pair may be
				// inverted as well as re-registered — which is what puts the held tone
				// on the same key twice instead of an octave apart.
				sound: voiceLed([pairNotes(from), pairNotes(to)], { invertible: true })
			};
		}

		case 'rlc': {
			const chain = buildChain(spec.key, 'major');
			const i = spec.transition === 'ii-V' ? 0 : 1;
			const from = chain.chords[i];
			const to = chain.chords[i + 1];
			const toForm: RootlessForm = spec.form === 'A' ? 'B' : 'A';
			const fromVoicing = buildRootless(from.root, from.quality as RootlessQuality, spec.form);
			const toVoicing = buildRootless(to.root, to.quality as RootlessQuality, toForm);
			return {
				id: spec.id,
				type: spec.type,
				title: `${from.symbol} → ${to.symbol}`,
				instruction: `${from.symbol} is in the ${spec.form} form. Tap ${to.symbol}'s ${toForm} form, bottom-up.`,
				input: 'keys',
				given: [...fromVoicing.pitchClasses],
				steps: [
					{
						position: spec.transition,
						symbol: toVoicing.symbol,
						answerLabel: `${toForm} form of ${toVoicing.symbol}`,
						expected: [...toVoicing.pitchClasses],
						ordered: true,
						names: [...toVoicing.names]
					}
				],
				answerText: `${toVoicing.names.join(' – ')}  (${toVoicing.stackLabel})`,
				rationale: `Roots fall a fifth, so alternating forms — ${spec.form} to ${toForm} — keeps every voice within a step of where it was.`,
				topic: 'rootless',
				rootPitchClass: pitchClass(parseNote(spec.key, ROOT_OCTAVE)),
				timeTarget,
				// Both voicings, like gtc: the A↔B alternation and how little
				// each voice moves is the card, and one chord alone shows neither.
				sound: voiceLed([[...fromVoicing.notes], [...toVoicing.notes]])
			};
		}

		case 'ext': {
			const rootNote = parseNote(spec.root, ROOT_OCTAVE);
			const note = simplifyIfExtreme(
				transpose(rootNote, INTERVALS[spec.interval]),
				prefersFlats(rootNote)
			);
			const label = extensionLabel(spec.quality, spec.interval);
			const chord = buildChord(spec.root, spec.quality);
			const symbol = chord.symbol;
			return {
				id: spec.id,
				type: spec.type,
				title: symbol,
				instruction: `Tap the ${label}`,
				input: 'keys',
				given: [],
				steps: [
					{
						position: label,
						symbol,
						answerLabel: `the ${label} of ${symbol}`,
						expected: [pitchClass(note)],
						names: [noteName(note)]
					}
				],
				answerText: noteName(note),
				rationale: `The ${label} of ${symbol} is ${noteName(note)} — ${INTERVAL_LABEL[spec.interval]} above ${prettyNoteName(spec.root)}.`,
				topic: 'extensions',
				rootPitchClass: pitchClass(rootNote),
				timeTarget,
				// An extension is a colour, and a colour needs something to colour:
				// the chord first, then the note over it. On its own it is just a pitch,
				// and the ♭9 that should sting sounds like any other note.
				sound: sound(extensionBed(chord), [note])
			};
		}

		case 'dia': {
			const degree = degreeFor(spec.numeral);
			const root = diatonicRoot(spec.key, degree);
			const chord = buildChord(noteName(root), degree.quality);
			const symbol = chord.symbol;
			return {
				id: spec.id,
				type: spec.type,
				title: `${prettyNoteName(spec.key)} major`,
				instruction: `Which chord is the ${degree.numeral}?`,
				input: 'chord-name',
				given: [],
				steps: [],
				expectedChord: {
					root: noteName(root),
					rootPc: pitchClass(root),
					quality: degree.quality
				},
				answerText: symbol,
				rationale: `The ${degree.numeral} of ${prettyNoteName(spec.key)} is ${symbol} — every major key runs ${DIATONIC.map((d) => d.numeral).join(' ')} as maj7 m7 m7 maj7 7 m7 m7♭5.`,
				topic: 'diatonic',
				rootPitchClass: pitchClass(parseNote(spec.key, ROOT_OCTAVE)),
				timeTarget,
				sound: sound([...chord.tones])
			};
		}

		case 'ivl': {
			const rootNote = parseNote(spec.root, ROOT_OCTAVE);
			const note = simplifyIfExtreme(
				transpose(rootNote, INTERVALS[spec.interval]),
				prefersFlats(rootNote)
			);
			return {
				id: spec.id,
				type: spec.type,
				title: prettyNoteName(spec.root),
				instruction: `Tap a ${INTERVAL_LABEL[spec.interval]} above it`,
				input: 'keys',
				given: [pitchClass(rootNote)],
				rootGiven: pitchClass(rootNote),
				steps: [
					{
						position: '',
						symbol: prettyNoteName(spec.root),
						answerLabel: `${INTERVAL_LABEL[spec.interval]} above ${prettyNoteName(spec.root)}`,
						expected: [pitchClass(note)],
						names: [noteName(note)]
					}
				],
				answerText: noteName(note),
				rationale: `A ${INTERVAL_LABEL[spec.interval]} above ${prettyNoteName(spec.root)} is ${noteName(note)} (${INTERVALS[spec.interval].semitones} semitone${INTERVALS[spec.interval].semitones === 1 ? '' : 's'}).`,
				topic: 'spelling',
				rootPitchClass: pitchClass(rootNote),
				timeTarget,
				sound: sound([rootNote], [note])
			};
		}

		case 'mode': {
			const degree = degreeFor(spec.numeral);
			const root = diatonicRoot(spec.key, degree);
			const chord = buildChord(noteName(root), degree.quality);
			const symbol = chord.symbol;
			return {
				id: spec.id,
				type: spec.type,
				title: `${symbol} in ${prettyNoteName(spec.key)} major`,
				instruction: 'Which mode do you play over it?',
				input: 'mode-name',
				given: [],
				steps: [],
				expectedMode: degree.mode,
				topic: 'modes',
				answerText: `${degree.mode} — the ${prettyNoteName(spec.key)} major scale from ${noteName(root)}`,
				rationale: `${symbol} is the ${degree.numeral} of ${prettyNoteName(spec.key)}, so it takes ${degree.mode}: ${degree.modeHint}.`,
				rootPitchClass: pitchClass(parseNote(spec.key, ROOT_OCTAVE)),
				timeTarget,
				sound: sound([...chord.tones])
			};
		}

		case 'eint': {
			const rootNote = parseNote(spec.root, ROOT_OCTAVE);
			const note = simplifyIfExtreme(
				transpose(rootNote, INTERVALS[spec.interval]),
				prefersFlats(rootNote)
			);
			const semitones = INTERVALS[spec.interval].semitones;
			return {
				id: spec.id,
				type: spec.type,
				title: 'Listen',
				instruction: 'Two notes, low to high — which interval is it?',
				input: 'interval-name',
				promptIsSound: true,
				given: [],
				steps: [],
				expectedInterval: spec.interval,
				answerText: `${INTERVAL_LABEL[spec.interval]} — ${noteName(rootNote)} up to ${noteName(note)}`,
				// Short on purpose: an ear card's feedback competes for screen space
				// with an eleven-button picker. The full "why no root" argument lives
				// in the ear reference topic, one tap away.
				rationale: `${semitones} semitone${semitones === 1 ? '' : 's'}. The starting note changes every time — the interval is the distance, not the pair.`,
				topic: 'ear',
				rootPitchClass: pitchClass(rootNote),
				timeTarget,
				// Melodically, ascending, root first — the same shape the ivl card
				// plays on reveal, so the two drills reinforce one another.
				sound: sound([rootNote], [note])
			};
		}

		case 'eqal': {
			const chord = buildChord(spec.root, spec.quality);
			const third = chord.tones[1];
			const seventh = chord.tones[3];
			return {
				id: spec.id,
				type: spec.type,
				title: 'Listen',
				instruction: 'One chord, all four notes — which quality is it?',
				input: 'quality-name',
				promptIsSound: true,
				given: [],
				steps: [],
				// No alsoAccept: four notes do pin the quality down. The other cards
				// on this picker show two notes, which never can.
				expectedChord: {
					root: spec.root,
					rootPc: pitchClass(chord.tones[0]),
					quality: spec.quality
				},
				answerText: `${QUALITY_LABEL[spec.quality]} — ${chord.symbol}: ${chord.tones.map(noteName).join(' – ')}`,
				rationale: `The 3rd (${noteName(third)}) says minor or major and the 7th (${noteName(seventh)}) says how far it leans; the 5th only speaks up when it is flat, as in m7♭5 and °7.`,
				topic: 'ear',
				rootPitchClass: pitchClass(chord.tones[0]),
				timeTarget,
				sound: sound([...chord.tones])
			};
		}
	}
}

function degreeFor(numeral: string): DiatonicDegree {
	const degree = DIATONIC.find((d) => d.numeral === numeral);
	if (!degree) throw new Error(`Unknown scale degree: ${numeral}`);
	return degree;
}

/** Parse a stored card id back into its spec. */
export function parseCardId(id: string): CardSpec | null {
	const parts = id.split(':');
	switch (parts[0]) {
		case 'chain': {
			if (parts.length === 2) return { id, type: 'chain', key: unslug(parts[1]), mode: 'major' };
			if (parts.length === 3 && parts[2] === 'minor')
				return { id, type: 'chain', key: unslug(parts[1]), mode: 'minor' };
			return null;
		}
		case 'gt': {
			if (parts.length !== 3) return null;
			return { id, type: 'gt', root: unslug(parts[1]), quality: parts[2] as Quality };
		}
		case 'gtn': {
			if (parts.length !== 3) return null;
			return { id, type: 'gtn', root: unslug(parts[1]), quality: parts[2] as GtClass };
		}
		case 'gtc': {
			if (parts.length === 3 || (parts.length === 4 && parts[3] === 'minor')) {
				return {
					id,
					type: 'gtc',
					key: unslug(parts[1]),
					transition: parts[2] as Transition,
					mode: parts.length === 4 ? 'minor' : 'major'
				};
			}
			return null;
		}
		case 'rlc': {
			if (parts.length !== 4) return null;
			return {
				id,
				type: 'rlc',
				key: unslug(parts[1]),
				transition: parts[2] as Transition,
				form: parts[3] as RootlessForm
			};
		}
		case 'rootless': {
			if (parts.length !== 4) return null;
			return {
				id,
				type: 'rootless',
				root: unslug(parts[1]),
				quality: parts[2] as RootlessQuality,
				form: parts[3] as RootlessForm
			};
		}
		case 'ext': {
			if (parts.length !== 4) return null;
			return {
				id,
				type: 'ext',
				root: unslug(parts[1]),
				quality: parts[2] as Quality,
				interval: parts[3] as IntervalName
			};
		}
		case 'dia': {
			if (parts.length !== 3) return null;
			return { id, type: 'dia', key: unslug(parts[1]), numeral: parts[2] };
		}
		case 'ivl': {
			if (parts.length !== 3) return null;
			return { id, type: 'ivl', root: unslug(parts[1]), interval: parts[2] as IntervalName };
		}
		case 'mode': {
			if (parts.length !== 3) return null;
			return { id, type: 'mode', key: unslug(parts[1]), numeral: parts[2] };
		}
		case 'eint': {
			if (parts.length !== 3) return null;
			return { id, type: 'eint', root: unslug(parts[1]), interval: parts[2] as IntervalName };
		}
		case 'eqal': {
			if (parts.length !== 3) return null;
			return { id, type: 'eqal', root: unslug(parts[1]), quality: parts[2] as Quality };
		}
		default:
			return null;
	}
}

