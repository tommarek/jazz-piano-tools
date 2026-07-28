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
	}

	let { interval = $bindable(null), disabled = false, correct = null }: Props = $props();

	const ORDERED = [...DRILLED_INTERVALS].sort(
		(a, b) => INTERVALS[a].semitones - INTERVALS[b].semitones
	);

	/**
	 * Once the answer is in, the grid has no choices left to offer — only a
	 * verdict to deliver. Showing the two intervals that matter (what you
	 * played, what it was) instead of all eleven is both clearer and what keeps
	 * the reveal on one screen next to a tall feedback panel.
	 */
	const shown = $derived(
		correct ? ORDERED.filter((n) => n === correct || n === interval) : ORDERED
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
		if (correct && correct === name) return 'border-good bg-good/20 text-good';
		if (correct && interval === name) return 'border-bad bg-bad/20 text-bad';
		if (interval === name) return 'border-accent bg-accent-solid text-white';
		return 'border-line bg-surface-2 text-ink';
	}
</script>

<div class="no-select">
	<div class="mb-1 text-[11px] uppercase tracking-wider text-muted">
		{caption}
	</div>
	<!-- Three columns, not two: eleven intervals in two columns is six rows, and
	     with the feedback panel open that pushes the answer off a phone screen. -->
	<div class="grid grid-cols-3 gap-1.5">
		{#each shown as name (name)}
			<button
				type="button"
				{disabled}
				class="min-h-[44px] rounded-lg border px-1 text-xs font-semibold {tone(name)}"
				data-testid="interval-{name}"
				aria-pressed={interval === name}
				onclick={() => (interval = name)}>{INTERVAL_LABEL[name]}</button
			>
		{/each}
	</div>
</div>
