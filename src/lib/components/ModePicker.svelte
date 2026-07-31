<script lang="ts">
	/** Answer surface for the modes drill: all seven, always, in scale order. */
	import { MODE_NAMES } from '$lib/music/theory-drills';

	interface Props {
		mode?: string | null;
		disabled?: boolean;
		correct?: string | null;
		/** Fired after a pick lands, for the instant-answer setting. */
		onpick?: () => void;
	}

	let {
		mode = $bindable(null),
		disabled = false,
		correct = null,
		onpick
	}: Props = $props();

	function pick(name: string) {
		mode = name;
		onpick?.();
	}

	function tone(name: string): string {
		if (correct && correct === name) return 'border-sage bg-sage/15 text-sage';
		if (correct && mode === name) return 'border-felt bg-felt/15 text-felt-ink';
		if (mode === name) return 'border-brass bg-brass text-on-brass';
		return 'border-line bg-surface text-ink';
	}
</script>

<div class="no-select">
	<div class="eyebrow mb-1.5">Mode</div>
	<div class="grid grid-cols-2 gap-1.5">
		{#each MODE_NAMES as name (name)}
			<button
				type="button"
				{disabled}
				class="min-h-[44px] border px-1 text-sm font-semibold {tone(name)}"
				data-testid="mode-{name}"
				aria-pressed={mode === name}
				onclick={() => pick(name)}>{name}</button
			>
		{/each}
	</div>
</div>
