<script lang="ts">
	/**
	 * Answer surface for every chord-name card: diatonic harmony and
	 * notes → symbol both name a chord as root + quality.
	 *
	 * Graded on pitch class rather than spelling — the IV of G♭ is C♭, which is
	 * not on this grid, and marking someone wrong for tapping B would teach the
	 * wrong lesson. The feedback shows the correct spelling.
	 */
	import { CHORD_ROOTS, QUALITIES, QUALITY_SUFFIX } from '$lib/music/voicings';
	import { parseNote, pitchClass, prettyNoteName } from '$lib/music/theory';
	import type { Quality } from '$lib/music/voicings';

	interface Props {
		root?: string | null;
		quality?: Quality | null;
		disabled?: boolean;
		/** Hides the root grid — for cards where the root is already marked on
		 *  the prompt keyboard and asking for it back would be reading. */
		hideRoot?: boolean;
		correct?: { root: string; rootPc: number; quality: Quality; alsoAccept?: Quality[] } | null;
	}

	let {
		root = $bindable(null),
		quality = $bindable(null),
		disabled = false,
		hideRoot = false,
		correct = null
	}: Props = $props();

	const pcOf = (name: string) => pitchClass(parseNote(name, 4));

	function tone(isSelected: boolean, isAnswer: boolean): string {
		if (correct && isAnswer) return 'border-good bg-good/20 text-good';
		if (correct && isSelected) return 'border-bad bg-bad/20 text-bad';
		if (isSelected) return 'border-accent bg-accent-solid text-white';
		return 'border-line bg-surface-2 text-ink';
	}
</script>

<div class="no-select space-y-3">
	{#if !hideRoot}
	<div>
		<div class="mb-1 text-[11px] uppercase tracking-wider text-muted">Root</div>
		<div class="grid grid-cols-6 gap-1.5">
			{#each CHORD_ROOTS as r (r)}
				<button
					type="button"
					{disabled}
					class="min-h-[44px] rounded-lg border text-sm font-semibold {tone(
						root === r,
						correct?.rootPc === pcOf(r)
					)}"
					data-testid="root-{r}"
					aria-pressed={root === r}
					onclick={() => (root = r)}>{prettyNoteName(r)}</button
				>
			{/each}
		</div>
	</div>
	{/if}

	<div>
		<div class="mb-1 text-[11px] uppercase tracking-wider text-muted">Quality</div>
		<div class="grid grid-cols-3 gap-1.5">
			{#each QUALITIES as q (q)}
				<button
					type="button"
					{disabled}
					class="min-h-[44px] rounded-lg border px-1 text-xs font-semibold {tone(
						quality === q,
						(correct?.alsoAccept ?? [correct?.quality]).includes(q)
					)}"
					data-testid="quality-{q}"
					aria-pressed={quality === q}
					onclick={() => (quality = q)}>{QUALITY_SUFFIX[q]}</button
				>
			{/each}
		</div>
	</div>
</div>
