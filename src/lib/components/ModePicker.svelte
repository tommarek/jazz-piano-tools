<script lang="ts">
	/** Answer surface for the modes drill: all seven, always, in scale order. */
	import { MODE_NAMES } from '$lib/music/theory-drills';

	interface Props {
		mode?: string | null;
		disabled?: boolean;
		correct?: string | null;
	}

	let { mode = $bindable(null), disabled = false, correct = null }: Props = $props();

	function tone(name: string): string {
		if (correct && correct === name) return 'border-good bg-good/20 text-good';
		if (correct && mode === name) return 'border-bad bg-bad/20 text-bad';
		if (mode === name) return 'border-accent bg-accent-solid text-white';
		return 'border-line bg-surface-2 text-ink';
	}
</script>

<div class="no-select">
	<div class="mb-1 text-[11px] uppercase tracking-wider text-muted">Mode</div>
	<div class="grid grid-cols-2 gap-1.5">
		{#each MODE_NAMES as name (name)}
			<button
				type="button"
				{disabled}
				class="min-h-[44px] rounded-lg border px-1 text-sm font-semibold {tone(name)}"
				data-testid="mode-{name}"
				aria-pressed={mode === name}
				onclick={() => (mode = name)}>{name}</button
			>
		{/each}
	</div>
</div>
