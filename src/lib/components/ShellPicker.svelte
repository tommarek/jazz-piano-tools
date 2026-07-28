<script lang="ts">
	/**
	 * Answer surface for notes → symbol: name the root, then the interval above
	 * it. A full 12 × 5 grid rather than four multiple-choice options, because
	 * picking from a shortlist is recognition and recognition is not the thing
	 * being trained.
	 */
	import { CHORD_ROOTS, GUIDE_INTERVALS, GUIDE_INTERVAL_LABEL } from '$lib/music/voicings';
	import type { GuideInterval } from '$lib/music/voicings';

	interface Props {
		root?: string | null;
		guide?: GuideInterval | null;
		disabled?: boolean;
		correct?: { root: string; guide: GuideInterval } | null;
	}

	let {
		root = $bindable(null),
		guide = $bindable(null),
		disabled = false,
		correct = null
	}: Props = $props();

	function tone(isSelected: boolean, isAnswer: boolean): string {
		if (correct && isAnswer) return 'border-good bg-good/20 text-good';
		if (correct && isSelected) return 'border-bad bg-bad/20 text-bad';
		if (isSelected) return 'border-accent bg-accent-solid text-white';
		return 'border-line bg-surface-2 text-ink';
	}
</script>

<div class="no-select space-y-3">
	<div>
		<div class="mb-1 text-[11px] uppercase tracking-wider text-muted">Root</div>
		<div class="grid grid-cols-6 gap-1.5">
			{#each CHORD_ROOTS as r (r)}
				<button
					type="button"
					{disabled}
					class="min-h-[44px] rounded-lg border text-sm font-semibold {tone(
						root === r,
						correct?.root === r
					)}"
					data-testid="root-{r}"
					aria-pressed={root === r}
					onclick={() => (root = r)}>{r}</button
				>
			{/each}
		</div>
	</div>

	<div>
		<div class="mb-1 text-[11px] uppercase tracking-wider text-muted">Interval above the root</div>
		<div class="grid grid-cols-3 gap-1.5">
			{#each GUIDE_INTERVALS as g (g)}
				<button
					type="button"
					{disabled}
					class="min-h-[44px] rounded-lg border px-1 text-xs font-semibold {tone(
						guide === g,
						correct?.guide === g
					)}"
					data-testid="guide-{g}"
					aria-pressed={guide === g}
					onclick={() => (guide = g)}>{GUIDE_INTERVAL_LABEL[g]}</button
				>
			{/each}
		</div>
	</div>
</div>
