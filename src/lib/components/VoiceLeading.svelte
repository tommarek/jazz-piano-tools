<script lang="ts">
	/**
	 * The movement between chords, drawn.
	 *
	 * The progression drills exist to teach that voices barely move — the 7th
	 * falls a semitone and becomes the 3rd, everything else stays put — and that
	 * claim was only ever made in prose, printed next to a keyboard showing one
	 * chord at a time. Here it is as a picture: one line per voice, near enough
	 * flat to be read as one gesture. Every card that draws this (chain, gtc,
	 * rlc) deals rootless or guide-tone voicings, so every line is a small move
	 * and every line is brass; there is no leaping voice left to contrast with.
	 * The registered midi comes from the same voiceLed() data the audio plays,
	 * so the graph, the sound and the rationale cannot disagree.
	 */

	interface Props {
		/** Registered note groups, voices aligned bottom-up (see cards.ts). */
		groups: number[][];
		/** One label per group, when the caller has them. */
		symbols?: string[];
	}

	let { groups, symbols = [] }: Props = $props();

	const W = 320;
	const H = 104;
	const PX = 26;
	const PT = 14;
	const PB = 26;

	const voices = $derived(groups[0]?.length ?? 0);
	const flat = $derived(groups.flat());
	const lo = $derived(Math.min(...flat));
	const hi = $derived(Math.max(...flat));

	function x(i: number): number {
		return PX + (i * (W - 2 * PX)) / Math.max(1, groups.length - 1);
	}
	function y(midi: number): number {
		return hi === lo ? (PT + H - PB) / 2 : PT + ((hi - midi) * (H - PT - PB)) / (hi - lo);
	}

	/**
	 * Words for the moves the drills are about. A whole tone is the entire
	 * budget every current card spends (pinned in audio.test.ts), so the null is
	 * a guard, not a case: a wider move gets a line and no claim about it.
	 */
	function label(delta: number): string | null {
		const a = Math.abs(delta);
		if (a === 0) return 'held';
		if (a === 1) return '½';
		if (a === 2) return '1';
		return null;
	}

	function points(v: number): string {
		return groups.map((g, i) => `${x(i)},${y(g[v])}`).join(' ');
	}
</script>

<svg
	viewBox="0 0 {W} {H}"
	class="w-full"
	role="img"
	aria-label="How each voice moves between the chords"
>
	{#each Array.from({ length: voices }) as _, v (v)}
		<polyline
			points={points(v)}
			fill="none"
			stroke="var(--color-brass)"
			stroke-width="1.5"
			stroke-linecap="round"
			stroke-linejoin="round"
		/>
		{#each groups as g, i (i)}
			<circle cx={x(i)} cy={y(g[v])} r="2.5" fill="var(--color-brass)" />
		{/each}
		{#each groups as g, i (i)}
			{#if i > 0}
				{@const text = label(g[v] - groups[i - 1][v])}
				{#if text}
					<text
						x={(x(i - 1) + x(i)) / 2}
						y={(y(groups[i - 1][v]) + y(g[v])) / 2 - 5}
						text-anchor="middle"
						font-size="9"
						fill="var(--color-brass)">{text}</text
					>
				{/if}
			{/if}
		{/each}
	{/each}

	{#each groups as _, i (i)}
		{#if symbols[i]}
			<text
				x={x(i)}
				y={H - 6}
				text-anchor="middle"
				font-size="10"
				fill="var(--color-muted)">{symbols[i]}</text
			>
		{/if}
	{/each}
</svg>
