/**
 * Playback reporting whether it actually sounded anything.
 *
 * An ear card's prompt IS the sound: there is nothing else on the screen to
 * answer from. The session screen flips the button to "Play it again" off this
 * return value, so a `true` where nothing rang leaves a learner staring at a
 * card that insists it already asked a question they never heard. Node has no
 * Web Audio, so each way of not having it is faked — closely enough that the
 * module cannot tell the difference.
 */

import { afterEach, describe, expect, it, vi } from 'vitest';

/** The minimum graph piano.ts touches, doing nothing audible. */
function fakeContext(state: string) {
	const param = {
		value: 1,
		setValueAtTime() {},
		exponentialRampToValueAtTime() {},
		setTargetAtTime() {},
		cancelScheduledValues() {}
	};
	return {
		state,
		currentTime: 0,
		destination: { connect() {} },
		createGain: () => ({ gain: { ...param }, connect() {} }),
		createBiquadFilter: () => ({
			type: 'lowpass',
			frequency: { value: 0 },
			Q: { value: 0 },
			connect() {}
		}),
		createOscillator: () => ({
			type: 'sine',
			frequency: { value: 0 },
			detune: { value: 0 },
			onended: null,
			connect() {},
			start() {},
			stop() {}
		}),
		resume: () => Promise.resolve()
	};
}

/** Fresh module per case: piano.ts caches one context for the page's lifetime. */
async function loadPiano(windowValue: unknown) {
	vi.resetModules();
	(globalThis as unknown as { window: unknown }).window = windowValue;
	return import('../../src/lib/audio/piano');
}

afterEach(() => {
	delete (globalThis as unknown as { window?: unknown }).window;
});

describe('playback reports what it actually did', () => {
	it('says no when there is no AudioContext to be had', async () => {
		// Older WebViews and some test browsers simply do not carry Web Audio.
		const piano = await loadPiano({});
		expect(piano.playSequence([[60], [67]])).toBe(false);
		expect(piano.playNotes([60, 64, 67])).toBe(false);
		expect(piano.isAudioReady()).toBe(false);
	});

	it('says no when the context cannot be constructed', async () => {
		const piano = await loadPiano({
			AudioContext: function () {
				throw new Error('no audio session');
			}
		});
		expect(piano.playSequence([[60], [67]])).toBe(false);
		expect(piano.isAudioReady()).toBe(false);
	});

	it("says no for WebKit's 'interrupted' context, which never sounds", async () => {
		// A phone call or Siri parks the context here. Unlike 'suspended' it may
		// never come back, and its clock is not advancing — anything scheduled on
		// it is scheduled into silence.
		const ctx = fakeContext('interrupted');
		const piano = await loadPiano({ AudioContext: function () { return ctx; } });
		expect(piano.playSequence([[60], [67]])).toBe(false);
		expect(piano.isAudioReady()).toBe(false);
	});

	it('says no when there is nothing playable in the groups', async () => {
		const ctx = fakeContext('running');
		const piano = await loadPiano({ AudioContext: function () { return ctx; } });
		expect(piano.playSequence([])).toBe(false);
		expect(piano.playSequence([[], [Number.NaN]])).toBe(false);
	});

	it('says yes on a running context, and on the suspended one iOS hands back', async () => {
		// Without these the `false` above would be worthless: a function that
		// always says no is not reporting anything.
		const running = fakeContext('running');
		const piano = await loadPiano({ AudioContext: function () { return running; } });
		expect(piano.playSequence([[60], [67]])).toBe(true);
		expect(piano.playNotes([60, 64, 67])).toBe(true);

		// A suspended context's clock is frozen but resumes where it stopped, so
		// notes scheduled now still speak once the first gesture lands. That is
		// the ordinary iOS path, not a failure.
		const suspended = fakeContext('suspended');
		const gated = await loadPiano({ AudioContext: function () { return suspended; } });
		expect(gated.playSequence([[60], [67]])).toBe(true);
		expect(gated.isAudioReady()).toBe(false);
	});
});
