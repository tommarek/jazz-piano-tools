<script lang="ts">
	import { onDestroy } from 'svelte';
	import Keyboard from '$lib/components/Keyboard.svelte';
	import ShellPicker from '$lib/components/ShellPicker.svelte';
	import ChordPicker from '$lib/components/ChordPicker.svelte';
	import ModePicker from '$lib/components/ModePicker.svelte';
	import IntervalPicker from '$lib/components/IntervalPicker.svelte';
	import ReferenceSheet from '$lib/components/ReferenceSheet.svelte';
	import { recordReview, endSession } from '$lib/data/review';
	import { median } from '$lib/scheduler/grading';
	import { CARD_TYPE_LABEL } from '$lib/music/cards';
	import { initAudio, isAudioReady, playSequence, stopAll } from '$lib/audio/piano';
	import type { QueueItem } from '$lib/data/queue';
	import { parseNote, pitchClass } from '$lib/music/theory';
	import type { IntervalName } from '$lib/music/theory';
	import type { GuideInterval, Quality } from '$lib/music/voicings';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	/** A speed round is a fixed 60-second sprint, not a card count. */
	const SPEED_DURATION_MS = 60_000;
	/** How long the keyboard stays blank in visualise mode. */
	const VISUALISE_MS = 3000;
	/** Wrong cards come back this many positions later, still inside the session. */
	const REQUEUE_GAP = 4;

	type Phase = 'blank' | 'answer' | 'feedback' | 'done';

	// The queue is fetched once per session and then owned by the client, so
	// capturing it (and the session constants below) at mount is intended.
	// svelte-ignore state_referenced_locally
	let queue = $state<QueueItem[]>([...data.queue]);
	let index = $state(0);
	let phase = $state<Phase>('answer');
	let answered = $state(0);
	let correctCount = $state(0);
	let times = $state<number[]>([]);
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

	// Answer state for the current card
	let stepIndex = $state(0);
	let stepAnswers = $state<number[][]>([]);
	let pickRoot = $state<string | null>(null);
	let pickGuide = $state<GuideInterval | null>(null);
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

	let attemptSeq = 0;
	let lastAdvanceAt = 0;
	let startedAt = $state(0);
	let clock = $state(Date.now());
	let frozenElapsed = $state(0);
	let lastResult = $state<{
		correct: boolean;
		gaveUp: boolean;
		responseMs: number;
		medianMs: number | null;
		previousMedianMs: number | null;
		mastery: string | null;
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
		if (card.input === 'shell-name') return !!(pickRoot && pickGuide);
		if (card.input === 'chord-name') return !!(pickRoot && pickQuality);
		if (card.input === 'quality-name') return !!pickQuality;
		if (card.input === 'mode-name') return !!pickMode;
		if (card.input === 'interval-name') return !!pickInterval;
		return expectedSteps.every((s, i) => (stepAnswers[i]?.length ?? 0) === s.expected.length);
	});

	// One ticker for the whole session drives both the per-card bar and the cap.
	const ticker = setInterval(() => (clock = Date.now()), 100);
	let blankTimer: ReturnType<typeof setTimeout> | undefined;
	let advanceTimer: ReturnType<typeof setTimeout> | undefined;

	function clearTimers() {
		clearInterval(ticker);
		if (blankTimer) clearTimeout(blankTimer);
		blankTimer = undefined;
		if (advanceTimer) clearTimeout(advanceTimer);
		advanceTimer = undefined;
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
		// The previous card's answer must not ring under the new prompt.
		stopAll();
		stepIndex = 0;
		stepAnswers = expectedSteps.map(() => []);
		pickRoot = null;
		pickGuide = null;
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
		const current = stepAnswers[stepIndex] ?? [];
		// Tapping a selected key clears it; past the required count the oldest
		// selection drops out, so a mis-tap costs one tap rather than a reset.
		const next = current.includes(pc)
			? current.filter((p) => p !== pc)
			: [...current, pc].slice(-need);
		stepAnswers[stepIndex] = next;

		// Auto-advance inside a chain so the three chords flow as one gesture;
		// the chain is still scored and timed as a single unit.
		if (expectedSteps.length > 1 && next.length === need && stepIndex < expectedSteps.length - 1) {
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
		// "Again" as an unintended "No idea".
		if (Date.now() - lastAdvanceAt < 300) return;
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
		if (card.input === 'shell-name') {
			correct = pickRoot === card.expectedShell?.root && pickGuide === card.expectedShell?.guide;
			answerGiven = { root: pickRoot, guide: pickGuide };
		} else if (card.input === 'chord-name') {
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
		// Before the database write: playback is started from the tap that got us
		// here, and iOS only unlocks audio inside that gesture's own task.
		playCardSound();
		// Scheduled before the database write below: the Next button renders the
		// moment the phase flips, and a timer created after the await could be
		// stale — fired into the *following* card and silently skipping it.
		if (data.mode === 'speed') advanceTimer = setTimeout(next, 600);
		answered += 1;
		times = [...times, responseMs];
		if (correct) correctCount += 1;
		lastResult = {
			correct,
			gaveUp,
			responseMs,
			medianMs: null,
			previousMedianMs: null,
			mastery: null
		};

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
			lastResult = {
				...lastResult,
				medianMs: result.medianMs,
				previousMedianMs: result.previousMedianMs,
				mastery: result.mastery
			};
		}

	}

	function requeueCurrent() {
		const item = queue[index];
		const target = Math.min(queue.length, index + REQUEUE_GAP);
		queue = [...queue.slice(0, target), item, ...queue.slice(target)];
	}

	function next() {
		lastAdvanceAt = Date.now();
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

	const sessionMedian = $derived(median(times));
	const baseline = $derived(card?.timeTarget.baseline ?? 4000);
	const barPct = $derived(Math.min(100, (elapsed / (baseline * 2)) * 100));
	const barTone = $derived(
		elapsed > baseline * 2 ? 'bg-bad' : elapsed > baseline ? 'bg-warn' : 'bg-accent'
	);
	const progressPct = $derived(
		data.mode === 'speed'
			? Math.min(100, (sessionElapsed / SPEED_DURATION_MS) * 100)
			: queue.length
				? (index / queue.length) * 100
				: 0
	);
</script>

<svelte:head><title>Session · Voicings</title></svelte:head>

{#if phase === 'done'}
	<div class="flex min-h-[70dvh] flex-col justify-center" data-testid="session-summary">
		<h1 class="mb-1 text-lg font-semibold">Session done</h1>
		<p class="mb-5 text-xs text-muted">
			{data.mode === 'speed' ? 'Speed round' : 'Spaced repetition'}
		</p>

		<div class="grid grid-cols-3 gap-2">
			<div class="rounded-xl border border-line bg-surface p-3 text-center">
				<div class="text-2xl font-bold tabular-nums" data-testid="summary-answered">
					{answered}
				</div>
				<div class="text-[11px] text-muted">cards</div>
			</div>
			<div class="rounded-xl border border-line bg-surface p-3 text-center">
				<div class="text-2xl font-bold tabular-nums" class:text-good={answered > 0}>
					{answered ? `${Math.round((correctCount / answered) * 100)}%` : '—'}
				</div>
				<div class="text-[11px] text-muted">correct</div>
			</div>
			<div class="rounded-xl border border-line bg-surface p-3 text-center">
				<div class="text-2xl font-bold tabular-nums">
					{sessionMedian === null ? '—' : (sessionMedian / 1000).toFixed(1)}
				</div>
				<div class="text-[11px] text-muted">median s</div>
			</div>
		</div>

		{#if queue.length === 0}
			<p class="mt-4 text-center text-sm text-muted" data-testid="empty-reason">
				{#if data.mode === 'speed'}
					A speed round runs on cards that are already automatic, and none are yet. Keep going with
					regular spaced-repetition sessions.
				{:else}
					Nothing was due. Raise new cards per day in Settings if you want more.
				{/if}
			</p>
		{/if}

		<a
			href="/"
			data-sveltekit-reload
			class="mt-6 flex min-h-[56px] items-center justify-center rounded-xl bg-accent-solid text-base font-semibold text-white"
		>
			Done
		</a>
		<p class="mt-4 text-center text-xs text-muted">
			Now go and play something. This only removes the note-finding.
		</p>
	</div>
{:else if card}
	<div class="flex min-h-[calc(100dvh-2rem)] flex-col">
		<!-- Progress + escape hatch -->
		<div class="mb-3 flex items-center gap-3">
			<div class="h-1 flex-1 overflow-hidden rounded-full bg-surface-2">
				<div class="h-full rounded-full bg-accent transition-all" style="width: {progressPct}%"></div>
			</div>
			<button
				type="button"
				class="min-h-[44px] px-2 text-xs text-muted"
				onclick={finish}
				data-testid="end-session">End</button
			>
		</div>

		<!-- Prompt -->
		<div class="rounded-xl border border-line bg-surface p-4 text-center" data-card-id={card.id}>
			<div class="text-[11px] uppercase tracking-wider text-muted">
				{CARD_TYPE_LABEL[card.type]}{current.isNew ? ' · new' : ''}
			</div>
			<div class="mt-1 text-3xl font-bold" data-testid="card-title">{card.title}</div>
			<!-- A sound prompt has nothing to re-read once answered, and its
			     instruction line is the difference between the reveal fitting a
			     small phone and not. -->
			{#if !(card.promptIsSound && phase === 'feedback')}
				<div class="mt-1 text-sm text-muted" data-testid="card-instruction">{card.instruction}</div>
			{/if}

			{#if expectedSteps.length > 1}
				<div class="mt-3 flex justify-center gap-1.5" data-testid="chain-steps">
					{#each expectedSteps as step, i (step.symbol + i)}
						<!-- During feedback the tabs turn into a per-chord verdict and stay
						     tappable, so the learner can flip the keyboard reveal to the
						     chord they actually missed. -->
						<button
							type="button"
							class="min-h-[44px] flex-1 rounded-lg border px-1 text-xs font-semibold"
							class:border-accent={i === stepIndex && phase !== 'blank'}
							class:bg-surface-2={i !== stepIndex}
							class:border-line={i !== stepIndex}
							class:text-good={phase === 'feedback' && stepCorrect(step, stepAnswers[i] ?? [])}
							class:text-bad={phase === 'feedback' && !stepCorrect(step, stepAnswers[i] ?? [])}
							data-testid="step-{i}"
							data-filled={(stepAnswers[i]?.length ?? 0) === step.expected.length}
							disabled={phase !== 'answer' && phase !== 'feedback'}
							onclick={() => (stepIndex = i)}
						>
							<span class="block text-[10px] text-muted">{step.position}</span>
							{step.symbol}
						</button>
					{/each}
				</div>
			{/if}
		</div>

		<!-- Timer bar: the desirable-difficulty cue -->
		{#if phase === 'answer'}
			<div class="mt-3 h-1.5 overflow-hidden rounded-full bg-surface-2" aria-hidden="true">
				<div class="h-full rounded-full {barTone}" style="width: {barPct}%"></div>
			</div>
		{:else}
			<div class="mt-3 h-1.5"></div>
		{/if}

		<div class="flex-1"></div>

		<!-- Feedback -->
		{#if phase === 'feedback' && lastResult}
			<div
				class="mb-3 rounded-xl border p-3 {lastResult.correct
					? 'border-good bg-good/10'
					: 'border-bad bg-bad/10'}"
				role="status"
				data-testid="feedback"
				data-correct={lastResult.correct}
				data-saved={saved}
			>
				<div class="flex items-baseline justify-between">
					<span
						class="text-sm font-semibold"
						class:text-good={lastResult.correct}
						class:text-bad={!lastResult.correct}
					>
						{lastResult.correct ? 'Correct' : lastResult.gaveUp ? 'Here it is' : 'Not quite'}
					</span>
					<span class="text-xs tabular-nums text-muted">
						{(lastResult.responseMs / 1000).toFixed(1)}s
						{#if lastResult.previousMedianMs}
							· median {(lastResult.previousMedianMs / 1000).toFixed(1)}s
						{/if}
					</span>
				</div>
				{#if saveError}
					<p class="mt-1 text-xs text-bad" role="alert" data-testid="save-error">
						Could not save that review: {saveError}
					</p>
				{/if}
				<div class="mt-1 text-sm" data-testid="answer-text">{card.answerText}</div>
				{#if orderOnlyMiss}
					<p class="mt-1 text-xs font-semibold text-warn" data-testid="order-miss">
						Right notes, wrong order — the numbers show the order to play them in.
					</p>
				{/if}
				<p class="mt-1 text-xs text-muted">{card.rationale}</p>
				<div class="flex items-center gap-3">
					<button
						type="button"
						class="mt-2 min-h-[44px] text-xs text-accent underline"
						onclick={() => (sheetTopic = card.topic)}
						data-testid="explain">Explain this →</button
					>
					{#if data.settings.soundEnabled && card.sound}
						<button
							type="button"
							class="mt-2 min-h-[44px] min-w-[44px] rounded-lg border border-line text-base text-accent"
							onclick={playCardSound}
							aria-label="Play it again"
							data-testid="play-again">♪</button
						>
					{/if}
				</div>
				{#if !lastResult.correct}
					<!-- The requeued copy sits REQUEUE_GAP ahead; only promise it when the
					     card cap cannot cut the session off before it comes around. A speed
					     miss never touches the schedule, so the srs fallback line would be
					     untrue there — the sprint promise stands on the recycling queue. -->
					{#if data.mode === 'speed'}
						<p class="text-xs text-warn">You'll see this one again in this speed round.</p>
					{:else if answered + REQUEUE_GAP <= Math.min(queue.length, data.settings.sessionCardCap)}
						<p class="text-xs text-warn">You'll see this one again before the session ends.</p>
					{:else}
						<p class="text-xs text-warn">This one comes back sooner in the schedule.</p>
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
						class="min-h-[64px] w-full rounded-xl border bg-surface-2 text-base font-semibold {noSound
							? 'border-line text-muted'
							: 'border-accent text-accent'}"
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
							{activeStep?.symbol} — {activeStep?.shellLabel}
						{:else}
							{expectedSteps[0]?.shellLabel ?? ''}
						{/if}
					</p>
				{/if}
				<Keyboard
					selected={stepAnswers[stepIndex] ?? []}
					given={card.given}
					rootMarker={card.rootGiven ?? null}
					markerLabel={card.givenMarkerLabel}
					reveal={phase === 'feedback' ? (expectedSteps[stepIndex]?.expected ?? []) : []}
					wrong={phase === 'feedback'
						? (stepAnswers[stepIndex] ?? []).filter(
								(pc) => !(expectedSteps[stepIndex]?.expected ?? []).includes(pc)
							)
						: []}
					blanked={phase === 'blank'}
					disabled={phase !== 'answer'}
					orderKeys={activeStep?.ordered
						? phase === 'feedback'
							? activeStep.expected
							: (stepAnswers[stepIndex] ?? [])
						: null}
					onselect={onKeyTap}
				/>
			{:else if card.input === 'shell-name'}
				<!-- The notes are shown on a keyboard, not spelled out: naming them
				     is the answer, so printing them would give it away. -->
				<div class="mb-3">
					<Keyboard
						given={card.given}
						rootMarker={card.rootGiven ?? null}
						markerLabel={card.givenMarkerLabel}
						disabled={true}
					/>
				</div>
				<ShellPicker
					bind:root={pickRoot}
					bind:guide={pickGuide}
					disabled={phase !== 'answer'}
					correct={phase === 'feedback' ? (card.expectedShell ?? null) : null}
				/>
			{:else if card.input === 'quality-name'}
				<!-- The notes are shown, root marked; only the quality is asked. The
				     keyboard yields its space to the feedback panel on reveal — with
				     both visible the quality verdicts fall below the fold. An ear card
				     has no keyboard at all: seeing the notes would be the answer. -->
				{#if phase !== 'feedback' && !card.promptIsSound}
					<div class="mb-3">
						<Keyboard
							given={card.given}
							rootMarker={card.rootGiven ?? null}
							markerLabel={card.givenMarkerLabel}
							disabled={true}
						/>
					</div>
				{/if}
				<ChordPicker
					hideRoot={true}
					bind:quality={pickQuality}
					disabled={phase !== 'answer'}
					correct={phase === 'feedback' ? (card.expectedChord ?? null) : null}
				/>
			{:else if card.input === 'chord-name'}
				{#if card.given.length > 0}
					<!-- The notes are shown on a keyboard, not spelled out: reading them
					     is part of the question, so printing them would give it away. -->
					<div class="mb-3">
						<Keyboard
							given={card.given}
							rootMarker={card.rootGiven ?? null}
							markerLabel={card.givenMarkerLabel}
							disabled={true}
						/>
					</div>
				{/if}
				<ChordPicker
					bind:root={pickRoot}
					bind:quality={pickQuality}
					disabled={phase !== 'answer'}
					correct={phase === 'feedback' ? (card.expectedChord ?? null) : null}
				/>
			{:else if card.input === 'interval-name'}
				<IntervalPicker
					bind:interval={pickInterval}
					disabled={phase !== 'answer'}
					correct={phase === 'feedback' ? (card.expectedInterval ?? null) : null}
				/>
			{:else}
				<ModePicker
					bind:mode={pickMode}
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
				<button
					type="button"
					class="min-h-[56px] w-full rounded-xl bg-accent-solid text-base font-semibold text-white"
					onclick={next}
					data-testid="next-card">Next</button
				>
			{:else}
				<div class="flex gap-2">
					<button
						type="button"
						class="min-h-[56px] shrink-0 rounded-xl border border-line px-4 text-sm font-semibold text-muted"
						disabled={phase !== 'answer'}
						onclick={giveUp}
						data-testid="give-up">No idea</button
					>
					<button
						type="button"
						class="min-h-[56px] flex-1 rounded-xl text-base font-semibold transition-colors"
						class:bg-accent-solid={answerReady}
						class:text-white={answerReady}
						class:bg-surface-2={!answerReady}
						class:text-muted={!answerReady}
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
