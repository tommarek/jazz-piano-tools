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
	KEY_CENTERS,
	QUALITIES,
	ROOTLESS_FORMS,
	ROOTLESS_QUALITIES
} from '../../src/lib/music/voicings';
import { DIATONIC, DRILLED_INTERVALS, EXTENSIONS } from '../../src/lib/music/theory-drills';

const catalogue = buildCatalogue();

describe('the catalogue', () => {
	it('has one card per combination and no duplicates', () => {
		const extensionsPerRoot = Object.values(EXTENSIONS).reduce((n, xs) => n + xs.length, 0);
		const expected =
			CHORD_ROOTS.length * ROOTLESS_QUALITIES.length * ROOTLESS_FORMS.length + // rootless A/B
			CHORD_ROOTS.length * extensionsPerRoot + // chord tones & extensions
			CHORD_ROOTS.length * DRILLED_INTERVALS.length + // intervals
			CHORD_ROOTS.length * DRILLED_INTERVALS.length + // intervals by ear
			CHORD_ROOTS.length * QUALITIES.length + // qualities by ear
			2 * KEY_CENTERS.length + // chains: one per key, major + minor
			CHORD_ROOTS.length * QUALITIES.length + // symbol → guide tones
			CHORD_ROOTS.length * 3 + // guide tones → symbol, three interval classes
			2 * KEY_CENTERS.length * 2 + // guide-tone comping: major + minor, two transitions
			KEY_CENTERS.length * 2 * 2 + // rootless comping: two transitions, two start forms
			KEY_CENTERS.length * DIATONIC.length + // diatonic harmony
			KEY_CENTERS.length * DIATONIC.length; // modes
		expect(expected).toBe(972);
		expect(catalogue).toHaveLength(expected);
		expect(new Set(catalogue.map((c) => c.id)).size).toBe(expected);
	});

	it('generates the same ids in the same order every call', () => {
		expect(buildCatalogue().map((c) => c.id)).toEqual(catalogue.map((c) => c.id));
	});

	/**
	 * The ids themselves, snapshotted: determinism inside one build says nothing
	 * about the next one, and a changed id is not a lost history any more — the
	 * card leaves the catalogue, so `syncCatalogue` purges its reviews on launch
	 * with no server-side copy to restore. Adding cards is a pure addition to
	 * this file; anything else in the diff is somebody's practice being deleted.
	 */
	it('matches the reviewed card-id snapshot', async () => {
		const ids = catalogue.map((c) => c.id).sort();
		await expect(ids.join('\n') + '\n').toMatchFileSnapshot('./__golden__/ids.txt');
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

	/**
	 * The ii–V–I golden, generated from the notes the drill deals rather than
	 * from the root shells underneath it: the chain asks for the 3rd and the
	 * 7th, and a snapshot of `buildShell` could not see a spelling change in
	 * them. Reviewed by hand once; any diff after that is a regression.
	 */
	it('matches the reviewed ii–V–I snapshot', async () => {
		const lines = catalogue
			.filter((spec) => spec.type === 'chain')
			.map((spec) => {
				const view = renderCard(spec);
				const body = view.steps
					.map((s) => `${s.position}:${s.symbol}=${s.names.join('+')}`)
					.join('  ');
				return `${view.title.padEnd(22)} ${body}`;
			});
		await expect(lines.join('\n') + '\n').toMatchFileSnapshot('./__golden__/chains.txt');
	});

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
		// A symbol→guide-tones card that already displays its notes teaches nothing.
		for (const v of views) {
			if (v.type !== 'gt') continue;
			for (const name of v.steps[0].names) {
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

	it('describes the chain’s voice leading from the notes it actually deals', () => {
		// The rationale under a chain is the one place the drill explains itself,
		// and major’s semitone against minor’s whole tone is exactly what it
		// must not assume. Asserted on renderCard, not on the theory engine: this
		// string is what the learner reads.
		for (const spec of catalogue.filter((c) => c.type === 'chain')) {
			const v = renderCard(spec);
			for (let i = 0; i < 2; i++) {
				const [third, seventh] = v.steps[i].expected;
				const [nextThird, nextSeventh] = v.steps[i + 1].expected;
				// One note holds — the 3rd becomes the next chord’s 7th.
				expect(third).toBe(nextSeventh);
				// The other falls a step: a semitone everywhere except into a minor
				// tonic, where the 7th of V falls a whole tone to a minor 3rd.
				const fell = (seventh - nextThird + 12) % 12;
				expect(fell).toBe(spec.mode === 'minor' && i === 1 ? 2 : 1);
				expect(v.rationale).toContain(fell === 1 ? 'falls a semitone' : 'falls a whole tone');
			}
		}
	});

	it('names the held and the moving note on a comping card', () => {
		// Dm7 → G7: F is held as G7’s 7th, C falls a semitone to B.
		const v = renderCard({
			id: 'gtc:C:ii-V',
			type: 'gtc',
			key: 'C',
			transition: 'ii-V',
			mode: 'major'
		});
		expect(v.rationale).toContain("Dm7's 3rd (F) is held as G7's 7th");
		expect(v.rationale).toContain("its 7th (C) falls to G7's 3rd (B)");
	});

	it('shows guide-tones→symbol cards their pair and accepts every reading', () => {
		for (const v of views.filter((v) => v.type === 'gtn')) {
			// Quality only: the 3rd is marked on the prompt keyboard, so asking
			// for a root would grade a note the voicing does not even contain.
			expect(v.input).toBe('quality-name');
			expect(v.given).toHaveLength(2);
			expect(v.expectedChord).toBeDefined();
			// A pair never pins down one quality unless it is the minor 6th class,
			// where naming its one chord is the whole point of the card. Asserted
			// per class: a bare ">= 1" also passes on a GT_CLASS_ACCEPTS that has
			// lost its ambiguity, which is the regression that would start grading
			// a correct "m7" on gtn:C:maj7 as wrong.
			const cls = v.id.split(':')[2];
			if (cls === 'mMaj7') expect(v.expectedChord!.alsoAccept).toHaveLength(1);
			else expect(v.expectedChord!.alsoAccept!.length).toBeGreaterThan(1);
			expect(v.expectedChord!.alsoAccept).toContain(v.expectedChord!.quality);
			expect(v.rootGiven).toBe(v.given[0]);
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
			...Array.from({ length: 12 }, (_, i) => ({ id: `gt:${i}`, type: 'gt' })),
			...Array.from({ length: 5 }, (_, i) => ({ id: `gtn:${i}`, type: 'gtn' })),
			...Array.from({ length: 4 }, (_, i) => ({ id: `chain:${i}`, type: 'chain' }))
		];
		const picked = spreadAcrossTypes(cards, 8);
		expect(picked).toHaveLength(8);
		// Blocked practice is what interleaving exists to avoid — a first session
		// of eight symbol→guide-tone cards on one root is exactly that.
		expect(new Set(picked.map((c) => c.type)).size).toBe(3);
	});

	it('keeps taking from what is left once a type runs out', async () => {
		const { spreadAcrossTypes } = await import('../../src/lib/data/queue');
		const cards = [
			{ id: 'chain:1', type: 'chain' },
			...Array.from({ length: 5 }, (_, i) => ({ id: `gt:${i}`, type: 'gt' }))
		];
		expect(spreadAcrossTypes(cards, 4).map((c) => c.type)).toEqual([
			'chain',
			'gt',
			'gt',
			'gt'
		]);
	});

	it('returns nothing for a zero budget', async () => {
		const { spreadAcrossTypes } = await import('../../src/lib/data/queue');
		expect(spreadAcrossTypes([{ id: 'gt:C:maj7', type: 'gt' }], 0)).toHaveLength(0);
		expect(spreadAcrossTypes([], 5)).toHaveLength(0);
	});

	it('introduces roots in fourths order, not chromatically', async () => {
		const { spreadAcrossTypes } = await import('../../src/lib/data/queue');
		// Chromatic order would follow C with D♭, a key it shares nothing with.
		const chains = KEY_CENTERS.map((k) => ({ id: `chain:${slug(k)}`, type: 'chain' }));
		expect(spreadAcrossTypes(chains, 4).map((c) => c.id.split(':')[1])).toEqual([
			'C',
			'F',
			'Bb',
			'Eb'
		]);

		// And each type enters the cycle at its own catalogue position, so two
		// types introduced on the same day do not both open on C: gt is second in
		// CARD_TYPES, so its rotation starts one fourth along.
		const pairs = CHORD_ROOTS.map((r) => ({ id: `gt:${slug(r)}:maj7`, type: 'gt' }));
		expect(spreadAcrossTypes(pairs, 4).map((c) => c.id.split(':')[1])).toEqual([
			'F',
			'Bb',
			'Eb',
			'Ab'
		]);
	});

	it('resumes the rotation next session instead of restarting it', async () => {
		const { spreadAcrossTypes } = await import('../../src/lib/data/queue');
		// Two new cards a day, six days. A rotation that restarts each session
		// never leaves C and F — which is what kept stage 2, whose gate wants an
		// automatic guide-tone pair in all twelve keys, shut for months.
		let pool = CHORD_ROOTS.flatMap((r) =>
			QUALITIES.slice(0, 3).map((q) => ({ id: `gt:${slug(r)}:${q}`, type: 'gt' }))
		);
		const roots: string[] = [];
		let seen = 0;
		for (let session = 0; session < 6; session++) {
			const drawn = spreadAcrossTypes(pool, 2, new Map([['gt', seen]]));
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
			...Array.from({ length: 6 }, (_, i) => ({ id: `gt:${i}`, type: 'gt' })),
			...Array.from({ length: 6 }, (_, i) => ({ id: `gtc:${i}`, type: 'gtc' }))
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
