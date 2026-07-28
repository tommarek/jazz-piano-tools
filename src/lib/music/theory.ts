/**
 * Diatonic note spelling and interval arithmetic.
 *
 * Notes are stored as (letter, alter, octave) rather than as bare pitch classes
 * so that Db and C# stay distinct — that distinction is the whole point of a
 * chord-spelling drill, and collapsing it early is where this kind of app
 * usually goes wrong.
 *
 * Octave numbering is scientific pitch: middle C is C4 = MIDI 60.
 */

export const LETTERS = ['C', 'D', 'E', 'F', 'G', 'A', 'B'] as const;
export type LetterName = (typeof LETTERS)[number];

/** Semitones above C for each natural letter. */
const LETTER_SEMITONES = [0, 2, 4, 5, 7, 9, 11];

export interface Note {
	/** 0..6, indexing LETTERS */
	letter: number;
	/** -2 = double flat, -1 = flat, 0 = natural, 1 = sharp, 2 = double sharp */
	alter: number;
	/** Scientific pitch octave; C4 = middle C */
	octave: number;
}

/** A diatonic interval: a letter distance plus an exact semitone distance. */
export interface Interval {
	/** 1 = unison, 3 = some kind of third, 7 = some kind of seventh */
	degree: number;
	semitones: number;
}

export const INTERVALS = {
	P1: { degree: 1, semitones: 0 },
	m2: { degree: 2, semitones: 1 },
	M2: { degree: 2, semitones: 2 },
	m3: { degree: 3, semitones: 3 },
	M3: { degree: 3, semitones: 4 },
	P4: { degree: 4, semitones: 5 },
	d5: { degree: 5, semitones: 6 },
	P5: { degree: 5, semitones: 7 },
	m6: { degree: 6, semitones: 8 },
	M6: { degree: 6, semitones: 9 },
	d7: { degree: 7, semitones: 9 },
	m7: { degree: 7, semitones: 10 },
	M7: { degree: 7, semitones: 11 },
	P8: { degree: 8, semitones: 12 },
	// Compound intervals. The degree keeps spelling honest: the ♯9 of C is D♯,
	// not E♭, even though they sound the same.
	m9: { degree: 9, semitones: 13 },
	M9: { degree: 9, semitones: 14 },
	A9: { degree: 9, semitones: 15 },
	P11: { degree: 11, semitones: 17 },
	A11: { degree: 11, semitones: 18 },
	m13: { degree: 13, semitones: 20 },
	M13: { degree: 13, semitones: 21 }
} as const satisfies Record<string, Interval>;

export type IntervalName = keyof typeof INTERVALS;

/** Names used when an interval is the thing being asked about. */
export const INTERVAL_LABEL: Record<IntervalName, string> = {
	P1: 'unison',
	m2: 'minor 2nd',
	M2: 'major 2nd',
	m3: 'minor 3rd',
	M3: 'major 3rd',
	P4: 'perfect 4th',
	// Not "tritone": the drilled answer is always the diminished-5th spelling
	// (Gb above C, not F#), and only this name makes that spelling the right one.
	d5: 'diminished 5th',
	P5: 'perfect 5th',
	m6: 'minor 6th',
	M6: 'major 6th',
	d7: 'diminished 7th',
	m7: 'minor 7th',
	M7: 'major 7th',
	P8: 'octave',
	m9: 'flat 9th',
	M9: '9th',
	A9: 'sharp 9th',
	P11: '11th',
	A11: 'sharp 11th',
	m13: 'flat 13th',
	M13: '13th'
};

/**
 * Accidentals as the user reads them. ASCII 'b'/'#' remain valid *input* (card
 * ids and CHORD_ROOTS stay ASCII so stored ids never change), but everything
 * rendered goes through these glyphs — one notation on every surface.
 */
const ACCIDENTALS: Record<number, string> = {
	[-3]: '♭♭♭',
	[-2]: '♭♭',
	[-1]: '♭',
	0: '',
	1: '♯',
	2: '♯♯',
	3: '♯♯♯'
};

/** Map an ASCII-spelled note name ("Db", "F#") to display glyphs ("D♭", "F♯"). */
export function prettyNoteName(name: string): string {
	return name.replace(/b/g, '♭').replace(/#/g, '♯');
}

export function midi(n: Note): number {
	return (n.octave + 1) * 12 + LETTER_SEMITONES[n.letter] + n.alter;
}

/** Pitch class 0..11, C = 0. */
export function pitchClass(n: Note): number {
	return ((midi(n) % 12) + 12) % 12;
}

export function noteName(n: Note): string {
	const acc = ACCIDENTALS[n.alter];
	if (acc === undefined) throw new Error(`Unrenderable accidental: ${n.alter}`);
	return LETTERS[n.letter] + acc;
}

export function noteNameWithOctave(n: Note): string {
	return noteName(n) + n.octave;
}

export function notesEqual(a: Note, b: Note): boolean {
	return a.letter === b.letter && a.alter === b.alter && a.octave === b.octave;
}

/**
 * Parse a note name such as "Bb", "F#", "Cbb" into a Note at the given octave.
 */
export function parseNote(name: string, octave = 4): Note {
	// Accept both ASCII and glyph accidentals: noteName() emits glyphs, ids use ASCII.
	const ascii = name.replace(/♭/g, 'b').replace(/♯/g, '#');
	const m = /^([A-G])(b{1,3}|#{1,3})?$/.exec(ascii);
	if (!m) throw new Error(`Not a note name: ${name}`);
	const letter = LETTERS.indexOf(m[1] as LetterName);
	const accStr = m[2] ?? '';
	const alter = accStr.startsWith('b') ? -accStr.length : accStr.length;
	return { letter, alter, octave };
}

/**
 * Raise `root` by `iv`, keeping diatonic spelling: the letter moves by the
 * interval's degree and the accidental absorbs whatever is left over.
 *
 * This can produce triple flats (Dbdim7 wants a Cbb seventh); callers that need
 * something playable should run the result through {@link simplifyIfExtreme}.
 */
export function transpose(root: Note, iv: Interval): Note {
	const rawLetter = root.letter + (iv.degree - 1);
	const letter = ((rawLetter % 7) + 7) % 7;
	const octave = root.octave + Math.floor(rawLetter / 7);
	const naturalMidi = (octave + 1) * 12 + LETTER_SEMITONES[letter];
	const alter = midi(root) + iv.semitones - naturalMidi;
	return { letter, alter, octave };
}

/**
 * Respell a note that needs more than a double accidental as the simplest
 * enharmonic equivalent. `preferFlats` decides the tie between e.g. F# and Gb.
 */
export function simplifyIfExtreme(n: Note, preferFlats: boolean): Note {
	if (Math.abs(n.alter) <= 2) return n;
	return simplestSpelling(midi(n), preferFlats);
}

/**
 * The fewest-accidentals spelling of a MIDI number, breaking ties by
 * `preferFlats`. Only ever returns naturals, single sharps or single flats.
 */
export function simplestSpelling(midiNumber: number, preferFlats: boolean): Note {
	const octave = Math.floor(midiNumber / 12) - 1;
	const pc = ((midiNumber % 12) + 12) % 12;

	const candidates: Note[] = [];
	for (let letter = 0; letter < 7; letter++) {
		for (const alter of [0, preferFlats ? -1 : 1, preferFlats ? 1 : -1]) {
			// Try the candidate in this octave and the neighbours, because e.g.
			// Cb belongs to the octave above its MIDI number's nominal octave.
			for (const oct of [octave - 1, octave, octave + 1]) {
				const cand: Note = { letter, alter, octave: oct };
				if (midi(cand) === midiNumber) candidates.push(cand);
			}
		}
	}
	if (candidates.length === 0) throw new Error(`No simple spelling for MIDI ${midiNumber}`);
	candidates.sort((a, b) => Math.abs(a.alter) - Math.abs(b.alter));
	const best = candidates.filter((c) => Math.abs(c.alter) === Math.abs(candidates[0].alter));
	if (best.length === 1) return best[0];
	// Tie between a sharp and a flat spelling: honour the preference.
	return best.find((c) => (preferFlats ? c.alter < 0 : c.alter > 0)) ?? best[0];
}

/** Flat-side roots spell their alterations with flats; sharp-side with sharps. */
export function prefersFlats(root: Note): boolean {
	if (root.alter < 0) return true;
	if (root.alter > 0) return false;
	// Naturals: F is the one flat-side natural root in common jazz usage.
	return LETTERS[root.letter] === 'F';
}
