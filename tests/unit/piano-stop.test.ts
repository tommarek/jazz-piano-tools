/**
 * Stopping playback, against a stand-in for Web Audio.
 *
 * The bug this pins is invisible to every other test: `AudioParam.value` on a
 * voice whose envelope is only *scheduled* would report the GainNode default of
 * 1.0, so a stopAll() during the gap between two notes could latch full volume
 * onto a note that had not spoken yet — four times the peak the envelope was
 * going to give it. Two things stop it, and both are asserted below: the
 * intrinsic value is floored when the voice is built, and a voice whose onset
 * has not arrived is cut rather than ramped. Node has no AudioContext, so the
 * graph is faked closely enough to observe what is scheduled on it.
 */

import { beforeAll, describe, expect, it } from 'vitest';

class FakeParam {
	/** Defaults to unity exactly as a real GainNode's gain does. */
	value = 1;
	events: { kind: string; value: number; time: number }[] = [];
	setValueAtTime(value: number, time: number) {
		// A real param scheduled into the future leaves `value` alone — which is
		// the whole trap being tested.
		this.events.push({ kind: 'set', value, time });
	}
	exponentialRampToValueAtTime(value: number, time: number) {
		this.events.push({ kind: 'ramp', value, time });
	}
	setTargetAtTime(value: number, time: number) {
		this.events.push({ kind: 'target', value, time });
	}
	cancelScheduledValues(time: number) {
		this.events.push({ kind: 'cancel', value: 0, time });
	}
}

class FakeOscillator {
	type = 'sine';
	frequency = { value: 0 };
	detune = { value: 0 };
	startedAt: number | null = null;
	stops: number[] = [];
	onended: (() => void) | null = null;
	setPeriodicWave() {}
	connect() {}
	start(time: number) {
		this.startedAt = time;
	}
	stop(time: number) {
		this.stops.push(time);
	}
}

const gains: FakeParam[] = [];
const oscillators: FakeOscillator[] = [];

class FakeContext {
	currentTime = 100;
	state = 'running';
	destination = { connect() {} };
	createGain() {
		const param = new FakeParam();
		gains.push(param);
		return { gain: param, connect() {} };
	}
	// The cutoff carries an envelope of its own, so it is a schedulable param —
	// but not one stopAll touches, hence kept out of `gains`.
	createBiquadFilter() {
		return { type: 'lowpass', frequency: new FakeParam(), Q: { value: 0 }, connect() {} };
	}
	createPeriodicWave() {
		return {};
	}
	createOscillator() {
		const osc = new FakeOscillator();
		oscillators.push(osc);
		return osc;
	}
	resume() {}
}

let piano: typeof import('../../src/lib/audio/piano');
let ctx: FakeContext;

beforeAll(async () => {
	ctx = new FakeContext();
	// One shared context, so the module's cached graph is this one.
	(globalThis as unknown as { window: unknown }).window = {
		AudioContext: function () {
			return ctx;
		}
	};
	piano = await import('../../src/lib/audio/piano');
});

describe('stopping a sequence mid-gap', () => {
	it('never latches a not-yet-sounded voice at full volume', () => {
		gains.length = 0;
		oscillators.length = 0;
		// An interval: the second note is 700 ms out, which on an ear card is
		// exactly the window a "Play it again" tap lands in.
		piano.playSequence([[60], [67]], { gapMs: 700 });

		// The master gain is created first; then one gain per voice, each followed
		// by the level gain of each of its two strings — which is why the voices
		// are picked out by their envelope ramp rather than by position.
		const voiceGains = gains.filter((g) => g.events.some((e) => e.kind === 'ramp'));
		expect(voiceGains).toHaveLength(2);
		const pending = voiceGains[1];
		// Scheduled, and floored right now — the second half is what stopAll reads.
		expect(pending.value).toBeCloseTo(0.0001, 6);

		// Half a second in: the first note is ringing, the second has not spoken.
		ctx.currentTime += 0.5;
		const scheduled = pending.events.length;
		piano.stopAll();

		// A voice that has not spoken is cut, not faded, so stopAll writes nothing
		// onto its envelope at all — and the floor above is what the latch would
		// read if that early return ever went. Both halves of the guard, one test.
		expect(pending.events).toHaveLength(scheduled);
	});

	it('cuts a voice that has not started rather than ramping it down', () => {
		gains.length = 0;
		oscillators.length = 0;
		piano.playSequence([[60], [67]], { gapMs: 700 });
		ctx.currentTime += 0.5;
		const now = ctx.currentTime;
		piano.stopAll();

		// Whatever the second note's voice is made of — the count is a synthesis
		// detail, "has not spoken yet" is the property under test.
		const pendingOscillators = oscillators.filter((o) => (o.startedAt ?? 0) > now);
		expect(pendingOscillators.length).toBeGreaterThan(0);
		for (const osc of pendingOscillators) {
			expect(osc.startedAt).toBeGreaterThan(now);
			// Stopped at `now`, not `now + 0.08`: there is nothing to fade.
			expect(Math.min(...osc.stops)).toBeLessThanOrEqual(now);
		}
		// The ringing voice still gets its ramp, because cutting it dead clicks.
		const ringing = gains.filter((g) => g.events.some((e) => e.kind === 'ramp'))[0];
		expect(ringing.events.some((e) => e.kind === 'target')).toBe(true);
	});
});
