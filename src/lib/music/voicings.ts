/**
 * Chord qualities, shell voicings and ii-V-I guide-tone chains.
 */

import {
	INTERVALS,
	midi,
	noteName,
	parseNote,
	pitchClass,
	prefersFlats,
	prettyNoteName,
	simplifyIfExtreme,
	transpose,
	type Interval,
	type Note
} from './theory';

export type Quality = 'maj7' | 'm7' | '7' | 'm7b5' | 'dim7' | 'mMaj7';
export type ShellType = 'r3' | 'r7';
export type ChainVariant = '737' | '373';
export type ChainPosition = 'ii' | 'iiø' | 'V' | 'I' | 'i';
/** Major ii–V–I or minor iiø–V–i. */
export type ChainMode = 'major' | 'minor';

export const QUALITIES: Quality[] = ['maj7', 'm7', '7', 'm7b5', 'dim7', 'mMaj7'];
export const SHELL_TYPES: ShellType[] = ['r3', 'r7'];
export const CHAIN_MODES: ChainMode[] = ['major', 'minor'];

/**
 * The twelve chord roots. F# rather than Gb: F#m7, F#7 and F#m7b5 are how these
 * chords are actually written on lead sheets. Major key centres use Gb instead
 * — see {@link KEY_CENTERS}.
 */
export const CHORD_ROOTS = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];

/** The twelve major key centres, spelled the way jazz charts spell them. */
export const KEY_CENTERS = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];

/**
 * Pitch classes in circle-of-fourths order (C F B♭ E♭ …). Jazz practice moves
 * in fourths, so this is the order new roots are introduced in — chromatic
 * order would pair C with D♭, two keys that share nothing.
 */
export const FOURTHS_ORDER = [0, 5, 10, 3, 8, 1, 6, 11, 4, 9, 2, 7];

/**
 * The twelve minor key centres. Not the same list as the major one: minor
 * leans sharp (C# minor, not D♭ minor, whose ii would need a double flat), but
 * A♭ minor is used rather than G♯ minor because G♯ minor's V and i both need a
 * double sharp and nobody wants to read F𝄪 on a drill card.
 */
export const MINOR_KEY_CENTERS = [
	'C',
	'C#',
	'D',
	'Eb',
	'E',
	'F',
	'F#',
	'G',
	'Ab',
	'A',
	'Bb',
	'B'
];

/** Roots and key centres live in octave 3 — a left hand shell sits under middle C. */
export const ROOT_OCTAVE = 3;

const CHORD_INTERVALS: Record<Quality, [Interval, Interval, Interval, Interval]> = {
	maj7: [INTERVALS.P1, INTERVALS.M3, INTERVALS.P5, INTERVALS.M7],
	m7: [INTERVALS.P1, INTERVALS.m3, INTERVALS.P5, INTERVALS.m7],
	'7': [INTERVALS.P1, INTERVALS.M3, INTERVALS.P5, INTERVALS.m7],
	m7b5: [INTERVALS.P1, INTERVALS.m3, INTERVALS.d5, INTERVALS.m7],
	dim7: [INTERVALS.P1, INTERVALS.m3, INTERVALS.d5, INTERVALS.d7],
	// The minor tonic in a minor ii–V–i. m6 would be the other common choice,
	// but it has no 7th at all, so it cannot carry a root-7 shell.
	mMaj7: [INTERVALS.P1, INTERVALS.m3, INTERVALS.P5, INTERVALS.M7]
};

export const QUALITY_SUFFIX: Record<Quality, string> = {
	maj7: 'maj7',
	m7: 'm7',
	'7': '7',
	m7b5: 'm7♭5',
	dim7: '°7',
	mMaj7: 'm(maj7)'
};

export const QUALITY_LABEL: Record<Quality, string> = {
	maj7: 'major 7',
	m7: 'minor 7',
	'7': 'dominant 7',
	m7b5: 'half-diminished',
	dim7: 'diminished 7',
	mMaj7: 'minor–major 7'
};

export const SHELL_LABEL: Record<ShellType, string> = {
	r3: 'root–3',
	r7: 'root–7'
};

/**
 * The five intervals a shell's guide tone can form with its root.
 *
 * Note→symbol cards are keyed on these rather than on a chord quality, because
 * two notes do not determine a chord: Dm7 and Dm7♭5 share their third, and 7
 * and m7 share their seventh. The interval is the most that can honestly be
 * asked, and it is the thing the ear and hand actually need.
 */
export type GuideInterval = 'M3' | 'm3' | 'M7' | 'm7' | 'd7';

export const GUIDE_INTERVALS: GuideInterval[] = ['m3', 'M3', 'm7', 'M7', 'd7'];

export const GUIDE_INTERVAL_LABEL: Record<GuideInterval, string> = {
	M3: 'major 3rd',
	m3: 'minor 3rd',
	M7: 'major 7th',
	m7: 'minor 7th',
	d7: 'dim 7th'
};

/** The chord degree a guide interval is, as written in chord-tone shorthand. */
export const GUIDE_INTERVAL_DEGREE: Record<GuideInterval, string> = {
	M3: '3',
	m3: '♭3',
	M7: '7',
	m7: '♭7',
	d7: '♭♭7'
};

/** Which shell type an interval belongs to. */
export const GUIDE_INTERVAL_SHELL: Record<GuideInterval, ShellType> = {
	M3: 'r3',
	m3: 'r3',
	M7: 'r7',
	m7: 'r7',
	d7: 'r7'
};

/** The chord qualities a given root-plus-interval shell is consistent with. */
export const GUIDE_INTERVAL_QUALITIES: Record<GuideInterval, Quality[]> = {
	M3: ['maj7', '7'],
	m3: ['m7', 'm7b5', 'dim7', 'mMaj7'],
	M7: ['maj7', 'mMaj7'],
	m7: ['m7', '7', 'm7b5'],
	d7: ['dim7']
};

export function guideNote(root: string, interval: GuideInterval, octave = ROOT_OCTAVE): Note {
	const rootNote = parseNote(root, octave);
	return simplifyIfExtreme(transpose(rootNote, INTERVALS[interval]), prefersFlats(rootNote));
}

export interface Chord {
	root: string;
	quality: Quality;
	symbol: string;
	/** root, third, fifth, seventh */
	tones: [Note, Note, Note, Note];
}

export interface Shell {
	chord: Chord;
	shellType: ShellType;
	/** [root, guide tone], in ascending order and correctly octaved */
	notes: [Note, Note];
	/** The guide tone alone — the note that carries the voice leading */
	guide: Note;
	/** Pitch classes of the two notes, in ascending played order */
	pitchClasses: [number, number];
	names: [string, string];
}

export function chordSymbol(root: string, quality: Quality): string {
	// Roots arrive ASCII from card specs; symbols are display strings, so the
	// accidental is rendered as a glyph to match noteName() and the suffixes.
	return prettyNoteName(root) + QUALITY_SUFFIX[quality];
}

export function buildChord(root: string, quality: Quality, octave = ROOT_OCTAVE): Chord {
	const rootNote = parseNote(root, octave);
	const flats = prefersFlats(rootNote);
	const tones = CHORD_INTERVALS[quality].map((iv) =>
		simplifyIfExtreme(transpose(rootNote, iv), flats)
	) as [Note, Note, Note, Note];
	return { root, quality, symbol: chordSymbol(root, quality), tones };
}

export function buildShell(root: string, quality: Quality, shellType: ShellType): Shell {
	const chord = buildChord(root, quality);
	const guide = shellType === 'r3' ? chord.tones[1] : chord.tones[3];
	const notes: [Note, Note] = [chord.tones[0], guide];
	return {
		chord,
		shellType,
		notes,
		guide,
		pitchClasses: [pitchClass(notes[0]), pitchClass(notes[1])],
		names: [noteName(notes[0]), noteName(notes[1])]
	};
}

/**
 * The chord root of a pitch class, ASCII, as lead sheets spell it.
 *
 * Interval arithmetic off a chord tone can land on B♯ or F𝄪 — correct spelling
 * for the note, nonsense as a chord root. Renaming through CHORD_ROOTS is what
 * keeps a derived root in the same twelve names the deck is built from.
 */
export function chordRootName(pc: number): string {
	const wrapped = ((pc % 12) + 12) % 12;
	return CHORD_ROOTS.find((r) => pitchClass(parseNote(r, 4)) === wrapped) ?? String(wrapped);
}

/** Display label for a pitch class, using the enharmonic pair where relevant. */
export function keyLabel(pc: number): string {
	const pairs: Record<number, string> = { 6: 'F♯/G♭' };
	return pairs[pc] ?? prettyNoteName(chordRootName(pc));
}

/** Which chord member the guide tone is, for feedback copy. */
export function guideDegree(shellType: ShellType): '3rd' | '7th' {
	return shellType === 'r3' ? '3rd' : '7th';
}

// ---------------------------------------------------------------------------
// Rootless A/B voicings
// ---------------------------------------------------------------------------

export type RootlessForm = 'A' | 'B';
export const ROOTLESS_FORMS: RootlessForm[] = ['A', 'B'];

/** Rootless voicings only exist for the qualities that actually take them. */
export type RootlessQuality = 'maj7' | 'm7' | '7' | 'm7b5';
export const ROOTLESS_QUALITIES: RootlessQuality[] = ['maj7', 'm7', '7', 'm7b5'];

/**
 * The A form, bottom-up. The B form is this rotated by two — the same four
 * notes with the top pair moved underneath — which is what makes A and B
 * indistinguishable by pitch-class set and distinguishable only by voice order.
 *
 * The dominant stacks 3-13-7-9 rather than 3-5-7-9: on a V chord the 5th is
 * dead weight and the 13th is what everyone actually plays.
 */
const ROOTLESS_A_STACK: Record<RootlessQuality, [Interval, Interval, Interval, Interval]> = {
	maj7: [INTERVALS.M3, INTERVALS.P5, INTERVALS.M7, INTERVALS.M9],
	m7: [INTERVALS.m3, INTERVALS.P5, INTERVALS.m7, INTERVALS.M9],
	'7': [INTERVALS.M3, INTERVALS.M13, INTERVALS.m7, INTERVALS.M9],
	// Half-diminished replaces the 9 with the root: the ♭9 a minor 9th above the
	// bass is the classic avoid tension on this chord, so the textbook form is
	// ♭3–♭5–♭7–1 (DeGreg, Levine), not a ♭9 drilled into the hand in twelve keys.
	m7b5: [INTERVALS.m3, INTERVALS.d5, INTERVALS.m7, INTERVALS.P8]
};

export const ROOTLESS_STACK_LABEL: Record<RootlessQuality, [string, string]> = {
	maj7: ['3–5–7–9', '7–9–3–5'],
	m7: ['♭3–5–♭7–9', '♭7–9–♭3–5'],
	'7': ['3–13–♭7–9', '♭7–9–3–13'],
	m7b5: ['♭3–♭5–♭7–1', '♭7–1–♭3–♭5']
};

export interface Rootless {
	root: string;
	quality: RootlessQuality;
	form: RootlessForm;
	symbol: string;
	/** The four notes bottom-up, in voice order. */
	notes: [Note, Note, Note, Note];
	/** Pitch classes in the same voice order — the sequence the answer must match. */
	pitchClasses: number[];
	names: string[];
	/** e.g. "3–5–7–9" */
	stackLabel: string;
}

export function buildRootless(
	root: string,
	quality: RootlessQuality,
	form: RootlessForm
): Rootless {
	const rootNote = parseNote(root, ROOT_OCTAVE);
	const flats = prefersFlats(rootNote);
	const stack = ROOTLESS_A_STACK[quality];
	// B form is the A form rotated by two voices.
	const ordered = form === 'A' ? stack : [stack[2], stack[3], stack[0], stack[1]];

	let previous: Note | null = null;
	const notes = ordered.map((iv) => {
		let note = simplifyIfExtreme(transpose(rootNote, iv), flats);
		// Keep the voicing ascending: drop any voice that landed below the one
		// beneath it by an octave, so the notes read as a playable stack.
		while (previous && midi(note) <= midi(previous)) {
			note = { ...note, octave: note.octave + 1 };
		}
		while (previous && midi(note) - midi(previous) > 12) {
			note = { ...note, octave: note.octave - 1 };
		}
		previous = note;
		return note;
	}) as [Note, Note, Note, Note];

	const placed = intoTaughtRegister(notes);

	return {
		root,
		quality,
		form,
		symbol: chordSymbol(root, quality),
		notes: placed,
		pitchClasses: placed.map(pitchClass),
		names: placed.map(noteName),
		stackLabel: ROOTLESS_STACK_LABEL[quality][form === 'A' ? 0 : 1]
	};
}

/** The window the reference topic teaches: below C3 four notes turn to mud. */
const ROOTLESS_LOW = midi(parseNote('C', 3));
const ROOTLESS_HIGH = midi(parseNote('C', 5));

/**
 * Octave-shift the whole stack into C3–C5.
 *
 * Every voice is transposed up from a root pinned at ROOT_OCTAVE, so a B form —
 * which starts on the ♭7 — lands most of a 7th above its own A form, and the
 * offset compounds with the root: B7's B form used to top out at A♭5, a fourth
 * above the register the app's own reference sheet tells the learner to stay in.
 *
 * The shift is applied to the stack as a unit. Voice ORDER is the graded answer
 * for A against B, and the two forms share a pitch-class set, so moving a single
 * voice would change what the card is asking.
 */
function intoTaughtRegister(notes: [Note, Note, Note, Note]): [Note, Note, Note, Note] {
	const low = midi(notes[0]);
	const high = midi(notes[notes.length - 1]);
	let shift = 0;
	while (high + shift > ROOTLESS_HIGH && low + shift - 12 >= ROOTLESS_LOW) shift -= 12;
	while (low + shift < ROOTLESS_LOW && high + shift + 12 <= ROOTLESS_HIGH) shift += 12;
	if (shift === 0) return notes;
	const octaves = shift / 12;
	return notes.map((n) => ({ ...n, octave: n.octave + octaves })) as [Note, Note, Note, Note];
}

// ---------------------------------------------------------------------------
// ii-V-I guide-tone chains
// ---------------------------------------------------------------------------

const M2: Interval = { degree: 2, semitones: 2 };
const P5: Interval = INTERVALS.P5;

/** The shell type used at each position, per chain variant. */
const CHAIN_SHELLS: Record<ChainVariant, [ShellType, ShellType, ShellType]> = {
	// 7th of ii falls to the 3rd of V, which is held as the 7th of I
	'737': ['r7', 'r3', 'r7'],
	// 3rd of ii is held as the 7th of V, which falls to the 3rd of I
	'373': ['r3', 'r7', 'r3']
};

export interface Chain {
	key: string;
	variant: ChainVariant;
	mode: ChainMode;
	shells: [Shell, Shell, Shell];
	positions: [ChainPosition, ChainPosition, ChainPosition];
}

/**
 * The qualities at each position.
 *
 * Minor takes the ii from the natural minor (half-diminished) and the V from
 * the harmonic minor (dominant, so it has a leading tone), which is what makes
 * a minor ii–V–i resolve. The tonic is m(maj7); m6 is the other common choice
 * but has no seventh for a shell to use.
 */
export const CHAIN_QUALITIES: Record<ChainMode, [Quality, Quality, Quality]> = {
	major: ['m7', '7', 'maj7'],
	minor: ['m7b5', '7', 'mMaj7']
};

/** ii is a major 2nd above the tonic in major, and in minor too. */
const CHAIN_ROOT_INTERVALS: [Interval, Interval] = [M2, INTERVALS.P5];

export const CHAIN_MODE_LABEL: Record<ChainMode, string> = {
	major: 'ii–V–I',
	minor: 'iiø–V–i'
};

export function buildChain(
	key: string,
	variant: ChainVariant,
	mode: ChainMode = 'major'
): Chain {
	const tonic = parseNote(key, ROOT_OCTAVE);
	const flats = prefersFlats(tonic);
	const [ivSuper, ivDom] = CHAIN_ROOT_INTERVALS;
	const supertonic = simplifyIfExtreme(transpose(tonic, ivSuper), flats);
	const dominant = simplifyIfExtreme(transpose(tonic, ivDom), flats);

	const [s1, s2, s3] = CHAIN_SHELLS[variant];
	const [q1, q2, q3] = CHAIN_QUALITIES[mode];
	return {
		key,
		variant,
		mode,
		// Display-only (never part of a card id), so the minor spelling is safe.
		positions: mode === 'minor' ? ['iiø', 'V', 'i'] : ['ii', 'V', 'I'],
		shells: [
			buildShell(noteName(supertonic), q1, s1),
			buildShell(noteName(dominant), q2, s2),
			buildShell(key, q3, s3)
		]
	};
}

export type Transition = 'ii-V' | 'V-I';

export interface TransitionInfo {
	from: Shell;
	to: Shell;
	/** True when the guide tone is the same pitch and simply holds over. */
	held: boolean;
	/** Semitone movement of the guide tone (0 when held). */
	semitones: number;
	/** One-line explanation shown as immediate feedback. */
	rationale: string;
}

export function describeTransition(chain: Chain, transition: Transition): TransitionInfo {
	const i = transition === 'ii-V' ? 0 : 1;
	const from = chain.shells[i];
	const to = chain.shells[i + 1];
	// Each chord is built over its own root in octave 3, so raw MIDI distance
	// would report register jumps. Guide-tone motion is a pitch-class move:
	// fold it into [-6, 6] and it reads as the semitone step it actually is.
	const raw = (((pitchClass(to.guide) - pitchClass(from.guide)) % 12) + 12) % 12;
	const semitones = raw > 6 ? raw - 12 : raw;
	const held = semitones === 0;
	const fromDeg = guideDegree(from.shellType);
	const toDeg = guideDegree(to.shellType);

	// Minor chains move by a whole tone in places where major moves by a
	// semitone, so the wording is derived rather than assumed — and named the
	// way the reference names it, not counted in raw semitones.
	const abs = Math.abs(semitones);
	const step = abs === 1 ? 'a semitone' : abs === 2 ? 'a whole tone' : `${abs} semitones`;
	const direction = semitones < 0 ? 'falls' : 'rises';

	const rationale = held
		? `The ${fromDeg} of ${from.chord.symbol} (${from.names[1]}) is held as the ${toDeg} of ${to.chord.symbol} — only the root moves.`
		: `The ${fromDeg} of ${from.chord.symbol} (${from.names[1]}) ${direction} ${step} to the ${toDeg} of ${to.chord.symbol} (${to.names[1]}).`;

	return { from, to, held, semitones, rationale };
}
