<script lang="ts">
	/**
	 * Answer surface for the interval ear drill: all eleven drilled intervals,
	 * always, so the answer is generated rather than picked from a shortlist.
	 *
	 * Laid out by size rather than in the order the scheduler introduces them.
	 * The grid then reads as a ruler, and a near miss lands next to the right
	 * answer instead of across the grid from it.
	 */
	import { DRILLED_INTERVALS } from '$lib/music/theory-drills';
	import { INTERVALS, INTERVAL_LABEL } from '$lib/music/theory';
	import type { IntervalName } from '$lib/music/theory';

	interface Props {
		interval?: IntervalName | null;
		disabled?: boolean;
		correct?: IntervalName | null;
		/** Fired after a pick lands, for the instant-answer setting. */
		onpick?: () => void;
	}

	let {
		interval = $bindable(null),
		disabled = false,
		correct = null,
		onpick
	}: Props = $props();

	function pick(name: IntervalName) {
		interval = name;
		onpick?.();
	}

	const ORDERED = [...DRILLED_INTERVALS].sort(
		(a, b) => INTERVALS[a].semitones - INTERVALS[b].semitones
	);

	/**
	 * Once the answer is in, the grid has no choices left to offer — only a
	 * verdict to deliver. Showing the two intervals that matter (what you
	 * played, what it was) instead of all eleven is both clearer and what keeps
	 * the reveal on one screen next to a tall feedback panel.
	 *
	 * Played first, then the answer — the order the caption below promises.
	 * Filtering the size-ordered list put them the other way round whenever the
	 * mistake was the larger interval, so "You played · it was" was true only
	 * about half the time.
	 */
	const shown = $derived(
		correct
			? [interval, correct].filter(
					(n, i, all): n is IntervalName => n !== null && all.indexOf(n) === i
				)
			: ORDERED
	);

	/**
	 * Three cases, not two: after "No idea" there is no answer to contrast the
	 * right one with, and captioning a lone green button "You played · it was"
	 * tells the learner they played something they never touched.
	 */
	const caption = $derived.by(() => {
		if (!correct) return 'Interval';
		if (!interval) return 'It was';
		return correct === interval ? 'Interval' : 'You played · it was';
	});

	function tone(name: IntervalName): string {
		if (correct && correct === name) return 'border-sage bg-sage/15 text-sage';
		if (correct && interval === name) return 'border-felt bg-felt/15 text-felt-ink';
		if (interval === name) return 'border-brass bg-brass text-on-brass';
		return 'border-line bg-surface text-ink';
	}
</script>

<div class="no-select">
	<div class="eyebrow mb-1.5">
		{caption}
	</div>
	<!-- Three columns, not two: eleven intervals in two columns is six rows, and
	     with the feedback panel open that pushes the answer off a phone screen. -->
	<div class="grid grid-cols-3 gap-1.5">
		{#each shown as name (name)}
			<button
				type="button"
				{disabled}
				class="min-h-[44px] border px-1 text-xs font-semibold {tone(name)}"
				data-testid="interval-{name}"
				aria-pressed={interval === name}
				onclick={() => pick(name)}>{INTERVAL_LABEL[name]}</button
			>
		{/each}
	</div>
</div>
