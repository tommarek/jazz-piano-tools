<script lang="ts">
	/**
	 * A one-octave piano used as the answer surface.
	 *
	 * One octave rather than two on purpose: answers are graded on pitch class,
	 * and seven white keys is what fits a phone at a comfortable tap size. Two
	 * octaves would put white keys at ~26px on a 375px screen.
	 *
	 * White keys are labelled; black keys are not, because labelling them would
	 * hand over the Db-versus-C# decision the drill is meant to train.
	 */

	interface Props {
		/** Controlled: the parent owns the answer and decides what a tap does. */
		selected?: number[];
		/** Context notes shown lit but not selectable (the chord you're moving from). */
		given?: number[];
		/** Marks which given note is the root, so the prompt is unambiguous. */
		rootMarker?: number | null;
		/** Text shown on the marked key; guide-tone cards mark the 3rd, not a root. */
		markerLabel?: string;
		/** Correct answer, revealed after checking. */
		reveal?: number[];
		/** Selections that were wrong, shown after checking. */
		wrong?: number[];
		disabled?: boolean;
		/** Visualise-then-place: the keyboard is present but not shown yet. */
		blanked?: boolean;
		/**
		 * Pitch classes to number 1..n, for voicings where the order *is* the
		 * answer. While answering this is what you tapped; on reveal it is the
		 * correct order, because "you played these four notes in the wrong
		 * sequence" is useless feedback without showing the right sequence.
		 */
		orderKeys?: number[] | null;
		onselect?: (pitchClass: number) => void;
	}

	let {
		selected = [],
		given = [],
		rootMarker = null,
		markerLabel = 'R',
		reveal = [],
		wrong = [],
		disabled = false,
		blanked = false,
		orderKeys = null,
		onselect
	}: Props = $props();

	/** 1-based position of a pitch class in the numbered sequence, or null. */
	function orderOf(pc: number): number | null {
		if (!orderKeys) return null;
		const i = orderKeys.indexOf(pc);
		return i === -1 ? null : i + 1;
	}

	const WHITE = [
		{ pc: 0, letter: 'C' },
		{ pc: 2, letter: 'D' },
		{ pc: 4, letter: 'E' },
		{ pc: 5, letter: 'F' },
		{ pc: 7, letter: 'G' },
		{ pc: 9, letter: 'A' },
		{ pc: 11, letter: 'B' }
	];

	// `slot` is the index of the white key the black key sits after.
	const BLACK = [
		{ pc: 1, slot: 1, name: 'C sharp / D flat' },
		{ pc: 3, slot: 2, name: 'D sharp / E flat' },
		{ pc: 6, slot: 4, name: 'F sharp / G flat' },
		{ pc: 8, slot: 5, name: 'G sharp / A flat' },
		{ pc: 10, slot: 6, name: 'A sharp / B flat' }
	];

	function toggle(pc: number) {
		if (disabled || blanked) return;
		onselect?.(pc);
	}

	function stateOf(pc: number): string {
		if (reveal.includes(pc)) return 'reveal';
		if (wrong.includes(pc)) return 'wrong';
		if (selected.includes(pc)) return 'selected';
		if (given.includes(pc)) return 'given';
		return '';
	}
</script>

{#if blanked}
	<!-- Motor imagery: the keys are not rendered at all, so there is nothing to
	     read off the screen while you picture the shape. -->
	<div
		class="-mx-4 flex h-[190px] items-center justify-center rounded-md border border-dashed border-line bg-surface-2 text-sm text-muted"
		data-testid="keyboard"
		data-blanked="true"
	>
		See it in your head…
	</div>
{:else}
<!-- Full-bleed: seven 44px keys need more width than the page padding leaves on
     a 320dp phone, and the last key was being clipped off the screen. -->
<div
	class="no-select relative -mx-4 touch-manipulation"
	data-testid="keyboard"
	data-blanked="false"
>
	<div class="flex h-[190px] w-full gap-[2px]">
		{#each WHITE as key (key.pc)}
			{@const s = stateOf(key.pc)}
			<button
				type="button"
				class="key-white relative flex-1 rounded-b-md border border-line pb-2 text-center align-bottom text-xs font-semibold transition-colors"
				class:is-selected={s === 'selected'}
				class:is-given={s === 'given'}
				class:is-reveal={s === 'reveal'}
				class:is-wrong={s === 'wrong'}
				data-pc={key.pc}
				data-state={s}
				aria-pressed={selected.includes(key.pc)}
				aria-label={key.letter}
				{disabled}
				onclick={() => toggle(key.pc)}
			>
				<!-- Badges sit above the letter, not at the top: the top half of a
				     white key is covered by its neighbouring black keys, which made
				     the order numbers unreadable on exactly the cards that need them. -->
				{#if rootMarker === key.pc}
					<span class="absolute inset-x-0 bottom-7 text-[10px] font-bold" aria-hidden="true"
						>{markerLabel}</span
					>
				{:else if orderOf(key.pc)}
					<span
						class="absolute inset-x-0 bottom-7 text-[11px] font-bold"
						data-order={orderOf(key.pc)}>{orderOf(key.pc)}</span
					>
				{/if}
				<span class="absolute inset-x-0 bottom-2">{key.letter}</span>
			</button>
		{/each}
	</div>

	{#each BLACK as key (key.pc)}
		{@const s = stateOf(key.pc)}
		<button
			type="button"
			class="key-black absolute top-0 h-[118px] w-[44px] rounded-b-md border border-black transition-colors"
			class:is-selected={s === 'selected'}
			class:is-given={s === 'given'}
			class:is-reveal={s === 'reveal'}
			class:is-wrong={s === 'wrong'}
			style="left: calc((100% / 7) * {key.slot} - 22px)"
			data-pc={key.pc}
			data-state={s}
			aria-pressed={selected.includes(key.pc)}
			aria-label={key.name}
			{disabled}
			onclick={() => toggle(key.pc)}
		>
			{#if rootMarker === key.pc}
				<!-- Inherits the key's ink: the root marker only appears on given keys,
				     whose amber fill needs dark text, not the black key's white. -->
				<span class="absolute inset-x-0 bottom-2 text-[10px] font-bold" aria-hidden="true"
					>{markerLabel}</span
				>
			{:else if orderOf(key.pc)}
				<span
					class="absolute inset-x-0 bottom-2 text-[11px] font-bold text-white"
					data-order={orderOf(key.pc)}>{orderOf(key.pc)}</span
				>
			{/if}
		</button>
	{/each}
</div>
{/if}

<style>
	.key-white {
		background: #f3f4f6;
		color: #111827;
		min-width: 44px;
	}
	.key-white:active {
		background: #dcdfe4;
	}
	.key-black {
		background: #14161d;
		color: #f3f4f6;
		z-index: 10;
	}
	.key-black:active {
		background: #303543;
	}

	.is-selected {
		background: var(--color-accent-solid);
		color: #ffffff;
		border-color: var(--color-accent-solid);
	}
	/* Amber, not gray: these keys carry the question, and gray reads as
	   "disabled" — the opposite of "start here". Amber is a hue none of the
	   answer states use, stays distinct from the blue of the user's own taps
	   under red–green colorblindness, and renders identically on white and
	   black keys. Dark ink for contrast on the bright fill. */
	.is-given {
		background: var(--color-warn);
		color: #3b2f06;
		border-color: var(--color-warn);
	}
	.is-reveal {
		background: var(--color-good);
		color: #06240f;
		border-color: var(--color-good);
	}
	.is-wrong {
		background: var(--color-bad);
		/* Dark ink, because the accessible red is light enough that white on it
		   would not clear AA. */
		color: #3f0d0d;
		border-color: var(--color-bad);
	}

	button:disabled {
		cursor: default;
	}
</style>
