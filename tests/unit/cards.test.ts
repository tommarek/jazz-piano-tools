import { describe, expect, it } from 'vitest';
import {
	buildCatalogue,
	parseCardId,
	renderCard,
	CARD_TYPES,
	STAGE_OF_TYPE,
	type CardSpec
} from '../../src/lib/music/cards';
import {
	CHORD_ROOTS,
	GUIDE_INTERVALS,
	KEY_CENTERS,
	MINOR_KEY_CENTERS,
	QUALITIES,
	ROOTLESS_FORMS,
	ROOTLESS_QUALITIES,
	SHELL_TYPES
} from '../../src/lib/music/voicings';
import { DIATONIC, DRILLED_INTERVALS, EXTENSIONS } from '../../src/lib/music/theory-drills';

const catalogue = buildCatalogue();

describe('the catalogue', () => {
	it('has one card per combination and no duplicates', () => {
		const extensionsPerRoot = Object.values(EXTENSIONS).reduce((n, xs) => n + xs.length, 0);
		const expected =
			CHORD_ROOTS.length * QUALITIES.length * SHELL_TYPES.length + // symbol → notes
			CHORD_ROOTS.length * GUIDE_INTERVALS.length + // notes → symbol
			CHORD_ROOTS.length * ROOTLESS_QUALITIES.length * ROOTLESS_FORMS.length + // rootless A/B
			CHORD_ROOTS.length * extensionsPerRoot + // chord tones & extensions
			CHORD_ROOTS.length * DRILLED_INTERVALS.length + // intervals
			CHORD_ROOTS.length * DRILLED_INTERVALS.length + // intervals by ear
			CHORD_ROOTS.length * QUALITIES.length + // qualities by ear
			2 * KEY_CENTERS.length * 2 + // chains: major + minor, two variants
			2 * KEY_CENTERS.length * 2 * 2 + // voice leading, two transitions per variant
			CHORD_ROOTS.length * QUALITIES.length + // symbol → guide tones
			CHORD_ROOTS.length * 3 + // guide tones → symbol, three interval classes
			2 * KEY_CENTERS.length * 2 + // guide-tone comping: major + minor, two transitions
			KEY_CENTERS.length * 2 * 2 + // rootless comping: two transitions, two start forms
			KEY_CENTERS.length * DIATONIC.length + // diatonic harmony
			KEY_CENTERS.length * DIATONIC.length; // modes
		expect(expected).toBe(1296);
		expect(catalogue).toHaveLength(expected);
		expect(new Set(catalogue.map((c) => c.id)).size).toBe(expected);
	});

	it('is stable across builds, so ids never orphan review history', () => {
		expect(buildCatalogue().map((c) => c.id)).toEqual(catalogue.map((c) => c.id));
	});

	it('round-trips every id back to its spec', () => {
		for (const spec of catalogue) {
			expect(parseCardId(spec.id)).toEqual(spec);
		}
	});

	it('gives the ear drills their own id namespace', () => {
		// Their own prefix, not a suffix on ivl/gt: an ear card is a different
		// question about the same music, and shares no review history with it.
		expect(parseCardId('eint:Db:d5')).toEqual({
			id: 'eint:Db:d5',
			type: 'eint',
			root: 'Db',
			interval: 'd5'
		});
		expect(parseCardId('eqal:Fs:m7b5')).toEqual({
			id: 'eqal:Fs:m7b5',
			type: 'eqal',
			root: 'F#',
			quality: 'm7b5'
		});
		expect(parseCardId('eint:C')).toBeNull();
	});

	it('rejects ids that are not cards', () => {
		expect(parseCardId('nonsense')).toBeNull();
		expect(parseCardId('s2n:C:maj7')).toBeNull();
	});

	it('keeps sharps out of ids but restores them on parse', () => {
		const sharp = catalogue.find((c) => 'root' in c && c.root === 'F#') as CardSpec;
		expect(sharp.id).not.toContain('#');
		expect(parseCardId(sharp.id)).toEqual(sharp);
	});
});

describe('rendering', () => {
	const views = catalogue.map(renderCard);

	it('gives every card a prompt, an answer and a reason', () => {
		for (const v of views) {
			expect(v.title.length).toBeGreaterThan(0);
			expect(v.instruction.length).toBeGreaterThan(0);
			expect(v.answerText.length).toBeGreaterThan(0);
			expect(v.rationale.length).toBeGreaterThan(0);
		}
	});

	it('asks for exactly the notes it will accept', () => {
		for (const v of views) {
			if (v.input !== 'keys') continue;
			expect(v.steps.length).toBeGreaterThan(0);
			for (const step of v.steps) {
				expect(step.expected.length).toBe(step.names.length);
				for (const pc of step.expected) {
					expect(pc).toBeGreaterThanOrEqual(0);
					expect(pc).toBeLessThan(12);
				}
			}
		}
	});

	it('never shows the answer in the prompt', () => {
		// A symbol→notes card that already displays its notes teaches nothing.
		for (const v of views) {
			if (v.type !== 's2n') continue;
			for (const name of v.steps[0].names.slice(1)) {
				expect(v.title).not.toContain(name);
			}
			expect(v.given).toHaveLength(0);
		}
	});

	it('asks chain cards for all three chords, with mode-matched numerals', () => {
		for (const spec of catalogue.filter((c) => c.type === 'chain')) {
			const v = renderCard(spec);
			expect(v.steps).toHaveLength(3);
			expect(v.steps.map((s) => s.position)).toEqual(
				spec.mode === 'minor' ? ['iiø', 'V', 'i'] : ['ii', 'V', 'I']
			);
			expect(v.steps.every((s) => s.expected.length === 2)).toBe(true);
		}
	});

	it('gives voice-leading cards the previous shell and asks for one note', () => {
		for (const v of views.filter((v) => v.type === 'vl')) {
			expect(v.given).toHaveLength(2);
			expect(v.steps[0].expected).toHaveLength(1);
		}
	});

	it('lights the answer on held transitions and only on those', () => {
		// When the guide tone holds, the correct key is already lit — that is the
		// card, and answering it means knowing the note does not move.
		for (const spec of catalogue.filter((c) => c.type === 'vl')) {
			const v = renderCard(spec);
			const alreadyLit = v.given.includes(v.steps[0].expected[0]);
			expect(alreadyLit).toBe(v.rationale.includes('held'));
		}
	});

	it('shows notes→symbol cards their notes and asks for a quality they could be', () => {
		for (const v of views.filter((v) => v.type === 'n2s')) {
			// Quality only: the root is marked on the prompt keyboard, so asking
			// for it back would grade reading, not recall.
			expect(v.input).toBe('quality-name');
			expect(v.given).toHaveLength(2);
			expect(v.expectedChord).toBeDefined();
			// Two notes never pin down one quality, so every consistent quality
			// must be accepted: Dm7 and Dm7♭5 share their third.
			expect(v.expectedChord!.alsoAccept!.length).toBeGreaterThanOrEqual(1);
			expect(v.expectedChord!.alsoAccept).toContain(v.expectedChord!.quality);
			// The root must be marked, or two lit keys are ambiguous: {Db, E} is a
			// minor 3rd over Db and equally a diminished 7th over E.
			expect(v.rootGiven).toBe(v.given[0]);
			expect(v.title).not.toContain(v.expectedChord!.root);
		}
	});

	it('never asks a notes→symbol question whose answer is ambiguous', () => {
		// Root plus pitch class must map to exactly one interval in the deck.
		const seen = new Map<string, string>();
		for (const spec of catalogue.filter((c) => c.type === 'n2s')) {
			const v = renderCard(spec);
			const key = `${v.rootGiven}:${v.given[1]}`;
			expect(seen.has(key)).toBe(false);
			seen.set(key, v.id);
		}
	});

	it('asks ear cards nothing but the sound', () => {
		for (const v of views.filter((v) => v.type === 'eint' || v.type === 'eqal')) {
			expect(v.promptIsSound).toBe(true);
			// Nothing lit and nothing to tap: a keyboard showing the notes would be
			// the answer, and the prompt text must not name them either.
			expect(v.given).toHaveLength(0);
			expect(v.steps).toHaveLength(0);
			expect(v.sound!.groups.length).toBeGreaterThan(0);
			for (const group of v.sound!.groups) {
				expect(group.length).toBeGreaterThan(0);
				for (const note of group) {
					expect(note).toBeGreaterThanOrEqual(36);
					expect(note).toBeLessThanOrEqual(84);
				}
			}
		}
	});

	it('plays an interval ear card as two notes, low to high', () => {
		for (const v of views.filter((v) => v.type === 'eint')) {
			expect(v.input).toBe('interval-name');
			expect(v.expectedInterval).toBeDefined();
			const [[low], [high]] = v.sound!.groups;
			expect(v.sound!.groups).toHaveLength(2);
			expect(high).toBeGreaterThan(low);
		}
	});

	it('accepts exactly one quality on a chord ear card', () => {
		// Four notes do pin the quality down — unlike the two-note shells that
		// share this picker, where every consistent reading has to be accepted.
		for (const v of views.filter((v) => v.type === 'eqal')) {
			expect(v.input).toBe('quality-name');
			expect(v.expectedChord!.alsoAccept).toBeUndefined();
			expect(v.sound!.groups).toHaveLength(1);
			expect(v.sound!.groups[0]).toHaveLength(4);
		}
	});

	it('keeps the root of an ear card out of the prompt', () => {
		// The root is what the card varies over, never what it asks: naming it in
		// the prompt would turn "which interval" into "which note".
		for (const spec of catalogue.filter((c) => c.type === 'eint' || c.type === 'eqal')) {
			const v = renderCard(spec);
			const root = 'root' in spec ? spec.root : '';
			expect(v.title).toBe('Listen');
			expect(v.instruction).not.toContain(root);
		}
	});

	it('gives every extension card audio of its own', () => {
		// The bed is what places the colour, so two cards sharing one are the same
		// question asked twice: root–3–7 made every m7♭5 card sound like its m7
		// neighbour, ♭5 and all, and the ♭13 over it read as a ♭6.
		const bySound = new Map<string, string>();
		for (const v of views.filter((v) => v.type === 'ext')) {
			const key = JSON.stringify(v.sound!.groups);
			expect(bySound.get(key)).toBeUndefined();
			bySound.set(key, v.id);
		}
	});

	it('spells alternate guide-tone readings on roots a chart would carry', () => {
		// Derived by interval from the marked 3rd, the alternate root lands on F♯♯
		// or B♯ — correct arithmetic, unreadable as a chord symbol.
		for (const v of views.filter((v) => v.type === 'gtn')) {
			expect(v.answerText).not.toMatch(/♯♯|♭♭|##|bb/);
			expect(v.answerText).not.toMatch(/(^|[\s,(])[BE]♯/);
			expect(v.rationale).not.toMatch(/♯♯|♭♭/);
		}
	});

	it('assigns every card to one of the twelve keys', () => {
		for (const v of views) {
			expect(v.rootPitchClass).toBeGreaterThanOrEqual(0);
			expect(v.rootPitchClass).toBeLessThan(12);
		}
	});
});

describe('new-card selection', () => {
	// Card ids carry the root slug, not the note name; the rotation only sorts
	// by fourths when it can parse one back out.
	const slug = (root: string) => root.replace('#', 's');

	it('spreads across types instead of draining one', async () => {
		const { spreadAcrossTypes } = await import('../../src/lib/data/queue');
		const cards = [
			...Array.from({ length: 12 }, (_, i) => ({ id: `s2n:${i}`, type: 's2n' })),
			...Array.from({ length: 5 }, (_, i) => ({ id: `n2s:${i}`, type: 'n2s' })),
			...Array.from({ length: 4 }, (_, i) => ({ id: `chain:${i}`, type: 'chain' }))
		];
		const picked = spreadAcrossTypes(cards, 8);
		expect(picked).toHaveLength(8);
		// Blocked practice is what interleaving exists to avoid — a first session
		// of eight symbol→notes cards on one root is exactly that.
		expect(new Set(picked.map((c) => c.type)).size).toBe(3);
	});

	it('keeps taking from what is left once a type runs out', async () => {
		const { spreadAcrossTypes } = await import('../../src/lib/data/queue');
		const cards = [
			{ id: 'a:1', type: 'a' },
			...Array.from({ length: 5 }, (_, i) => ({ id: `b:${i}`, type: 'b' }))
		];
		expect(spreadAcrossTypes(cards, 4).map((c) => c.type)).toEqual(['a', 'b', 'b', 'b']);
	});

	it('returns nothing for a zero budget', async () => {
		const { spreadAcrossTypes } = await import('../../src/lib/data/queue');
		expect(spreadAcrossTypes([{ id: 'x', type: 'x' }], 0)).toHaveLength(0);
		expect(spreadAcrossTypes([], 5)).toHaveLength(0);
	});

	it('introduces roots in fourths order, not chromatically', async () => {
		const { spreadAcrossTypes } = await import('../../src/lib/data/queue');
		const cards = CHORD_ROOTS.map((r) => ({ id: `s2n:${slug(r)}:maj7:r3`, type: 's2n' }));
		// Chromatic order would follow C with D♭, a key it shares nothing with.
		expect(spreadAcrossTypes(cards, 4).map((c) => c.id.split(':')[1])).toEqual([
			'C',
			'F',
			'Bb',
			'Eb'
		]);
	});

	it('resumes the rotation next session instead of restarting it', async () => {
		const { spreadAcrossTypes } = await import('../../src/lib/data/queue');
		// Two new cards a day, six days. A rotation that restarts each session
		// never leaves C and F — which is what kept stage 2, whose gate wants an
		// automatic shell in all twelve keys, shut for months.
		let pool = CHORD_ROOTS.flatMap((r) =>
			[0, 1, 2].map((i) => ({ id: `s2n:${slug(r)}:maj7:r${i}`, type: 's2n' }))
		);
		const roots: string[] = [];
		let seen = 0;
		for (let session = 0; session < 6; session++) {
			const drawn = spreadAcrossTypes(pool, 2, new Map([['s2n', seen]]));
			const taken = new Set(drawn.map((c) => c.id));
			pool = pool.filter((c) => !taken.has(c.id));
			seen += drawn.length;
			roots.push(...drawn.map((c) => c.id.split(':')[1]));
		}
		expect(roots).toHaveLength(12);
		expect(new Set(roots).size).toBe(12);
	});

	it('is deterministic, so the same deck always introduces the same cards', async () => {
		const { spreadAcrossTypes } = await import('../../src/lib/data/queue');
		const cards = [
			...Array.from({ length: 6 }, (_, i) => ({ id: `s2n:${i}`, type: 's2n' })),
			...Array.from({ length: 6 }, (_, i) => ({ id: `vl:${i}`, type: 'vl' }))
		];
		const first = spreadAcrossTypes([...cards], 5).map((c) => c.id);
		const second = spreadAcrossTypes([...cards], 5).map((c) => c.id);
		expect(first).toEqual(second);
	});
});

describe('the path', () => {
	it('assigns every card type to a stage', () => {
		// A type missing from STAGES gets an undefined stage, which no comparison
		// against unlockedStages ever passes — the deck would silently never deal
		// it, with nothing anywhere reporting a problem.
		expect(CARD_TYPES.filter((t) => !STAGE_OF_TYPE[t])).toEqual([]);
	});
});
