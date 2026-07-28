import { describe, expect, it } from 'vitest';
import {
	INTERVALS,
	midi,
	noteName,
	parseNote,
	pitchClass,
	prefersFlats,
	prettyNoteName,
	simplestSpelling,
	simplifyIfExtreme,
	transpose
} from '../../src/lib/music/theory';

describe('note parsing and naming', () => {
	it('round-trips every accidental it can render, ASCII in and glyphs out', () => {
		for (const name of ['C', 'Cb', 'C#', 'Cbb', 'C##', 'Bb', 'F#', 'Abb']) {
			expect(noteName(parseNote(name, 4))).toBe(prettyNoteName(name));
			// Glyph names parse back to the same note.
			expect(noteName(parseNote(prettyNoteName(name), 4))).toBe(prettyNoteName(name));
		}
	});

	it('rejects things that are not note names', () => {
		expect(() => parseNote('H')).toThrow();
		expect(() => parseNote('Cx')).toThrow();
	});

	it('places middle C at MIDI 60', () => {
		expect(midi(parseNote('C', 4))).toBe(60);
		expect(midi(parseNote('A', 4))).toBe(69);
	});

	it('gives enharmonics the same pitch class and different names', () => {
		expect(pitchClass(parseNote('C♯', 4))).toBe(pitchClass(parseNote('D♭', 4)));
		expect(noteName(parseNote('C♯', 4))).not.toBe(noteName(parseNote('D♭', 4)));
	});

	it('crosses the octave boundary correctly', () => {
		// Cb4 sounds a semitone below C4, i.e. in the B3 register.
		expect(midi(parseNote('C♭', 4))).toBe(59);
		expect(midi(parseNote('B♯', 3))).toBe(60);
	});
});

describe('interval transposition keeps diatonic spelling', () => {
	it('spells a major third from every natural root', () => {
		const cases: [string, string][] = [
			['C', 'E'],
			['D', 'F♯'],
			['E', 'G♯'],
			['F', 'A'],
			['G', 'B'],
			['A', 'C♯'],
			['B', 'D♯']
		];
		for (const [root, third] of cases) {
			expect(noteName(transpose(parseNote(root, 4), INTERVALS.M3))).toBe(third);
		}
	});

	it('spells a minor seventh from flat roots without changing letter', () => {
		expect(noteName(transpose(parseNote('B♭', 3), INTERVALS.m7))).toBe('A♭');
		expect(noteName(transpose(parseNote('D♭', 3), INTERVALS.m7))).toBe('C♭');
	});

	it('produces a diminished fifth as a fifth, not a sharp fourth', () => {
		const d5 = transpose(parseNote('B', 3), INTERVALS.d5);
		expect(noteName(d5)).toBe('F');
		expect(pitchClass(d5)).toBe(5);
	});

	it('carries the octave when the letter wraps past B', () => {
		const seventh = transpose(parseNote('B', 3), INTERVALS.M7);
		expect(seventh.octave).toBe(4);
		expect(noteName(seventh)).toBe('A♯');
	});
});

describe('extreme accidentals are respelled', () => {
	it('leaves double accidentals alone', () => {
		const bb7 = transpose(parseNote('C', 3), INTERVALS.d7);
		expect(noteName(bb7)).toBe('B♭♭');
		expect(noteName(simplifyIfExtreme(bb7, true))).toBe('B♭♭');
	});

	it('respells a triple flat as its simplest enharmonic', () => {
		// A guard rather than a live path: no root in the catalogue reaches a
		// triple accidental (Dbdim7's seventh is Cbb, which is renderable). It
		// only fires if the root set ever grows to doubly-altered roots.
		const raw = transpose(parseNote('Fb', 3), INTERVALS.d7);
		expect(raw.alter).toBe(-3);
		const fixed = simplifyIfExtreme(raw, true);
		expect(noteName(fixed)).toBe('D♭');
		expect(midi(fixed)).toBe(midi(raw));
	});

	it('leaves the whole catalogue untouched, because nothing exceeds a double', () => {
		const dbDim7Seventh = transpose(parseNote('Db', 3), INTERVALS.d7);
		expect(noteName(dbDim7Seventh)).toBe('C♭♭');
		expect(noteName(simplifyIfExtreme(dbDim7Seventh, true))).toBe('C♭♭');
	});

	it('honours the flat/sharp preference when respelling', () => {
		expect(noteName(simplestSpelling(midi(parseNote('F♯', 4)), true))).toBe('G♭');
		expect(noteName(simplestSpelling(midi(parseNote('F♯', 4)), false))).toBe('F♯');
	});

	it('prefers a natural spelling over an accidental one', () => {
		expect(noteName(simplestSpelling(midi(parseNote('E', 4)), true))).toBe('E');
	});
});

describe('accidental preference by root', () => {
	it('uses flats for flat roots and F, sharps otherwise', () => {
		expect(prefersFlats(parseNote('B♭', 3))).toBe(true);
		expect(prefersFlats(parseNote('F', 3))).toBe(true);
		expect(prefersFlats(parseNote('F♯', 3))).toBe(false);
		expect(prefersFlats(parseNote('C', 3))).toBe(false);
	});
});
