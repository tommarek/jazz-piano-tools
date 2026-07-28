/**
 * Data for the four theory drills.
 *
 * These are the lookups that slow down comping — "what's the ♯9 of A7", "what's
 * the ii in D♭", "which mode over Bm7 in A". They are knowledge questions, not
 * voicing-production questions, so they get their own card types and their own
 * response-time targets.
 */

import { INTERVALS, transpose, simplifyIfExtreme, prefersFlats, parseNote } from './theory';
import type { IntervalName, Note } from './theory';
import { ROOT_OCTAVE, type Quality } from './voicings';

// ---------------------------------------------------------------------------
// Extensions and alterations
// ---------------------------------------------------------------------------

export interface Extension {
	/** How it is written on a chart. */
	label: string;
	interval: IntervalName;
}

/**
 * Which extensions are worth drilling on which quality.
 *
 * Deliberately not exhaustive: 3rds, 5ths and 7ths are covered by the shell
 * deck, and the alterations that people actually fumble live on the dominant.
 */
export const EXTENSIONS: Record<string, Extension[]> = {
	maj7: [
		{ label: '9', interval: 'M9' },
		{ label: '♯11', interval: 'A11' }
	],
	m7: [
		{ label: '9', interval: 'M9' },
		{ label: '11', interval: 'P11' }
	],
	'7': [
		{ label: '♭9', interval: 'm9' },
		{ label: '♯9', interval: 'A9' },
		{ label: '♯11', interval: 'A11' },
		{ label: '13', interval: 'M13' },
		{ label: '♭13', interval: 'm13' }
	],
	m7b5: [
		{ label: '11', interval: 'P11' },
		{ label: '♭13', interval: 'm13' }
	],
	mMaj7: [{ label: '9', interval: 'M9' }]
};

export const EXTENSION_QUALITIES = Object.keys(EXTENSIONS) as Quality[];

// ---------------------------------------------------------------------------
// Diatonic harmony
// ---------------------------------------------------------------------------

export interface DiatonicDegree {
	/** Roman numeral as written. */
	numeral: string;
	/** Interval of this degree's root above the tonic. */
	interval: IntervalName;
	quality: Quality;
	mode: string;
	/** Why this mode: the note that distinguishes it from the parallel major/minor. */
	modeHint: string;
}

/** The seven diatonic chords of a major key, with the mode played over each. */
export const DIATONIC: DiatonicDegree[] = [
	{
		numeral: 'I',
		interval: 'P1',
		quality: 'maj7',
		mode: 'Ionian',
		modeHint: 'the major scale itself'
	},
	{
		numeral: 'ii',
		interval: 'M2',
		quality: 'm7',
		mode: 'Dorian',
		modeHint: 'minor with a natural 6th'
	},
	{
		numeral: 'iii',
		interval: 'M3',
		quality: 'm7',
		mode: 'Phrygian',
		modeHint: 'minor with a ♭2'
	},
	{
		numeral: 'IV',
		interval: 'P4',
		quality: 'maj7',
		mode: 'Lydian',
		modeHint: 'major with a ♯4'
	},
	{
		numeral: 'V',
		interval: 'P5',
		quality: '7',
		mode: 'Mixolydian',
		modeHint: 'major with a ♭7'
	},
	{
		numeral: 'vi',
		interval: 'M6',
		quality: 'm7',
		mode: 'Aeolian',
		modeHint: 'the natural minor scale'
	},
	{
		numeral: 'vii',
		interval: 'M7',
		quality: 'm7b5',
		mode: 'Locrian',
		modeHint: 'minor with a ♭2 and a ♭5'
	}
];

export const MODE_NAMES = DIATONIC.map((d) => d.mode);

export function diatonicRoot(key: string, degree: DiatonicDegree): Note {
	const tonic = parseNote(key, ROOT_OCTAVE);
	return simplifyIfExtreme(transpose(tonic, INTERVALS[degree.interval]), prefersFlats(tonic));
}

// ---------------------------------------------------------------------------
// Intervals
// ---------------------------------------------------------------------------

/**
 * The intervals drilled on their own, ascending. Compound intervals are left to
 * the extensions drill, where they have a chord to hang on.
 */
export const DRILLED_INTERVALS: IntervalName[] = [
	// Difficulty order, not chromatic order: this is the order the scheduler
	// introduces them in. Consonant intervals first, then the quality-defining
	// 3rds, their 6th inversions, steps, the jazz-critical 7ths, and the
	// diminished 5th last — it needs the most spelling care.
	'P5',
	'P4',
	'm3',
	'M3',
	'm6',
	'M6',
	'm2',
	'M2',
	'm7',
	'M7',
	'd5'
];
