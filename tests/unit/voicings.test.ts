import { describe, expect, it } from 'vitest';
import { midi, noteName, parseNote, pitchClass, prettyNoteName } from '../../src/lib/music/theory';
import {
	CHORD_ROOTS,
	QUALITIES,
	ROOTLESS_FORMS,
	ROOTLESS_QUALITIES,
	SHELL_TYPES,
	buildChain,
	buildChord,
	buildRootless,
	buildShell,
	chordSymbol
} from '../../src/lib/music/voicings';

describe('golden file: every shell voicing', () => {
	/**
	 * Every chord in the deck rendered as text, with the root–3rd and root–7th
	 * pairs the guide-tone drills are built from. No card is a root shell any
	 * more; this is a spelling probe, and the drills get their own goldens.
	 * Reviewed by hand once; after that any diff here is a regression in note
	 * spelling, which is the failure mode this app cannot tolerate and cannot
	 * see at runtime.
	 */
	it('matches the reviewed snapshot', async () => {
		const lines: string[] = [];
		for (const root of CHORD_ROOTS) {
			for (const quality of QUALITIES) {
				const chord = buildChord(root, quality);
				const tones = chord.tones.map(noteName).join(' ');
				const shells = SHELL_TYPES.map((s) => {
					const shell = buildShell(root, quality, s);
					return `${s}=${shell.names.join('+')}`;
				}).join('  ');
				lines.push(`${chord.symbol.padEnd(9)} [${tones.padEnd(18)}] ${shells}`);
			}
		}
		await expect(lines.join('\n') + '\n').toMatchFileSnapshot('./__golden__/shells.txt');
	});

	it('matches the reviewed rootless snapshot', async () => {
		const lines: string[] = [];
		for (const root of CHORD_ROOTS) {
			for (const quality of ROOTLESS_QUALITIES) {
				const cells = ROOTLESS_FORMS.map((form) => {
					const v = buildRootless(root, quality, form);
					return `${form}=${v.names.join('+')}`;
				}).join('  ');
				lines.push(`${chordSymbol(root, quality).padEnd(9)} ${cells}`);
			}
		}
		await expect(lines.join('\n') + '\n').toMatchFileSnapshot('./__golden__/rootless.txt');
	});
});

describe('rootless voicings', () => {
	it('gives A and B the same notes in a different order', () => {
		for (const root of CHORD_ROOTS) {
			for (const quality of ROOTLESS_QUALITIES) {
				const a = buildRootless(root, quality, 'A');
				const b = buildRootless(root, quality, 'B');
				expect([...a.pitchClasses].sort()).toEqual([...b.pitchClasses].sort());
				// This is the whole reason the answer is graded as a sequence.
				expect(a.pitchClasses).not.toEqual(b.pitchClasses);
			}
		}
	});

	it('stacks four distinct notes strictly upward, inside two octaves', () => {
		for (const root of CHORD_ROOTS) {
			for (const quality of ROOTLESS_QUALITIES) {
				for (const form of ROOTLESS_FORMS) {
					const v = buildRootless(root, quality, form);
					expect(new Set(v.pitchClasses).size).toBe(4);
					const midis = v.notes.map(midi);
					for (let i = 1; i < midis.length; i++) {
						expect(midis[i]).toBeGreaterThan(midis[i - 1]);
						// No voice more than an octave above the one below it.
						expect(midis[i] - midis[i - 1]).toBeLessThanOrEqual(12);
					}
					expect(midis[3] - midis[0]).toBeLessThan(24);
				}
			}
		}
	});

	it('sits in the C3–C5 register the reference topic teaches', () => {
		// "Keep the whole thing between roughly C3 and C5. Lower than that and
		// four notes turn to mud." Before the stack was normalised, a B form —
		// built up from a root pinned at ROOT_OCTAVE and starting on the ♭7 —
		// landed most of a 7th above its own A form, and B7's topped out at A♭5.
		const low = midi(parseNote('C', 3));
		const high = midi(parseNote('C', 5));
		const outside: string[] = [];
		for (const root of CHORD_ROOTS) {
			for (const quality of ROOTLESS_QUALITIES) {
				for (const form of ROOTLESS_FORMS) {
					const v = buildRootless(root, quality, form);
					const midis = v.notes.map(midi);
					if (midis[0] < low || midis[3] > high) {
						outside.push(`${chordSymbol(root, quality)} ${form}: ${v.names.join('+')}`);
					}
				}
			}
		}
		expect(outside).toEqual([]);
	});

	it('never includes the root, except m7♭5 where the root replaces the ♭9', () => {
		// Half-diminished is the one textbook exception: the ♭9 is the avoid
		// tension there, so its stack is ♭3–♭5–♭7–1 — see ROOTLESS_A_STACK.
		for (const root of CHORD_ROOTS) {
			for (const quality of ROOTLESS_QUALITIES) {
				const rootPc = pitchClass(parseNote(root, 3));
				for (const form of ROOTLESS_FORMS) {
					const pcs = buildRootless(root, quality, form).pitchClasses;
					if (quality === 'm7b5') expect(pcs).toContain(rootPc);
					else expect(pcs).not.toContain(rootPc);
				}
			}
		}
	});

	it('puts the 3rd on the bottom of A and the 7th on the bottom of B', () => {
		const dm7a = buildRootless('D', 'm7', 'A');
		expect(dm7a.names).toEqual(['F', 'A', 'C', 'E']);
		const dm7b = buildRootless('D', 'm7', 'B');
		expect(dm7b.names).toEqual(['C', 'E', 'F', 'A']);
		// Dominants take the 13th rather than the 5th.
		expect(buildRootless('G', '7', 'A').names).toEqual(['B', 'E', 'F', 'A']);
		expect(buildRootless('C', 'maj7', 'A').names).toEqual(['E', 'G', 'B', 'D']);
	});
});

describe('chord construction', () => {
	it('builds the expected pitch classes for each quality on C', () => {
		const pcs = (q: Parameters<typeof buildChord>[1]) =>
			buildChord('C', q).tones.map(pitchClass);
		expect(pcs('maj7')).toEqual([0, 4, 7, 11]);
		expect(pcs('m7')).toEqual([0, 3, 7, 10]);
		expect(pcs('7')).toEqual([0, 4, 7, 10]);
		expect(pcs('m7b5')).toEqual([0, 3, 6, 10]);
		expect(pcs('dim7')).toEqual([0, 3, 6, 9]);
	});

	it('never emits an accidental it cannot render', () => {
		for (const root of CHORD_ROOTS) {
			for (const quality of QUALITIES) {
				for (const tone of buildChord(root, quality).tones) {
					expect(Math.abs(tone.alter)).toBeLessThanOrEqual(2);
				}
			}
		}
	});
});

describe('shells', () => {
	it('always contains the root plus exactly one guide tone', () => {
		for (const root of CHORD_ROOTS) {
			for (const quality of QUALITIES) {
				for (const shellType of SHELL_TYPES) {
					const shell = buildShell(root, quality, shellType);
					expect(shell.names).toHaveLength(2);
					expect(shell.names[0]).toBe(prettyNoteName(root));
					expect(shell.names[1]).not.toBe(prettyNoteName(root));
				}
			}
		}
	});

	it('places the guide tone above the root, within an octave', () => {
		for (const root of CHORD_ROOTS) {
			for (const quality of QUALITIES) {
				for (const shellType of SHELL_TYPES) {
					const [low, high] = buildShell(root, quality, shellType).notes;
					const gap = midi(high) - midi(low);
					expect(gap).toBeGreaterThan(0);
					expect(gap).toBeLessThanOrEqual(12);
				}
			}
		}
	});

	it('gives root-3 and root-7 different guide tones', () => {
		for (const root of CHORD_ROOTS) {
			for (const quality of QUALITIES) {
				const third = buildShell(root, quality, 'r3');
				const seventh = buildShell(root, quality, 'r7');
				expect(third.pitchClasses[1]).not.toBe(seventh.pitchClasses[1]);
			}
		}
	});
});

describe('ii-V-I chains', () => {
	it('builds Gm7 C7 Fmaj7 in F', () => {
		const chain = buildChain('F');
		expect(chain.chords.map((c) => c.symbol)).toEqual(['Gm7', 'C7', 'Fmaj7']);
	});

	it('spells the ii and V diatonically in flat keys', () => {
		expect(buildChain('D♭').chords.map((c) => c.symbol)).toEqual([
			'E♭m7',
			'A♭7',
			'D♭maj7'
		]);
		expect(buildChain('G♭').chords.map((c) => c.symbol)).toEqual([
			'A♭m7',
			'D♭7',
			'G♭maj7'
		]);
	});

	it('builds a minor ii-V-i from the half-diminished ii and a real dominant', () => {
		const chain = buildChain('C', 'minor');
		expect(chain.chords.map((c) => c.symbol)).toEqual(['Dm7♭5', 'G7', 'Cm(maj7)']);
		// The leading tone is what makes it resolve: G7 has a B natural.
		expect(chain.chords[1].tones.map(noteName)).toEqual(['G', 'B', 'D', 'F']);
	});

});
