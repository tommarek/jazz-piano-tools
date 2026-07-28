/**
 * A tiny synthesised piano.
 *
 * The app ships no binary assets and works offline, so a sampled instrument is
 * out: a usable soundfont is megabytes, and this whole build is smaller than
 * one of them. Three detuned partials through a per-note lowpass get close
 * enough to a felt piano for hearing a voicing, which is all the drills need.
 *
 * Everything takes MIDI numbers, never pitch classes — the caller owns the
 * register, so a voicing sounds where it is actually played rather than folded
 * into one octave.
 */

/** Pitch classes are octave-free; playback is not. C4 = 60. */
export function midiForPitchClass(pitchClass: number, octave = 4): number {
	return (octave + 1) * 12 + pitchClass;
}

export function midiToFreq(midiNumber: number): number {
	return 440 * 2 ** ((midiNumber - 69) / 12);
}

export interface ScheduledGroup {
	notes: number[];
	/** Milliseconds after the sequence starts. */
	atMs: number;
}

/** How long a group rings, and how long after it the next one starts. */
const DEFAULT_DURATION_MS = 1600;
const DEFAULT_GAP_MS = 700;

/**
 * Onset times for a sequence of note groups.
 *
 * Empty groups are dropped rather than given their slot: a silent beat in the
 * middle of a ii–V–I reads as a wrong answer, not as an absent chord.
 */
export function sequenceSchedule(
	groups: number[][],
	opts: { gapMs?: number } = {}
): ScheduledGroup[] {
	const gapMs = opts.gapMs ?? DEFAULT_GAP_MS;
	return groups
		.map((notes) => notes.filter(isPlayableMidi))
		.filter((notes) => notes.length > 0)
		.map((notes, i) => ({ notes, atMs: i * gapMs }));
}

function isPlayableMidi(n: unknown): n is number {
	return typeof n === 'number' && Number.isFinite(n) && n >= 12 && n <= 108;
}

// ---------------------------------------------------------------------------
// The audio graph
// ---------------------------------------------------------------------------

interface Voice {
	oscillators: OscillatorNode[];
	gain: GainNode;
	/** Audio-clock time the voice is scheduled to sound at. */
	startsAt: number;
}

let ctx: AudioContext | null = null;
let master: GainNode | null = null;
const active = new Set<Voice>();

/**
 * Create or wake the audio context. Safe to call on every gesture: iOS and
 * Safari only permit context creation and resume() inside a user gesture, and
 * a context that was running can be suspended or interrupted again by a phone
 * call or a lock screen, so "already initialised" is not the same as "audible".
 */
export function initAudio(): void {
	if (typeof window === 'undefined') return;
	try {
		if (!ctx) {
			const Ctor: typeof AudioContext | undefined =
				window.AudioContext ??
				(window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
			// No Web Audio (older WebViews, some test browsers): stay silent rather
			// than taking the session down over a nicety.
			if (!Ctor) return;
			ctx = new Ctor();
			master = ctx.createGain();
			master.gain.value = 0.6;
			// One shared lowpass takes the fizz off the summed partials; per-note
			// filters shape timbre, this one just keeps a four-note chord civil.
			const lowpass = ctx.createBiquadFilter();
			lowpass.type = 'lowpass';
			lowpass.frequency.value = 6000;
			master.connect(lowpass);
			lowpass.connect(ctx.destination);
			// A context handed back after an interruption does not restart itself,
			// and the next gesture may be an answer tap rather than a Play — so
			// re-arm on the state change rather than waiting to be called again.
			ctx.onstatechange = () => wake();
		}
		wake();
	} catch {
		ctx = null;
		master = null;
	}
}

/**
 * Nudge a context that is not sounding back into life.
 *
 * Not `state === 'suspended'`: WKWebView parks an interrupted context — a phone
 * call, Siri, another app taking the audio session — in a non-standard
 * 'interrupted' state that lib.dom's AudioContextState does not name, so the
 * test has to be written the other way round to compile at all. A rejected
 * resume() means the session is still held elsewhere, which is nothing the
 * caller can act on; the next gesture tries again.
 */
function wake(): void {
	if (!ctx || ctx.state === 'running' || ctx.state === 'closed') return;
	try {
		void ctx.resume()?.catch(() => {});
	} catch {
		// A context torn down between the check and the call.
	}
}

export function isAudioReady(): boolean {
	return ctx !== null && ctx.state === 'running';
}

/** Simultaneous notes — a chord or a voicing. */
export function playNotes(
	midiNumbers: number[],
	opts: { durationMs?: number; velocity?: number } = {}
): void {
	playSequence([midiNumbers], opts);
}

/**
 * Successive groups: the three chords of a ii–V–I, or the two notes of an
 * interval played melodically. Everything is scheduled on the audio clock in
 * one go, so a busy main thread cannot smear the rhythm.
 */
export function playSequence(
	groups: number[][],
	opts: { gapMs?: number; durationMs?: number; velocity?: number } = {}
): void {
	initAudio();
	if (!ctx || !master) return;
	// A suspended context keeps its clock frozen and resumes where it stopped, so
	// notes scheduled now still speak once resume() lands — that is the ordinary
	// first-gesture path. An interrupted one may never come back, and scheduling
	// into a clock that is not advancing rings nothing at all.
	if (ctx.state !== 'running' && ctx.state !== 'suspended') return;

	const schedule = sequenceSchedule(groups, opts);
	if (schedule.length === 0) return;

	const durationSec = (opts.durationMs ?? DEFAULT_DURATION_MS) / 1000;
	const velocity = Math.min(1, Math.max(0.05, opts.velocity ?? 0.8));
	const start = ctx.currentTime + 0.02;

	try {
		for (const group of schedule) {
			for (const note of group.notes) {
				startVoice(ctx, master, note, start + group.atMs / 1000, durationSec, velocity);
			}
		}
	} catch {
		// A scheduling failure mid-chord leaves half a voicing ringing; clear it.
		stopAll();
	}
}

/** Kill everything ringing or scheduled. Safe before init and after teardown. */
export function stopAll(): void {
	if (!ctx) {
		active.clear();
		return;
	}
	const now = ctx.currentTime;
	for (const voice of active) {
		try {
			// A voice that has not sounded yet has nothing to fade out of: cut it
			// where it stands rather than letting the ramp below hold it audible
			// for another 80 ms — long enough for a note 3 ms away to speak.
			if (voice.startsAt > now) {
				for (const osc of voice.oscillators) osc.stop(now);
				continue;
			}
			const g = voice.gain.gain;
			// Latched before cancelling, because cancelScheduledValues drops the
			// decay ramp and reverts the param to the last surviving event — the
			// attack's peak. Without this a half-faded note jumps back to full
			// volume first, which is the very click the ramp below avoids.
			// Not cancelAndHoldAtTime: still missing or prefixed in the WKWebView
			// builds this ships into.
			const held = g.value;
			g.cancelScheduledValues(now);
			g.setValueAtTime(Math.max(held, 0.0001), now);
			// A ramp rather than a cut: stopping a piano note dead is a click.
			g.setTargetAtTime(0.0001, now, 0.015);
			for (const osc of voice.oscillators) osc.stop(now + 0.08);
		} catch {
			// A voice already stopped by its own scheduled end.
		}
	}
	active.clear();
}

/**
 * The partials. A triangle carries the body, a detuned sine underneath gives
 * the beating that keeps a sustained note from sounding synthetic, and a
 * quiet octave above supplies the attack's brightness.
 */
const PARTIALS: { type: OscillatorType; ratio: number; detune: number; level: number }[] = [
	{ type: 'triangle', ratio: 1, detune: 0, level: 1 },
	{ type: 'sine', ratio: 1, detune: -7, level: 0.55 },
	{ type: 'sine', ratio: 2, detune: 5, level: 0.2 }
];

function startVoice(
	audio: AudioContext,
	dest: AudioNode,
	midiNumber: number,
	atSec: number,
	durationSec: number,
	velocity: number
): void {
	const freq = midiToFreq(midiNumber);

	const gain = audio.createGain();
	const tone = audio.createBiquadFilter();
	tone.type = 'lowpass';
	// Brightness tracks velocity the way a real hammer does: a soft note keeps
	// fewer partials. Tracking the fundamental keeps the ratio constant across
	// the keyboard instead of dulling the top octave into a sine.
	tone.frequency.value = Math.min(11000, freq * (4 + 9 * velocity));
	tone.Q.value = 0.6;
	gain.connect(tone);
	tone.connect(dest);

	// Low strings ring longer than high ones — the single cue that most stops a
	// bass note from sounding like a plucked blip next to the chord above it.
	const ring = durationSec * (midiNumber < 60 ? 1.25 : 1);
	const peak = 0.22 * velocity;
	// Exponential ramps cannot touch zero, hence the near-silent floor.
	// The intrinsic value is set as well as scheduled: until atSec arrives an
	// AudioParam reports the node's default 1.0, and stopAll latches whatever it
	// reports — so a voice cut before its onset would be pinned four times louder
	// than it was ever meant to sound.
	gain.gain.value = 0.0001;
	gain.gain.setValueAtTime(0.0001, atSec);
	gain.gain.exponentialRampToValueAtTime(peak, atSec + 0.006);
	gain.gain.exponentialRampToValueAtTime(0.0001, atSec + ring);

	const voice: Voice = { oscillators: [], gain, startsAt: atSec };
	for (const partial of PARTIALS) {
		const osc = audio.createOscillator();
		osc.type = partial.type;
		osc.frequency.value = freq * partial.ratio;
		osc.detune.value = partial.detune;
		const level = audio.createGain();
		level.gain.value = partial.level;
		osc.connect(level);
		level.connect(gain);
		osc.start(atSec);
		osc.stop(atSec + ring + 0.05);
		voice.oscillators.push(osc);
	}
	voice.oscillators[voice.oscillators.length - 1].onended = () => active.delete(voice);
	active.add(voice);
}
