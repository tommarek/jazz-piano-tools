/**
 * A tiny synthesised piano.
 *
 * The app works offline and ships no audio assets, so a sampled instrument is
 * out: a usable soundfont is tens of megabytes, and this whole build is smaller
 * than one of them. What is left is to spend the synthesis on the cues the ear
 * actually reads as "piano": a partial series shaped like a struck string, two
 * strings per note beating against each other, a two-stage decay, and
 * brightness that dies away faster than the note does.
 *
 * Everything takes MIDI numbers, never pitch classes — the caller owns the
 * register, so a voicing sounds where it is actually played rather than folded
 * into one octave.
 */

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
			// A PeriodicWave belongs to the context that made it, so the cache
			// cannot outlive one.
			waves = null;
			master = ctx.createGain();
			master.gain.value = 0.5;
			// One shared lowpass takes the fizz off the summed partials; per-note
			// filters shape timbre, this one just keeps a four-note chord civil.
			// Well above where a note's own filter ever opens, so the attack keeps
			// the brightness its envelope gives it.
			const lowpass = ctx.createBiquadFilter();
			lowpass.type = 'lowpass';
			lowpass.frequency.value = 9000;
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
		waves = null;
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

/**
 * Simultaneous notes — a chord or a voicing.
 *
 * @returns whether anything was actually scheduled. See playSequence.
 */
export function playNotes(
	midiNumbers: number[],
	opts: { durationMs?: number; velocity?: number } = {}
): boolean {
	return playSequence([midiNumbers], opts);
}

/**
 * Successive groups: the three chords of a ii–V–I, or the two notes of an
 * interval played melodically. Everything is scheduled on the audio clock in
 * one go, so a busy main thread cannot smear the rhythm.
 *
 * @returns whether voices were scheduled. Callers for whom the sound is a
 * nicety can ignore it, but an ear card's prompt IS the sound — it has to be
 * able to tell "played" from "silently gave up", or it shows a learner a
 * question they cannot hear while insisting it already asked it.
 */
export function playSequence(
	groups: number[][],
	opts: { gapMs?: number; durationMs?: number; velocity?: number } = {}
): boolean {
	initAudio();
	if (!ctx || !master) return false;
	// A suspended context keeps its clock frozen and resumes where it stopped, so
	// notes scheduled now still speak once resume() lands — that is the ordinary
	// first-gesture path. An interrupted one may never come back, and scheduling
	// into a clock that is not advancing rings nothing at all.
	if (ctx.state !== 'running' && ctx.state !== 'suspended') return false;

	const schedule = sequenceSchedule(groups, opts);
	if (schedule.length === 0) return false;

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
		return false;
	}
	return true;
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
 * The partial series of a struck string, as a PeriodicWave.
 *
 * Two things shape it. Partials fall away with height, faster in the treble —
 * a top-octave note is nearly a sine, a bass note is a comb of twenty. And the
 * hammer strikes the string about a seventh of the way along, which cancels the
 * partials that have a node there: the 7th, the 14th. That notch is a large
 * part of why a piano is not an organ, and it costs nothing to write down.
 *
 * One oscillator carries the lot, so a four-note voicing is eight oscillators
 * rather than the dozens an additive bank would need on a phone.
 */
function buildWave(audio: AudioContext, partials: number, rolloff: number): PeriodicWave {
	const real = new Float32Array(partials + 1);
	const imag = new Float32Array(partials + 1);
	for (let n = 1; n <= partials; n++) {
		const strike = Math.abs(Math.sin((n * Math.PI) / 7));
		imag[n] = (strike / n ** rolloff) * Math.exp(-n / (partials * 0.55));
	}
	return audio.createPeriodicWave(real, imag, { disableNormalization: false });
}

/** Bass, middle and treble get their own wave; three per context, built once. */
const WAVE_SHAPES: { maxMidi: number; partials: number; rolloff: number }[] = [
	{ maxMidi: 51, partials: 20, rolloff: 1.15 },
	{ maxMidi: 71, partials: 13, rolloff: 1.35 },
	{ maxMidi: 127, partials: 7, rolloff: 1.6 }
];

let waves: Map<number, PeriodicWave | null> | null = null;

function waveFor(audio: AudioContext, midiNumber: number): PeriodicWave | null {
	const shape = WAVE_SHAPES.find((w) => midiNumber <= w.maxMidi) ?? WAVE_SHAPES[2];
	if (!waves) waves = new Map();
	// `has`, not a truthy read: a context without createPeriodicWave caches its
	// null too, or every note of every chord pays for the same failure again.
	if (waves.has(shape.maxMidi)) return waves.get(shape.maxMidi) ?? null;
	let wave: PeriodicWave | null = null;
	try {
		wave = buildWave(audio, shape.partials, shape.rolloff);
	} catch {
		// No createPeriodicWave (older WebViews): the caller falls back to a plain
		// oscillator, which is duller but still a note.
	}
	waves.set(shape.maxMidi, wave);
	return wave;
}

/**
 * The two strings of a unison, a few cents apart. Real ones are never in
 * perfect tune with each other, and the slow beating that comes of it is most
 * of what stops a held note sounding like a synthesiser. Detuned in opposite
 * directions so the pitch centre stays where the theory engine put it.
 */
const STRINGS: { detune: number; level: number }[] = [
	{ detune: -3, level: 1 },
	{ detune: 4, level: 0.7 }
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
	const wave = waveFor(audio, midiNumber);

	const gain = audio.createGain();
	const tone = audio.createBiquadFilter();
	tone.type = 'lowpass';
	tone.Q.value = 0.7;
	gain.connect(tone);
	tone.connect(dest);

	// Low strings ring longer than high ones — the single cue that most stops a
	// bass note from sounding like a plucked blip next to the chord above it,
	// and the reason a treble note has to get out of the way of the next chord.
	const ring = durationSec * clamp(2.35 - midiNumber / 42, 0.65, 1.7);
	// A hammer takes time to leave a thick string. Sharpening the attack towards
	// the treble is also what keeps the top of a voicing audible as a separate
	// note rather than a swell inside the chord.
	const attack = midiNumber < 48 ? 0.011 : midiNumber < 66 ? 0.007 : 0.004;
	const peak = 0.2 * velocity;
	// Exponential ramps cannot touch zero, hence the near-silent floor.
	// The intrinsic value is set as well as scheduled: until atSec arrives an
	// AudioParam reports the node's default 1.0, and stopAll latches whatever it
	// reports — so a voice cut before its onset would be pinned five times louder
	// than it was ever meant to sound.
	gain.gain.value = 0.0001;
	gain.gain.setValueAtTime(0.0001, atSec);
	gain.gain.exponentialRampToValueAtTime(peak, atSec + attack);
	// Two stages, not one. A struck string dumps its energy fast at first and
	// then hangs on far longer than that rate implies — a single exponential
	// either bangs and vanishes or drones. The knee is the piano.
	gain.gain.exponentialRampToValueAtTime(peak * 0.3, atSec + attack + ring * 0.16);
	gain.gain.exponentialRampToValueAtTime(0.0001, atSec + ring);

	// Brightness dies before the note does: high partials lose their energy
	// first, so a piano is percussive at the front and mellow in the tail.
	// Both ends track the fundamental, which keeps the timbre constant across
	// the keyboard rather than dulling the top octave into a sine. Velocity
	// opens the top the way a harder hammer does.
	const open = Math.min(12000, freq * (7 + 12 * velocity));
	const closed = Math.min(open, Math.max(freq * 2.5, 350));
	tone.frequency.value = open;
	tone.frequency.setValueAtTime(open, atSec);
	tone.frequency.exponentialRampToValueAtTime(closed, atSec + ring * 0.55);

	const voice: Voice = { oscillators: [], gain, startsAt: atSec };
	for (const string of STRINGS) {
		const osc = audio.createOscillator();
		// Without the wave there is nothing to shape a triangle into; it is the
		// closest of the built-ins to a struck string's weak upper partials.
		if (wave) osc.setPeriodicWave(wave);
		else osc.type = 'triangle';
		osc.frequency.value = freq;
		osc.detune.value = string.detune;
		const level = audio.createGain();
		level.gain.value = string.level;
		osc.connect(level);
		level.connect(gain);
		osc.start(atSec);
		osc.stop(atSec + ring + 0.05);
		voice.oscillators.push(osc);
	}
	voice.oscillators[voice.oscillators.length - 1].onended = () => active.delete(voice);
	active.add(voice);
}

function clamp(v: number, min: number, max: number): number {
	return Math.min(max, Math.max(min, v));
}
