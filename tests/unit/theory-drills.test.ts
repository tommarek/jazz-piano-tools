import { describe, expect, it } from 'vitest';
import { buildCatalogue, renderCard, parseCardId } from '../../src/lib/music/cards';
import type { CardSpec } from '../../src/lib/music/cards';
import { DIATONIC, DRILLED_INTERVALS, EXTENSIONS } from '../../src/lib/music/theory-drills';
import { CHORD_ROOTS, KEY_CENTERS } from '../../src/lib/music/voicings';
import { noteName, parseNote, pitchClass } from '../../src/lib/music/theory';

const catalogue = buildCatalogue();
const of = (type: string) => catalogue.filter((c) => c.type === type);
const view = (spec: CardSpec) => renderCard(spec);

/** The single expected note of a one-key card. */
function answerName(spec: CardSpec): string {
	return view(spec).steps[0].names[0];
}

function find(type: string, match: (c: never) => boolean): CardSpec {
	const hit = of(type).find(match as (c: CardSpec) => boolean);
	if (!hit) throw new Error(`No ${type} card matched`);
	return hit;
}

describe('golden file: theory spelling', () => {
	it('matches the reviewed extensions and intervals snapshot', async () => {
		const lines: string[] = [];
		for (const root of CHORD_ROOTS) {
			for (const [quality, extensions] of Object.entries(EXTENSIONS)) {
				const cells = extensions
					.map((ext) => {
						const spec = find(
							'ext',
							(c: never) =>
								(c as CardSpec & { type: 'ext' }).root === root &&
								(c as CardSpec & { type: 'ext' }).quality === quality &&
								(c as CardSpec & { type: 'ext' }).interval === ext.interval
						);
						return `${ext.label}=${answerName(spec)}`;
					})
					.join(' ');
				lines.push(`${(root + quality).padEnd(10)} ${cells}`);
			}
		}
		lines.push('');
		for (const root of CHORD_ROOTS) {
			const cells = DRILLED_INTERVALS.map((interval) => {
				const spec = find(
					'ivl',
					(c: never) =>
						(c as CardSpec & { type: 'ivl' }).root === root &&
						(c as CardSpec & { type: 'ivl' }).interval === interval
				);
				return `${interval}=${answerName(spec)}`;
			}).join(' ');
			lines.push(`${root.padEnd(3)} ${cells}`);
		}
		await expect(lines.join('\n') + '\n').toMatchFileSnapshot('./__golden__/theory.txt');
	});

	it('matches the reviewed diatonic snapshot', async () => {
		const lines: string[] = [];
		for (const key of KEY_CENTERS) {
			const cells = DIATONIC.map((d) => {
				const spec = find(
					'dia',
					(c: never) =>
						(c as CardSpec & { type: 'dia' }).key === key &&
						(c as CardSpec & { type: 'dia' }).numeral === d.numeral
				);
				return `${d.numeral}=${view(spec).answerText}`;
			}).join(' ');
			lines.push(`${key.padEnd(3)} ${cells}`);
		}
		await expect(lines.join('\n') + '\n').toMatchFileSnapshot('./__golden__/diatonic.txt');
	});
});

describe('chord tones and extensions', () => {
	it('spells the classic dominant alterations', () => {
		const a7 = (interval: string) =>
			answerName(
				find(
					'ext',
					(c: never) =>
						(c as CardSpec & { type: 'ext' }).root === 'A' &&
						(c as CardSpec & { type: 'ext' }).quality === '7' &&
						(c as CardSpec & { type: 'ext' }).interval === interval
				)
			);
		expect(a7('m9')).toBe('B♭');
		// Spelled B♯ rather than C: it is a ninth, so it must sit on a B.
		expect(a7('A9')).toBe('B♯');
		expect(a7('A11')).toBe('D♯');
		expect(a7('M13')).toBe('F♯');
		expect(a7('m13')).toBe('F');
	});

	it('asks for one note and shows no keys in the prompt', () => {
		for (const spec of of('ext')) {
			const v = view(spec);
			expect(v.steps[0].expected).toHaveLength(1);
			expect(v.given).toHaveLength(0);
			expect(v.title).not.toContain(v.steps[0].names[0]);
		}
	});

	it('never puts an extension on a diminished 7th', () => {
		// Extensions on a fully diminished chord are a different conversation.
		expect(of('ext').some((c) => (c as CardSpec & { type: 'ext' }).quality === 'dim7')).toBe(false);
	});
});

describe('intervals', () => {
	it('spells a tritone as a diminished 5th, on the right letter', () => {
		const spec = find(
			'ivl',
			(c: never) =>
				(c as CardSpec & { type: 'ivl' }).root === 'Bb' &&
				(c as CardSpec & { type: 'ivl' }).interval === 'd5'
		);
		expect(answerName(spec)).toBe('F♭');
		expect(view(spec).steps[0].expected[0]).toBe(4);
	});

	it('lights the root so the question is unambiguous', () => {
		for (const spec of of('ivl')) {
			const v = view(spec);
			expect(v.given).toHaveLength(1);
			expect(v.rootGiven).toBe(v.given[0]);
		}
	});

	it('covers every drilled interval from every root', () => {
		expect(of('ivl')).toHaveLength(CHORD_ROOTS.length * DRILLED_INTERVALS.length);
	});
});

describe('diatonic harmony', () => {
	it('knows the ii, V and vii of a flat key', () => {
		const chordFor = (key: string, numeral: string) =>
			view(
				find(
					'dia',
					(c: never) =>
						(c as CardSpec & { type: 'dia' }).key === key &&
						(c as CardSpec & { type: 'dia' }).numeral === numeral
				)
			).answerText;
		expect(chordFor('Db', 'ii')).toBe('E♭m7');
		expect(chordFor('Db', 'V')).toBe('A♭7');
		expect(chordFor('Db', 'vii')).toBe('Cm7♭5');
		// The IV of G♭ really is C♭, not B — and it is graded by pitch class so
		// tapping B is accepted anyway.
		expect(chordFor('Gb', 'IV')).toBe('C♭maj7');
	});

	it('grades on pitch class, because some answers are off the root picker', () => {
		for (const spec of of('dia')) {
			const v = view(spec);
			expect(v.expectedChord).toBeDefined();
			expect(v.expectedChord!.rootPc).toBe(pitchClass(parseNote(v.expectedChord!.root, 4)));
		}
		const offGrid = of('dia')
			.map(view)
			.filter((v) => !CHORD_ROOTS.includes(v.expectedChord!.root));
		expect(offGrid.length).toBeGreaterThan(0);
	});

	it('never leaks the answer into the prompt', () => {
		for (const spec of of('dia')) {
			const v = view(spec);
			expect(v.title).not.toContain(v.answerText);
		}
	});
});

describe('scales and modes', () => {
	it('maps each degree to its mode', () => {
		const modeFor = (key: string, numeral: string) =>
			view(
				find(
					'mode',
					(c: never) =>
						(c as CardSpec & { type: 'mode' }).key === key &&
						(c as CardSpec & { type: 'mode' }).numeral === numeral
				)
			).expectedMode;
		expect(modeFor('G', 'ii')).toBe('Dorian');
		expect(modeFor('G', 'V')).toBe('Mixolydian');
		expect(modeFor('G', 'vii')).toBe('Locrian');
		expect(modeFor('C', 'I')).toBe('Ionian');
	});

	it('names the chord it is asking about, in the right key', () => {
		const v = view(
			find(
				'mode',
				(c: never) =>
					(c as CardSpec & { type: 'mode' }).key === 'A' &&
					(c as CardSpec & { type: 'mode' }).numeral === 'ii'
			)
		);
		expect(v.title).toBe('Bm7 in A major');
		expect(v.input).toBe('mode-name');
	});
});

describe('every new card type round-trips its id', () => {
	it('parses back to the same spec', () => {
		for (const spec of catalogue) {
			expect(parseCardId(spec.id)).toEqual(spec);
		}
	});

	it('keeps the ids minted before minor chains existed', () => {
		// Major chains must not have gained a mode segment, or a year of review
		// history would detach from its cards.
		expect(parseCardId('chain:C:737')).toMatchObject({ type: 'chain', mode: 'major' });
		expect(parseCardId('vl:C:737:ii-V')).toMatchObject({ type: 'vl', mode: 'major' });
		expect(parseCardId('chain:C:737:minor')).toMatchObject({ mode: 'minor' });
	});

	it('rejects malformed ids', () => {
		expect(parseCardId('chain:C:737:major')).toBeNull();
		expect(parseCardId('rootless:C:m7')).toBeNull();
		expect(parseCardId('ivl:C')).toBeNull();
	});
});

describe('minor chains', () => {
	it('adds a full set without disturbing the major ones', () => {
		const chains = of('chain');
		expect(chains.filter((c) => (c as CardSpec & { type: 'chain' }).mode === 'major')).toHaveLength(
			24
		);
		expect(chains.filter((c) => (c as CardSpec & { type: 'chain' }).mode === 'minor')).toHaveLength(
			24
		);
	});

	it('titles minor chains as minor', () => {
		const minor = of('chain').find((c) => (c as CardSpec & { type: 'chain' }).mode === 'minor')!;
		expect(view(minor).title).toContain('minor');
		expect(view(minor).title).toContain('iiø');
	});
});

describe('rootless cards', () => {
	it('are graded as an ordered sequence', () => {
		for (const spec of of('rootless')) {
			const step = view(spec).steps[0];
			expect(step.ordered).toBe(true);
			expect(step.expected).toHaveLength(4);
		}
	});

	it('distinguish A from B only by order', () => {
		const a = of('rootless').find(
			(c) =>
				(c as CardSpec & { type: 'rootless' }).root === 'D' &&
				(c as CardSpec & { type: 'rootless' }).quality === 'm7' &&
				(c as CardSpec & { type: 'rootless' }).form === 'A'
		)!;
		const b = of('rootless').find(
			(c) =>
				(c as CardSpec & { type: 'rootless' }).root === 'D' &&
				(c as CardSpec & { type: 'rootless' }).quality === 'm7' &&
				(c as CardSpec & { type: 'rootless' }).form === 'B'
		)!;
		const [va, vb] = [view(a).steps[0], view(b).steps[0]];
		expect([...va.expected].sort()).toEqual([...vb.expected].sort());
		expect(va.expected).not.toEqual(vb.expected);
		expect(va.names[0]).toBe('F');
		expect(vb.names[0]).toBe('C');
	});

	it('name every note in the answer text', () => {
		for (const spec of of('rootless')) {
			const v = view(spec);
			for (const name of v.steps[0].names) expect(v.answerText).toContain(name);
		}
	});
});

describe('the whole catalogue still holds together', () => {
	it('gives every card a prompt, an answer and a reason', () => {
		for (const spec of catalogue) {
			const v = view(spec);
			expect(v.title.length).toBeGreaterThan(0);
			expect(v.instruction.length).toBeGreaterThan(0);
			expect(v.answerText.length).toBeGreaterThan(0);
			expect(v.rationale.length).toBeGreaterThan(0);
			expect(v.rootPitchClass).toBeGreaterThanOrEqual(0);
			expect(v.rootPitchClass).toBeLessThan(12);
		}
	});

	it('only ever asks for pitch classes that exist', () => {
		for (const spec of catalogue) {
			for (const step of view(spec).steps) {
				for (const pc of step.expected) {
					expect(pc).toBeGreaterThanOrEqual(0);
					expect(pc).toBeLessThan(12);
				}
				expect(step.expected).toHaveLength(step.names.length);
			}
		}
	});

	it('spells every answer with a renderable accidental', () => {
		for (const spec of catalogue) {
			for (const step of view(spec).steps) {
				for (const name of step.names) {
					expect(() => noteName(parseNote(name, 4))).not.toThrow();
				}
			}
		}
	});
});
