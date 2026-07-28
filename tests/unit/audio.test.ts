import { describe, expect, it } from 'vitest';
import {
	initAudio,
	isAudioReady,
	midiForPitchClass,
	midiToFreq,
	playNotes,
	playSequence,
	sequenceSchedule,
	stopAll
} from '../../src/lib/audio/piano';
import { buildCatalogue, renderCard } from '../../src/lib/music/cards';

describe('midi mapping', () => {
	it('places pitch classes in the octave asked for', () => {
		expect(midiForPitchClass(0, 4)).toBe(60);
		expect(midiForPitchClass(9, 4)).toBe(69);
		expect(midiForPitchClass(0, 3)).toBe(48);
	});

	it('tunes A4 to 440 and octaves to doubles', () => {
		expect(midiToFreq(69)).toBeCloseTo(440, 6);
		expect(midiToFreq(81)).toBeCloseTo(880, 6);
		expect(midiToFreq(57)).toBeCloseTo(220, 6);
	});
});

describe('sequence timing', () => {
	it('spaces groups evenly from the start of the sequence', () => {
		const schedule = sequenceSchedule([[60], [62], [64]], { gapMs: 500 });
		expect(schedule.map((g) => g.atMs)).toEqual([0, 500, 1000]);
		expect(schedule.map((g) => g.notes)).toEqual([[60], [62], [64]]);
	});

	it('gives a lone group no delay', () => {
		expect(sequenceSchedule([[60, 64, 67]])).toEqual([{ notes: [60, 64, 67], atMs: 0 }]);
	});

	// A silent beat inside a ii–V–I reads as a missing chord, not as a rest.
	it('closes up empty and unplayable groups rather than leaving a hole', () => {
		const schedule = sequenceSchedule([[60], [], [64]], { gapMs: 400 });
		expect(schedule).toEqual([
			{ notes: [60], atMs: 0 },
			{ notes: [64], atMs: 400 }
		]);
		expect(sequenceSchedule([[Number.NaN, 999, 60]])).toEqual([{ notes: [60], atMs: 0 }]);
		expect(sequenceSchedule([])).toEqual([]);
	});
});

describe('without a Web Audio implementation', () => {
	// Node, jsdom and some WebViews have no AudioContext. Silence is the only
	// acceptable failure mode: a missing nicety must never take a session down.
	it('degrades silently instead of throwing', () => {
		expect(() => stopAll()).not.toThrow();
		expect(() => initAudio()).not.toThrow();
		expect(() => playNotes([60, 64, 67])).not.toThrow();
		expect(() => playSequence([[60], [64]])).not.toThrow();
		expect(() => stopAll()).not.toThrow();
		expect(isAudioReady()).toBe(false);
	});
});

describe('card playback', () => {
	const views = buildCatalogue().map(renderCard);

	it('gives every card something to play, in a playable register', () => {
		for (const v of views) {
			expect(v.sound).toBeDefined();
			const schedule = sequenceSchedule(v.sound!.groups);
			expect(schedule.length).toBe(v.sound!.groups.length);
			for (const group of v.sound!.groups) {
				expect(group.length).toBeGreaterThan(0);
				for (const note of group) {
					expect(note).toBeGreaterThanOrEqual(36);
					expect(note).toBeLessThanOrEqual(84);
				}
			}
		}
	});

	it('plays what each card type is about', () => {
		const groupsOf = (id: string) => views.find((v) => v.id === id)!.sound!.groups;
		// The three shells of the chain, in order — the point of the card is the
		// voice leading, which only exists as a sequence.
		expect(groupsOf('chain:C:737')).toHaveLength(3);
		// Both chords of a transition, and both notes of an interval, melodically.
		expect(groupsOf('vl:C:737:ii-V')).toHaveLength(2);
		expect(groupsOf('ivl:C:P5')).toEqual([[48], [55]]);
		// Single voicings sound as one chord.
		expect(groupsOf('s2n:C:maj7:r3')).toEqual([[48, 52]]);
		expect(groupsOf('rootless:C:maj7:A')).toHaveLength(1);
		expect(groupsOf('rootless:C:maj7:A')[0]).toHaveLength(4);
		// The ear cards are their own prompt: an interval melodically, a quality
		// as one strike, both the same sound the reading drills play on reveal.
		expect(groupsOf('eint:C:P5')).toEqual([[48], [55]]);
		expect(groupsOf('eqal:C:m7')).toEqual([[48, 51, 55, 58]]);
	});

	// Each chord is built from its own root, so without registering the groups
	// against each other a "held" guide tone sounds an octave away from itself
	// and a semitone fall sounds like a major 7th leap — the audio flatly
	// contradicting the rationale printed beside it.
	it('registers each group against the one before it', () => {
		const groupsOf = (id: string) => views.find((v) => v.id === id)!.sound!.groups;
		// F held, C4 down a semitone to B3.
		expect(groupsOf('gtc:C:ii-V')).toEqual([
			[53, 60],
			[53, 59]
		]);
		// B held, F4 falls a semitone to E4 — the rationale's own words.
		expect(groupsOf('gtc:C:V-I')).toEqual([
			[59, 65],
			[59, 64]
		]);
		// "Alternating forms keeps every voice within a step of where it was."
		expect(groupsOf('rlc:C:ii-V:A')).toEqual([
			[53, 57, 60, 64],
			[53, 57, 59, 64]
		]);
		// The 737 chain already lined up, and must be left where it was.
		expect(groupsOf('chain:C:737')).toEqual([
			[50, 60],
			[55, 59],
			[48, 59]
		]);
	});

	it('never leaps a voice further than the harmony does', () => {
		// Voices are compared bottom-up: every one of these cards plays voicings
		// of the same size twice, so voice n of the second group is what voice n
		// of the first turned into.
		//
		// Guide-tone and rootless comping is the drill about voices barely
		// moving, so a whole tone is the whole budget. A shell keeps its root,
		// and roots fall a fifth — that movement is the card, not a mis-register.
		const MAX_MOVE: Record<string, number> = { gtc: 2, rlc: 2, chain: 7, vl: 7 };
		for (const v of views) {
			const limit = MAX_MOVE[v.type];
			if (limit === undefined) continue;
			const groups = v.sound!.groups;
			for (let i = 1; i < groups.length; i++) {
				expect(groups[i]).toHaveLength(groups[i - 1].length);
				for (let voice = 0; voice < groups[i].length; voice++) {
					const move = Math.abs(groups[i][voice] - groups[i - 1][voice]);
					expect(move, `${v.id} voice ${voice} moves ${move} semitones`).toBeLessThanOrEqual(
						limit
					);
				}
			}
		}
	});
});
