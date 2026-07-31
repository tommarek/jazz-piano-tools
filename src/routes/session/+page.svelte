<script lang="ts">
	import { onDestroy } from 'svelte';
	import Keyboard from '$lib/components/Keyboard.svelte';
	import ChordPicker from '$lib/components/ChordPicker.svelte';
	import ModePicker from '$lib/components/ModePicker.svelte';
	import IntervalPicker from '$lib/components/IntervalPicker.svelte';
	import ReferenceSheet from '$lib/components/ReferenceSheet.svelte';
	import ChordSymbol from '$lib/components/ChordSymbol.svelte';
	import VoiceLeading from '$lib/components/VoiceLeading.svelte';
	import { recordReview, endSession } from '$lib/data/review';
	import { median } from '$lib/scheduler/grading';
	import { CARD_TYPE_LABEL } from '$lib/music/cards';
	import { initAudio, isAudioReady, playSequence, stopAll } from '$lib/audio/piano';
	import { deckCounts, type DeckCount, type QueueItem } from '$lib/data/queue';
	import { liveDeckTypes, parseDeckSlug } from '$lib/data/decks';
	import { parseNote, pitchClass } from '$lib/music/theory';
	import type { IntervalName } from '$lib/music/theory';
	import type { Quality } from '$lib/music/voicings';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	/** A speed round is a fixed 60-second sprint, not a card count. */
	const SPEED_DURATION_MS = 60_000;
	/** How long the keyboard stays blank in visualise mode. */
	const VISUALISE_MS = 3000;
	/** Wrong cards come back this many positions later, still inside the session. */
	const REQUEUE_GAP = 4;
	/**
	 * How long Next stays inert after a reveal. It renders exactly where Check
	 * was, so the second half of a double-tap on Check lands on it and would
	 * skip the very feedback the first half asked for — the same accident
	 * giveUp() absorbs in the other direction. Disabled rather than swallowed in
	 * the handler: a button that is inert says so to the platform, and nothing
	 * downstream has to know why its tap did nothing.
	 */
	const ADVANCE_ARM_MS = 300;

	type Phase = 'blank' | 'answer' | 'feedback' | 'done';

	// The queue is fetched once per session and then owned by the client, so
	// capturing it (and the session constants below) at mount is intended.
	// svelte-ignore state_referenced_locally
	let queue = $state<QueueItem[]>([...data.queue]);
	let index = $state(0);
	/** How far the progress bar has got — latched at each deal, see beginCard. */
	let dealtPct = $state(0);
	let phase = $state<Phase>('answer');
	let answered = $state(0);
	let correctCount = $state(0);
	/** Correct attempts only, like every other fluency median in the app (see
	 *  rollUpDay): a fast "No idea" tap is not a fast answer. */
	let correctTimes = $state<number[]>([]);
	/** Where the last miss put its copy back in the queue, so the promise made on
	 *  the reveal is the one requeueCurrent() actually kept. */
	let requeuedAt = $state<number | null>(null);
	/** Surfaced only if writing to the device database actually fails. */
	let saveError = $state<string | null>(null);
	/**
	 * False between answering and the write landing on disk. There is no server
	 * to catch a lost review, so "answered" has to mean "durably stored" — and
	 * this is what lets the tests assert that rather than assume it.
	 */
	let saved = $state(false);
	/** Reference topic showing over the session, or null. */
	let sheetTopic = $state<string | null>(null);
	/** This section's deck counts as they stand at the end — see `switchable`. */
	let freshDecks = $state<DeckCount[] | null>(null);

	// Answer state for the current card
	let stepIndex = $state(0);
	let stepAnswers = $state<number[][]>([]);
	let pickRoot = $state<string | null>(null);
	let pickQuality = $state<Quality | null>(null);
	let pickMode = $state<string | null>(null);
	let pickInterval = $state<IntervalName | null>(null);
	/** Whether this card's sound has actually played — an ear card that could not
	 *  autoplay has to say so, or it reads as a dead card. */
	let heard = $state(false);
	/** Set when a Play tap reached the synth and still produced nothing. An ear
	 *  card has no prompt but its sound, so this is the difference between a
	 *  card the learner can answer and one they can only stare at. */
	let noSound = $state(false);

	/**
	 * Bumped once per dealt card, and what the keyboard's `asking` is keyed on: a
	 * missed card is requeued and — at the tail of a queue, or in a one-card
	 * sprint recycle — comes straight back, so the card id and the step inside it
	 * are identical across the two attempts and a finger still down from the miss
	 * would commit its release into the retry.
	 */
	let dealSeq = $state(0);

	let attemptSeq = 0;
	let lastAdvanceAt = 0;
	/** See ADVANCE_ARM_MS. */
	let advanceArmed = $state(true);
	/** Where focus is put down when the sticky bar swaps under it. */
	let nextButton = $state<HTMLButtonElement | null>(null);
	let promptPanel = $state<HTMLDivElement | null>(null);
	let startedAt = $state(0);
	let clock = $state(Date.now());
	let frozenElapsed = $state(0);
	let lastResult = $state<{
		correct: boolean;
		gaveUp: boolean;
		responseMs: number;
		/** The median *before* this attempt: comparing a time to a median it is
		    already folded into would flatter every answer. */
		previousMedianMs: number | null;
	} | null>(null);

	const sessionStart = Date.now();
	// svelte-ignore state_referenced_locally
	const capMs =
		data.mode === 'speed' ? SPEED_DURATION_MS : data.settings.sessionMinutes * 60_000;
	// A speed round never blanks: the sprint has no room for a visualise pause.
	// svelte-ignore state_referenced_locally
	const blankMs =
		data.mode === 'visualise' ? VISUALISE_MS : data.mode === 'speed' ? 0 : data.settings.visualiseDelayMs;

	const current = $derived(queue[index]);
	const card = $derived(current?.card);
	const expectedSteps = $derived(card?.steps ?? []);
	const activeStep = $derived(expectedSteps[stepIndex]);
	const elapsed = $derived(phase === 'answer' ? clock - startedAt : frozenElapsed);
	const sessionElapsed = $derived(clock - sessionStart);

	const answerReady = $derived.by(() => {
		if (!card) return false;
		if (card.input === 'chord-name') return !!(pickRoot && pickQuality);
		if (card.input === 'quality-name') return !!pickQuality;
		if (card.input === 'mode-name') return !!pickMode;
		if (card.input === 'interval-name') return !!pickInterval;
		return expectedSteps.every((s, i) => (stepAnswers[i]?.length ?? 0) === s.expected.length);
	});

	/**
	 * Cards a single tap finishes. Everything else — a root plus a quality, the
	 * two notes of a guide-tone pair, keys — has a half-made answer that
	 * submitting on the first tap would throw away.
	 */
	const oneTapCard = $derived(
		card?.input === 'quality-name' || card?.input === 'mode-name' || card?.input === 'interval-name'
	);

	/**
	 * Instant answer: the tap that picks is the tap that submits, saving one of
	 * the two taps every one-tap card costs. check() re-reads answerReady rather
	 * than trusting the caller, so a pick that somehow did not land still leaves
	 * the Check button doing the work.
	 */
	function onPick() {
		if (!data.settings.instantAnswer || !oneTapCard || phase !== 'answer') return;
		void check();
	}

	// One ticker for the whole session drives both the per-card bar and the cap.
	const ticker = setInterval(() => (clock = Date.now()), 100);
	let blankTimer: ReturnType<typeof setTimeout> | undefined;
	let advanceTimer: ReturnType<typeof setTimeout> | undefined;
	let armTimer: ReturnType<typeof setTimeout> | undefined;

	function clearTimers() {
		clearInterval(ticker);
		if (blankTimer) clearTimeout(blankTimer);
		blankTimer = undefined;
		if (advanceTimer) clearTimeout(advanceTimer);
		advanceTimer = undefined;
		if (armTimer) clearTimeout(armTimer);
		armTimer = undefined;
	}

	onDestroy(() => {
		clearTimers();
		stopAll();
	});

	/**
	 * What the card sounds like. On everything but an ear card this is only ever
	 * reached from the reveal: hearing the voicing before it is checked would
	 * answer the card for you. On an ear card the sound is the question, so it
	 * also plays on arrival and on demand — replaying is the drill, not a way
	 * round it.
	 */
	function playCardSound() {
		if (!data.settings.soundEnabled) return;
		const groups = card?.sound?.groups;
		if (!groups?.length) return;
		// Autoplay then a tap, or two taps of ♪, would otherwise overdub two
		// copies of the same prompt on top of each other.
		stopAll();
		const firstEarPlay = !!card?.promptIsSound && !heard && phase === 'answer';
		// A chain's three chords need room to be heard as three chords; a single
		// voicing does not, and waiting on it just delays the Next tap.
		const played = playSequence(groups, groups.length > 2 ? { gapMs: 900 } : {});
		// `heard` follows what the synth did, not what we asked it to do: flipping
		// the button to "Play it again" when nothing sounded tells a learner the
		// question was asked when it never was.
		noSound = !played;
		if (!played) return;
		// The first sounding of an ear prompt is often the Play tap, because iOS
		// would not let it autoplay — and the wait for that tap is not thinking
		// time. On the autoplay path this rewrites the same millisecond.
		if (firstEarPlay) {
			startedAt = Date.now();
			clock = startedAt;
		}
		heard = true;
	}

	/**
	 * Sound the prompt of an ear card as it appears.
	 *
	 * iOS only unlocks an AudioContext inside a user gesture, and a session that
	 * opens straight onto an ear card has not had one yet — so readiness is
	 * checked rather than assumed. When it is not ready nothing is played and
	 * nothing is marked heard: the play button below carries the prompt instead,
	 * and its tap both unlocks the context and sounds the card. Once anything
	 * has played, every later ear card autoplays.
	 */
	function autoplayPrompt() {
		if (!card?.promptIsSound || !data.settings.soundEnabled) return;
		initAudio();
		if (!isAudioReady()) return;
		playCardSound();
	}

	function beginCard() {
		if (blankTimer) clearTimeout(blankTimer);
		// Read once per deal rather than continuously: requeueCurrent() lengthens
		// the queue under a miss, and a live index/length would animate the bar
		// backwards at exactly the moment the miss feedback appears. Taken at the
		// deal it only ever grows — (i+1)/(n+1) > i/n for every i < n.
		dealtPct = queue.length ? (index / queue.length) * 100 : 0;
		// The previous card's answer must not ring under the new prompt.
		stopAll();
		stepIndex = 0;
		dealSeq++;
		stepAnswers = expectedSteps.map(() => []);
		pickRoot = null;
		pickQuality = null;
		pickMode = null;
		pickInterval = null;
		heard = false;
		noSound = false;
		lastResult = null;
		saveError = null;
		// Invalidate any in-flight write's token: a late failure from the card we
		// just left must not surface on the card now beginning.
		attemptSeq++;
		frozenElapsed = 0;

		const shouldBlank = blankMs > 0 && card?.input === 'keys';
		if (shouldBlank) {
			phase = 'blank';
			blankTimer = setTimeout(startAnswering, blankMs);
		} else {
			startAnswering();
		}
		// After the clock has started, so the time the prompt takes to sound is
		// inside the response time — which is why the ear targets are looser.
		autoplayPrompt();
	}

	function startAnswering() {
		// The clock starts when the answer surface appears, not when the card does.
		startedAt = Date.now();
		clock = startedAt;
		phase = 'answer';
	}

	function onKeyTap(pc: number) {
		if (!card || card.input !== 'keys' || phase !== 'answer') return;
		const need = activeStep?.expected.length ?? 2;
		const taps = stepAnswers[stepIndex] ?? [];
		// Tapping a selected key clears it; past the required count the oldest
		// selection drops out, so a mis-tap costs one tap rather than a reset.
		const wasFull = taps.length === need;
		const next = taps.includes(pc) ? taps.filter((p) => p !== pc) : [...taps, pc].slice(-need);
		stepAnswers[stepIndex] = next;

		// Auto-advance inside a chain so the three chords flow as one gesture;
		// the chain is still scored and timed as a single unit. Only on the way
		// forward, though: it fires on the tap that COMPLETES a step, and only
		// while the chord after it is still untouched. Going back to correct a
		// finished chord used to hand the next tap to the following one, so the
		// learner edited a chord they thought they had left alone and the chain
		// graded wrong on the step they believed they had just repaired.
		if (
			expectedSteps.length > 1 &&
			!wasFull &&
			next.length === need &&
			stepIndex < expectedSteps.length - 1 &&
			(stepAnswers[stepIndex + 1]?.length ?? 0) === 0
		) {
			stepIndex += 1;
		}
	}

	function sameSet(a: number[], b: number[]): boolean {
		if (a.length !== b.length) return false;
		const sa = [...a].sort((x, y) => x - y);
		const sb = [...b].sort((x, y) => x - y);
		return sa.every((v, i) => v === sb[i]);
	}

	function sameSequence(a: number[], b: number[]): boolean {
		return a.length === b.length && a.every((v, i) => v === b[i]);
	}

	/** Rootless A and B are the same notes in a different order, so ordered
	 *  steps are compared as sequences and everything else as sets. */
	function stepCorrect(step: { expected: number[]; ordered?: boolean }, given: number[]): boolean {
		return step.ordered ? sameSequence(given, step.expected) : sameSet(given, step.expected);
	}

	/**
	 * "No idea" — reveals the answer and the explanation without making you
	 * guess randomly first. It grades as Again, because that is what it is: you
	 * did not recall it. Guessing to see the answer would put a fast, confident-
	 * looking wrong attempt into the response-time data.
	 */
	async function giveUp() {
		if (!card || phase !== 'answer') return;
		// Absorb the second half of a double-tap on Next: it lands where the
		// bottom bar's buttons now sit and would instantly grade the fresh card
		// "Again" as an unintended "No idea". Only a tapped advance arms it — a
		// sprint's automatic one leaves no finger on the screen, and swallowing
		// the first 300ms of every sprint card is a dead button, not a guard.
		if (Date.now() - lastAdvanceAt < ADVANCE_ARM_MS) return;
		const responseMs = Date.now() - startedAt;
		frozenElapsed = responseMs;
		await complete(false, { gaveUp: true }, responseMs, true);
	}

	async function check() {
		if (!card || !answerReady || phase !== 'answer') return;
		const responseMs = Date.now() - startedAt;
		frozenElapsed = responseMs;

		let correct: boolean;
		let answerGiven: unknown;
		if (card.input === 'chord-name') {
			// Pitch class, not spelling — see the note on expectedChord.
			const accepted = card.expectedChord?.alsoAccept ?? [card.expectedChord?.quality];
			correct =
				!!pickRoot &&
				pitchClass(parseNote(pickRoot, 4)) === card.expectedChord?.rootPc &&
				!!pickQuality &&
				accepted.includes(pickQuality);
			answerGiven = { root: pickRoot, quality: pickQuality };
		} else if (card.input === 'quality-name') {
			// The root is shown on the prompt keyboard, so only the quality is graded.
			const accepted = card.expectedChord?.alsoAccept ?? [card.expectedChord?.quality];
			correct = !!pickQuality && accepted.includes(pickQuality);
			answerGiven = { quality: pickQuality };
		} else if (card.input === 'mode-name') {
			correct = pickMode === card.expectedMode;
			answerGiven = { mode: pickMode };
		} else if (card.input === 'interval-name') {
			// The interval alone: the card never showed which note it started from.
			correct = pickInterval === card.expectedInterval;
			answerGiven = { interval: pickInterval };
		} else {
			correct = expectedSteps.every((s, i) => stepCorrect(s, stepAnswers[i] ?? []));
			answerGiven = stepAnswers;
		}

		await complete(correct, answerGiven, responseMs, false);
	}

	async function complete(
		correct: boolean,
		answerGiven: unknown,
		responseMs: number,
		gaveUp: boolean
	) {
		if (!card) return;
		// The write below can still be in flight when the user is already on the
		// next card; everything after the await checks this token so a late
		// result cannot stamp a previous attempt's stats onto the current
		// feedback. A per-attempt counter, not the card id: a requeued miss can
		// put the same id on screen twice in a row.
		const attempt = ++attemptSeq;
		saved = false;
		phase = 'feedback';
		advanceArmed = false;
		armTimer = setTimeout(() => (advanceArmed = true), ADVANCE_ARM_MS);
		// Before the database write: playback is started from the tap that got us
		// here, and iOS only unlocks audio inside that gesture's own task.
		playCardSound();
		// Scheduled before the database write below: the Next button renders the
		// moment the phase flips, and a timer created after the await could be
		// stale — fired into the *following* card and silently skipping it.
		if (data.mode === 'speed') advanceTimer = setTimeout(next, 600);
		answered += 1;
		if (correct) {
			correctCount += 1;
			correctTimes = [...correctTimes, responseMs];
		}
		lastResult = { correct, gaveUp, responseMs, previousMedianMs: null };

		if (!correct) requeueCurrent();

		// Straight to the on-device database. There is no network in this path,
		// so there is nothing to queue and nothing to fail.
		let result: Awaited<ReturnType<typeof recordReview>> | null = null;
		try {
			result = await recordReview({
				cardId: card.id,
				correct,
				responseMs,
				answerGiven,
				sessionId: data.sessionId,
				mode: data.mode,
				ts: Date.now()
			});
			// Only a resolved write may claim durability — a failed one must leave
			// data-saved false so nothing downstream trusts a lost review.
			if (attempt === attemptSeq) saved = true;
		} catch (err) {
			if (attempt === attemptSeq) {
				saveError = err instanceof Error ? err.message : 'Could not save that review';
			}
		}

		if (result && lastResult && attempt === attemptSeq && phase === 'feedback') {
			lastResult = { ...lastResult, previousMedianMs: result.previousMedianMs };
		}
	}

	function requeueCurrent() {
		const item = queue[index];
		const target = Math.min(queue.length, index + REQUEUE_GAP);
		// A copy, not the same object again, and no longer new: by the time the
		// repeat comes round the card has been introduced, answered and written
		// to card_state, so the "new" badge on it would be a lie — and a requeue
		// only ever follows a miss, which is where it reads worst.
		queue = [...queue.slice(0, target), { ...item, isNew: false }, ...queue.slice(target)];
		requeuedAt = target;
	}

	/** The Next button's own entry point — see the guard in giveUp(). */
	function advance() {
		lastAdvanceAt = Date.now();
		next();
	}

	function next() {
		if (advanceTimer) {
			clearTimeout(advanceTimer);
			advanceTimer = undefined;
		}
		if (phase === 'done') return;
		const outOfTime = sessionElapsed >= capMs;
		const outOfCards = index + 1 >= queue.length;
		const hitCap = data.mode !== 'speed' && answered >= data.settings.sessionCardCap;

		// A sprint is time-boxed, not card-boxed: a small automatic pool recycles
		// until the clock runs out instead of ending the round at half time.
		if (data.mode === 'speed' && outOfCards && !outOfTime && queue.length > 0) {
			index = 0;
			beginCard();
			return;
		}

		if (outOfTime || outOfCards || hitCap) {
			finish();
			return;
		}
		index += 1;
		beginCard();
	}

	async function finish() {
		clearTimers();
		phase = 'done';
		try {
			await endSession(data.sessionId, answered);
		} catch {
			// Nothing depends on the session row being closed; reviews are already stored.
		}
		try {
			freshDecks = (await deckCounts(data.section)).stages;
		} catch {
			// The loader's snapshot is stale but readable; a switcher beats none.
		}
	}

	let started = false;
	$effect(() => {
		if (started) return;
		started = true;
		if (queue.length === 0) {
			// finish() rather than a bare phase flip: the sessions row opened by the
			// loader still needs closing even when there was nothing to do.
			void finish();
		} else {
			beginCard();
		}
	});

	// A speed round can run out of time mid-card; end it as soon as it does.
	$effect(() => {
		if (data.mode === 'speed' && phase !== 'done' && sessionElapsed >= capMs) finish();
	});

	/**
	 * Both phase flips destroy the control that was just used — the sticky bar
	 * swaps Check for Next and back — which drops focus onto <body> and restarts
	 * the tab order at the top of the document on every single card. Focus is
	 * put back on the bar's live button, or at the head of the new card, so a
	 * keyboard or switch user stays where they were. Only when it actually fell:
	 * focus that survived the swap is where its owner put it.
	 */
	$effect(() => {
		// Not before Next is armed: focus does not land on a disabled button, and
		// the attempt would be the only one made.
		const landing =
			phase === 'feedback' ? (advanceArmed ? nextButton : null) : phase === 'answer' ? promptPanel : null;
		if (!landing) return;
		const active = document.activeElement;
		if (active && active !== document.body) return;
		landing.focus();
	});

	/**
	 * Right notes, wrong order. Worth calling out: on an ordered card the
	 * revealed keys all go green, which otherwise reads as "you got this".
	 */
	const orderOnlyMiss = $derived(
		phase === 'feedback' &&
			!!lastResult &&
			!lastResult.correct &&
			!lastResult.gaveUp &&
			!!activeStep?.ordered &&
			sameSet(stepAnswers[stepIndex] ?? [], activeStep.expected)
	);

	/**
	 * The other decks of this section, for the summary. The one just drilled is
	 * dropped — offering it again as "another deck" is the one useless row — and
	 * so is anything with no card to deal. A stage counts as the same deck when
	 * the drill just finished is the only live one in it: ear stage 1 is `eint`
	 * and nothing else, and a switch offering the session that just ended under
	 * a different name is exactly the row this filter exists to remove.
	 *
	 * Counted again when the session ends rather than reused from the loader:
	 * the cards just answered are no longer due, and the pre-session snapshot
	 * both printed stale due figures and offered a deck it had itself just
	 * emptied — a row that starts an empty session, which is what the filter is
	 * for. The snapshot stands in until the recount lands.
	 */
	const switchable = $derived(
		(freshDecks ?? data.decks.stages).filter((d) => {
			if (d.slug === data.deckSlug || d.block !== null || d.total === 0) return false;
			const live = liveDeckTypes(parseDeckSlug(d.slug), data.settings);
			return !(data.deck.kind === 'type' && live.length === 1 && live[0] === data.deck.type);
		})
	);

	// Home is the section's own screen. The nav is hidden while drilling, so
	// these two links are the whole way out of a session, and an ear session
	// that ends on the Theory screen has walked the learner across the one line
	// the rest of the app never crosses.
	const home = $derived(data.section === 'ear' ? '/ear' : '/');

	/**
	 * Where the hand is while a progression is being entered: the previous
	 * chord's own taps, ghosted on the keyboard. Only mid-progression and only
	 * while answering — during feedback the keyboard is busy with the reveal.
	 */
	const previousChord = $derived(
		phase === 'answer' && expectedSteps.length > 1 && stepIndex > 0
			? (stepAnswers[stepIndex - 1] ?? [])
			: []
	);

	/**
	 * The reveal's movement graph: every card whose sound is a progression of
	 * same-sized voicings, which is exactly the set voiceLed() registered
	 * (chain, gtc, rlc). Ear cards keep their sound as the question, and a
	 * single voicing has no movement to draw.
	 */
	const movementGroups = $derived.by(() => {
		const g = card?.sound?.groups;
		if (!g || g.length < 2 || card?.promptIsSound) return null;
		const width = g[0].length;
		if (width < 2 || !g.every((group) => group.length === width)) return null;
		return g;
	});

	const movementSymbols = $derived.by(() => {
		if (!card) return [];
		if (expectedSteps.length > 1) return expectedSteps.map((s) => s.symbol);
		// Transition cards carry both chords in the title: "Dm7 → G7".
		if (card.title.includes('→')) return card.title.split(' → ');
		return [];
	});

	/**
	 * Cards whose title steps aside on the reveal.
	 *
	 * The reveal panel, the movement graph and the keyboard together do not fit
	 * a 390×664 phone alongside the prompt, and the prompt is the part that is
	 * already repeated: a progression's chips and the graph's own axis label
	 * every chord, and a diatonic card's rationale opens by restating the
	 * question ("The ii of D♭ is E♭m7"). Everything else keeps its symbol —
	 * a rootless reveal reads "F – A – C – E" and nothing else would say of what.
	 */
	const titleStepsAside = $derived(
		expectedSteps.length > 1 || !!movementGroups || card?.type === 'dia'
	);

	const sessionMedian = $derived(median(correctTimes));
	const baseline = $derived(card?.timeTarget.baseline ?? 4000);
	const barPct = $derived(Math.min(100, (elapsed / (baseline * 2)) * 100));
	const barTone = $derived(
		elapsed > baseline * 2 ? 'bg-felt' : elapsed > baseline ? 'bg-brass' : 'bg-ink'
	);
	const progressPct = $derived(
		data.mode === 'speed' ? Math.min(100, (sessionElapsed / SPEED_DURATION_MS) * 100) : dealtPct
	);
</script>

<svelte:head><title>Session · Comp</title></svelte:head>

{#if phase === 'done'}
	<div class="flex min-h-[70dvh] flex-col justify-center" data-testid="session-summary">
		<h1 class="text-2xl font-bold uppercase" style="font-stretch:118%; letter-spacing:0.14em">
			Session done
		</h1>
		<div class="rule-brass mt-1.5 mb-2"></div>
		<p class="mb-6 text-xs text-muted">
			{data.mode === 'speed' ? 'Speed round' : 'Spaced repetition'}
		</p>

		<!-- Three figures on the ground, divided by rules rather than boxed. -->
		<div class="grid grid-cols-3 divide-x divide-line">
			<div class="pr-3">
				<div class="figure text-3xl" data-testid="summary-answered">{answered}</div>
				<div class="eyebrow mt-1">cards</div>
			</div>
			<div class="px-3">
				<div class="figure text-3xl" class:text-sage={answered > 0}>
					{answered ? `${Math.round((correctCount / answered) * 100)}%` : '—'}
				</div>
				<div class="eyebrow mt-1">correct</div>
			</div>
			<div class="pl-3">
				<div class="figure text-3xl">
					{sessionMedian === null ? '—' : (sessionMedian / 1000).toFixed(1)}
				</div>
				<div class="eyebrow mt-1">median s</div>
			</div>
		</div>

		{#if queue.length === 0}
			<p class="mt-4 text-center text-sm text-muted" data-testid="empty-reason">
				{#if data.mode === 'speed'}
					A speed round runs on cards that are already automatic, and none are yet. Keep going with
					regular spaced-repetition sessions.
				{:else if data.emptyBlock === 'sound'}
					Every card in {data.deckLabel} is a sound and nothing else, and "Play the answer" is
					off — so there was no question to put on the screen. Turn it on in
					<a href="/settings" class="text-brass underline underline-offset-2">Settings</a>.
				{:else if data.emptyBlock}
					{data.deckLabel} has no drill switched on. Turn one back on in
					<a href="/settings" class="text-brass underline underline-offset-2">Settings</a>.
				{:else if data.showDeck}
					<!-- One deck being empty says nothing about the rest, and sending
					     someone away for the day when a mixed session is waiting would
					     be a lie the mixed screen immediately contradicts. -->
					Nothing due in {data.deckLabel}. Another deck may have cards, and
					<a href={home} data-sveltekit-reload class="text-brass underline underline-offset-2"
						>everything due</a
					> is the session that transfers best anyway.
				{:else}
					Nothing was due. Raise new cards per day in Settings if you want more.
				{/if}
			</p>
		{/if}

		<a
			href={home}
			data-sveltekit-reload
			class="eyebrow mt-8 flex min-h-[56px] items-center justify-center rounded-sm bg-brass !text-on-brass"
			style="font-size:0.8125rem"
		>
			Done
		</a>
		<p class="mt-4 text-center text-xs text-muted">
			Now go and play something. This only removes the note-finding.
		</p>

		<!--
			Straight into another deck. The nav is hidden while drilling, so the end
			of a session is the one moment "what next" can be asked without either
			interrupting a card or costing three taps through the home screen. Only
			decks with something to deal are listed: a row that starts an empty
			session is worse than no row.
		-->
		{#if switchable.length > 0}
			<div class="mt-8">
				<div class="rule mb-3"></div>
				<h2 class="eyebrow">Or drill another deck</h2>
				<ul class="mt-2" data-testid="deck-switcher">
					{#each switchable as other (other.slug)}
						<li class="border-t border-line">
							<a
								href="/session?deck={other.slug}"
								data-sveltekit-reload
								class="flex items-baseline gap-3 py-3"
								data-testid="switch-{other.slug}"
							>
								<span class="flex-1 text-sm">
									{other.label}{#if other.ahead}<span class="eyebrow ml-2 !text-[9px]">ahead</span
										>{/if}
								</span>
								<span class="text-xs text-muted">
									{#if other.due > 0}
										<span class="figure text-ink">{other.due}</span> due
									{:else}
										<span class="figure">{other.size}</span> cards
									{/if}
								</span>
							</a>
						</li>
					{/each}
				</ul>
			</div>
		{/if}
	</div>
{:else if card}
	<!-- The chrome to subtract is what <main> actually pads by: --pad-top above
	     and the session's own pb-4 below. A hard 2rem here assumed no notch. -->
	<div class="flex min-h-[calc(100dvh-var(--pad-top)-1rem)] flex-col">
		<!-- Progress + escape hatch. A hairline, not a pill: the session's own
		     position is the quietest thing on the screen. -->
		<div class="mb-5 flex items-center gap-3">
			<!-- Which deck, when it is not the mixed one. A drill-only session looks
			     exactly like a mixed session that happened to deal three of the same
			     type in a row, and those are worth telling apart. -->
			{#if data.showDeck}
				<span class="eyebrow shrink-0 !text-brass" data-testid="session-deck">
					{data.deckLabel}
				</span>
			{/if}
			<div class="h-px flex-1 bg-line">
				<div
					class="h-px bg-brass-deep transition-all"
					style="width: {progressPct}%"
					data-testid="session-progress"
				></div>
			</div>
			<button
				type="button"
				class="eyebrow min-h-[44px] px-1"
				onclick={finish}
				data-testid="end-session">End</button
			>
		</div>

		<!-- Prompt. No card around it — the chord symbol IS the card, set the size
		     a lead sheet would set it, on the ebony ground. It floats in the space
		     the answer surface leaves rather than sitting at the top of it: with
		     the boxes gone, a prompt pinned to the ceiling reads as an accident,
		     and this region is the one that gives way when the reveal needs room. -->
		<!-- tabindex -1: never a tab stop, but where focus is put down when a card
		     begins — see the effect above. -->
		<div
			bind:this={promptPanel}
			tabindex="-1"
			class="flex min-h-0 flex-1 flex-col justify-center text-center"
			data-card-id={card.id}
		>
			<div class="eyebrow" data-testid="card-eyebrow">
				{CARD_TYPE_LABEL[card.type]}{current.isNew ? ' · new' : ''}
			</div>
			{#if !(phase === 'feedback' && titleStepsAside)}
				<div class="mt-2 text-[2.75rem] leading-none font-semibold" data-testid="card-title">
					<ChordSymbol text={card.title} />
				</div>
			{/if}
			<!-- The instruction says what to do, and on the reveal it has been
			     done. Dropping it is the cheapest of the reclaims below and the
			     only one that costs nothing at all. -->
			{#if phase !== 'feedback'}
				<div class="mt-2 text-sm text-muted" data-testid="card-instruction">{card.instruction}</div>
			{/if}

			{#if expectedSteps.length > 1}
				<div class="mt-4 flex justify-center gap-2" data-testid="chain-steps">
					{#each expectedSteps as step, i (step.symbol + i)}
						<!-- During feedback the tabs turn into a per-chord verdict and stay
						     tappable, so the learner can flip the keyboard reveal to the
						     chord they actually missed. The bar over each one is the
						     stave line the nav uses: current, correct, missed. While the
						     keyboard is blanked nothing is current, and the line has to be
						     said explicitly: a chip with no border-color utility falls back
						     to currentColor, i.e. ivory. Which chord is current is a border
						     colour and nothing else on screen, so it is a pressed state as
						     well — the same gap the sr-only verdict fills for the other. -->
						<button
							type="button"
							class="min-h-[44px] flex-1 border-t-2 px-1 pt-1.5 text-sm font-semibold"
							class:border-brass={i === stepIndex && phase !== 'blank'}
							class:border-line={i !== stepIndex || phase === 'blank'}
							class:text-sage={phase === 'feedback' && stepCorrect(step, stepAnswers[i] ?? [])}
							class:text-bad={phase === 'feedback' && !stepCorrect(step, stepAnswers[i] ?? [])}
							class:text-muted={phase !== 'feedback' && i !== stepIndex}
							data-testid="step-{i}"
							data-filled={(stepAnswers[i]?.length ?? 0) === step.expected.length}
							aria-pressed={i === stepIndex && phase !== 'blank'}
							disabled={phase !== 'answer' && phase !== 'feedback'}
							onclick={() => (stepIndex = i)}
						>
							<span class="eyebrow block !text-[9px]">{step.position}</span>
							<ChordSymbol text={step.symbol} size="inline" class="mt-0.5 block" />
							<!-- The verdict is sage against felt and nothing else, and the
							     panel above names the whole chain's correct answer without
							     saying which chord was missed. Said in words too, or the
							     per-chord result exists only in the hue. -->
							{#if phase === 'feedback'}
								<span class="sr-only"
									>— {stepCorrect(step, stepAnswers[i] ?? []) ? 'correct' : 'missed'}</span
								>
							{/if}
						</button>
					{/each}
				</div>
			{/if}
		</div>

		<!-- The timer: a stave line that fills. Ivory while you are inside the
		     target, brass as it runs out, felt once it is gone — a heat ramp, so
		     the cue is legible without a second colour meaning "warning". -->
		{#if phase === 'answer'}
			<div class="mt-5 h-px bg-line" aria-hidden="true">
				<div class="h-px {barTone}" style="width: {barPct}%"></div>
			</div>
		{:else}
			<div class="mt-5 h-px"></div>
		{/if}


		<!-- Feedback -->
		{#if phase === 'feedback' && lastResult}
			<!-- The verdict is a margin mark: a coloured rule down the left edge,
			     the way a teacher rules a bar in the margin of a score. It needs no
			     box, and losing the box is what buys the room the reveal needs. -->
			<div
				class="mb-3 border-l-2 py-2 pr-1 pl-3 {lastResult.correct
					? 'border-sage bg-sage/[0.07]'
					: 'border-felt bg-felt/[0.07]'}"
				role="status"
				data-testid="feedback"
				data-correct={lastResult.correct}
				data-saved={saved}
			>
				<div class="flex items-baseline justify-between">
					<span
						class="eyebrow"
						class:!text-sage={lastResult.correct}
						class:!text-felt-ink={!lastResult.correct}
					>
						{lastResult.correct ? 'Correct' : lastResult.gaveUp ? 'Here it is' : 'Not quite'}
					</span>
					<span class="text-xs text-muted">
						<span class="figure">{(lastResult.responseMs / 1000).toFixed(1)}</span>s
						{#if lastResult.previousMedianMs}
							· median <span class="figure"
								>{(lastResult.previousMedianMs / 1000).toFixed(1)}</span
							>s
						{/if}
					</span>
				</div>
				{#if saveError}
					<p class="mt-1 text-xs text-bad" role="alert" data-testid="save-error">
						Could not save that review: {saveError}
					</p>
				{/if}
				<div class="mt-1.5 text-sm" data-testid="answer-text">
					<ChordSymbol text={card.answerText} size="inline" />
				</div>
				{#if orderOnlyMiss}
					<p class="mt-1 text-xs font-semibold text-brass" data-testid="order-miss">
						Right notes, wrong order — the numbers show the order to play them in.
					</p>
				{/if}
				{#if movementGroups}
					<!-- The rationale, drawn: nearly-flat lines are the voices doing
					     their job. Same registered midi the ♪ button plays, so the two
					     cannot disagree — which is also why the prose is not printed
					     above it here. Both together
					     cost the keyboard its bottom third on a small phone, and the
					     picture is the one that shows all three chords at once. -->
					<div class="mx-auto mt-2 max-w-[300px]" data-testid="voice-leading">
						<VoiceLeading groups={movementGroups} symbols={movementSymbols} />
					</div>
					<!-- The graph costs nothing on screen but says nothing to a screen
					     reader beyond its subject, so the prose it replaces is still
					     read out — otherwise these three drills are the only ones whose
					     reveal carries no reason at all. -->
					<p class="sr-only">{card.rationale}</p>
				{:else}
					<p class="mt-1 text-xs leading-relaxed text-muted">{card.rationale}</p>
				{/if}
				<div class="flex items-center gap-3">
					<button
						type="button"
						class="mt-1 min-h-[44px] text-xs text-brass underline underline-offset-2"
						onclick={() => (sheetTopic = card.topic)}
						data-testid="explain">Explain this →</button
					>
					{#if data.settings.soundEnabled && card.sound}
						<button
							type="button"
							class="mt-1 min-h-[44px] min-w-[44px] border border-line text-base text-brass"
							onclick={playCardSound}
							aria-label="Play it again"
							data-testid="play-again">♪</button
						>
					{/if}
				</div>
				{#if !lastResult.correct}
					<!-- Where the copy actually landed, not REQUEUE_GAP ahead: a short
					     queue clamps the insert to its end, which is nearer than the gap
					     and still inside the session. Only the card cap can cut it off —
					     every card between here and there costs one. A speed miss never
					     touches the schedule, so the srs fallback line would be untrue
					     there — the sprint promise stands on the recycling queue. -->
					{#if data.mode === 'speed'}
						<p class="mt-1 text-xs text-brass">You'll see this one again in this speed round.</p>
					{:else if requeuedAt !== null && answered + (requeuedAt - index - 1) < data.settings.sessionCardCap}
						<p class="mt-1 text-xs text-brass">You'll see this one again before the session ends.</p>
					{:else}
						<p class="mt-1 text-xs text-brass">This one comes back sooner in the schedule.</p>
					{/if}
				{/if}
			</div>
		{/if}

		<!-- Answer surface, in the bottom third for one-thumb use -->
		<div class="mb-3">
			{#if card.promptIsSound && phase !== 'feedback'}
				<!-- The prompt itself. It lives down here with the answer surface
				     rather than up in the prompt panel, because it is tapped — often,
				     and with the same thumb. On reveal it yields its space to the
				     feedback panel, whose own ♪ button replays the same sound. -->
				<div class="mb-3">
					<!-- Still tappable when sound has failed: a device can gain an audio
					     session between one tap and the next, and a button that has gone
					     inert offers a learner nothing to try. -->
					<button
						type="button"
						class="min-h-[64px] w-full border-2 text-base font-semibold {noSound
							? 'border-line text-muted'
							: 'border-brass text-brass'}"
						onclick={playCardSound}
						data-testid="play-prompt"
					>
						<span aria-hidden="true">{noSound ? '🔇' : '▶'}</span>
						{noSound ? 'No sound on this device' : heard ? 'Play it again' : 'Play'}
					</button>
					<p class="mt-1 text-center text-[11px] text-muted" data-testid="prompt-hint">
						{#if noSound}
							This card is only a sound, so there is nothing here to answer. Tap "No idea" to move
							on, or turn Sound off in Settings to drop the ear drills from your deck.
						{:else if heard}
							Play it as often as you like — listening again is the drill.
						{:else}
							Tap to hear it.
						{/if}
					</p>
				</div>
			{/if}

			{#if card.input === 'keys'}
				{#if phase === 'answer' || phase === 'blank'}
					<p class="mb-1.5 text-center text-xs text-muted">
						{#if expectedSteps.length > 1}
							{activeStep?.symbol} — {activeStep?.answerLabel}
						{:else}
							{expectedSteps[0]?.answerLabel ?? ''}
						{/if}
					</p>
				{/if}
				<Keyboard
					asking="{dealSeq}:{stepIndex}"
					selected={stepAnswers[stepIndex] ?? []}
					given={card.given}
					previous={previousChord}
					rootMarker={card.rootGiven ?? null}
					markerLabel={card.givenMarkerLabel}
					reveal={phase === 'feedback' ? (expectedSteps[stepIndex]?.expected ?? []) : []}
					wrong={phase === 'feedback'
						? (stepAnswers[stepIndex] ?? []).filter(
								(pc) => !(expectedSteps[stepIndex]?.expected ?? []).includes(pc)
							)
						: []}
					blanked={phase === 'blank'}
					compact={phase === 'feedback'}
					disabled={phase !== 'answer'}
					orderKeys={activeStep?.ordered
						? phase === 'feedback'
							? activeStep.expected
							: (stepAnswers[stepIndex] ?? [])
						: null}
					onselect={onKeyTap}
				/>
			{:else if card.input === 'quality-name'}
				<!-- The notes are shown, root marked; only the quality is asked, so the
				     keyboard is compact while answering — it is read, never tapped, and
				     at full height the bottom row of quality buttons sat under the
				     sticky bar on a 375dp phone. On the reveal it goes entirely: the
				     prompt has been answered, and the quality verdicts would otherwise
				     fall below the fold. An ear card has no keyboard at all: seeing the
				     notes would be the answer. -->
				{#if phase !== 'feedback' && !card.promptIsSound}
					<div class="mb-3">
						<Keyboard
							given={card.given}
							rootMarker={card.rootGiven ?? null}
							markerLabel={card.givenMarkerLabel}
							compact={true}
							disabled={true}
						/>
					</div>
				{/if}
				<ChordPicker
					hideRoot={true}
					bind:quality={pickQuality}
					onpick={onPick}
					disabled={phase !== 'answer'}
					correct={phase === 'feedback' ? (card.expectedChord ?? null) : null}
				/>
			{:else if card.input === 'chord-name'}
				<!-- `dia` is the only chord-name drill and its question is a numeral over
				     a key, so there are no given notes to show. -->
				<ChordPicker
					bind:root={pickRoot}
					bind:quality={pickQuality}
					disabled={phase !== 'answer'}
					correct={phase === 'feedback' ? (card.expectedChord ?? null) : null}
				/>
			{:else if card.input === 'interval-name'}
				<IntervalPicker
					bind:interval={pickInterval}
					onpick={onPick}
					disabled={phase !== 'answer'}
					correct={phase === 'feedback' ? (card.expectedInterval ?? null) : null}
				/>
			{:else}
				<ModePicker
					bind:mode={pickMode}
					onpick={onPick}
					disabled={phase !== 'answer'}
					correct={phase === 'feedback' ? (card.expectedMode ?? null) : null}
				/>
			{/if}
		</div>

		<!-- Pinned to the bottom of the viewport. The chord picker is two grids of
		     buttons and pushed the answer button clean off a real phone screen;
		     sticky keeps it reachable however tall the answer surface gets. -->
		<div
			class="sticky bottom-0 -mx-4 bg-bg px-4 pt-2 pb-[max(0.5rem,env(safe-area-inset-bottom))]"
		>
			{#if phase === 'feedback'}
				<!-- Not styled as disabled while it is inert: it is unavailable for a
				     third of a second, and a button that flickers grey on every card
				     reads as a fault. -->
				<button
					bind:this={nextButton}
					type="button"
					class="eyebrow min-h-[56px] w-full rounded-sm bg-brass !text-on-brass"
					style="font-size:0.8125rem"
					disabled={!advanceArmed}
					onclick={advance}
					data-testid="next-card">Next</button
				>
			{:else}
				<div class="flex gap-2">
					<button
						type="button"
						class="eyebrow min-h-[56px] shrink-0 rounded-sm border border-line px-4"
						disabled={phase !== 'answer'}
						onclick={giveUp}
						data-testid="give-up">No idea</button
					>
					<button
						type="button"
						class="eyebrow min-h-[56px] flex-1 rounded-sm border transition-colors"
						style="font-size:0.8125rem"
						class:bg-brass={answerReady}
						class:!text-on-brass={answerReady}
						class:border-brass={answerReady}
						class:border-line={!answerReady}
						disabled={!answerReady || phase !== 'answer'}
						onclick={check}
						data-testid="check-answer"
					>
						{#if expectedSteps.length > 1 && !answerReady}
							All three chords
						{:else}
							Check
						{/if}
					</button>
				</div>
			{/if}
		</div>
	</div>
{/if}

<!-- Shown over the session so the queue survives; only reachable once the
     answer is on screen, because looking it up mid-attempt would turn a
     retrieval test into a reading exercise. -->
<ReferenceSheet topicId={sheetTopic} onclose={() => (sheetTopic = null)} />
