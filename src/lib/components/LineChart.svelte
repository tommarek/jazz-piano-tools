<script lang="ts">
	/**
	 * Single-series line chart with a crosshair tooltip.
	 *
	 * One series, so no legend — the heading names it — and the latest value is
	 * direct-labelled rather than every point carrying a number.
	 */

	interface Point {
		x: string;
		y: number | null;
	}

	interface Props {
		points: Point[];
		/** Formats a y value for the tooltip and the end label. */
		format: (y: number) => string;
		color?: string;
		height?: number;
		/** Optional horizontal reference line, e.g. a target. */
		target?: { value: number; label: string } | null;
		/**
		 * Pins one or both ends of the y-axis; null means fit to the data.
		 * Accuracy passes [null, 1]: padding a proportion up to 101% is a lie,
		 * but pinning the floor to 0 as well squashes a 85–100% series into the
		 * top fifth of the plot and shows nothing.
		 */
		domain?: [number | null, number | null] | null;
		label: string;
		/** Shown instead of the chart when nothing has been recorded yet. */
		emptyLabel?: string;
	}

	let {
		points,
		format,
		color = 'var(--color-accent)',
		height = 120,
		target = null,
		domain = null,
		label,
		emptyLabel = 'No reviews yet.'
	}: Props = $props();

	let width = $state(320);
	let hoverIndex = $state<number | null>(null);

	const PAD = { top: 10, right: 8, bottom: 18, left: 34 };

	const withData = $derived(points.filter((p) => p.y !== null) as { x: string; y: number }[]);

	const bounds = $derived.by(() => {
		const ys = withData.map((p) => p.y);
		if (target) ys.push(target.value);

		let min: number;
		let max: number;
		if (ys.length === 0) {
			[min, max] = [0, 1];
		} else if (Math.min(...ys) === Math.max(...ys)) {
			const v = ys[0];
			[min, max] = [v * 0.9, v * 1.1 || 1];
		} else {
			const lo = Math.min(...ys);
			const hi = Math.max(...ys);
			const pad = (hi - lo) * 0.1;
			// Never pad below zero for non-negative data: "-10%" is not an axis
			// label a response-time or accuracy chart can honestly print.
			[min, max] = [lo >= 0 ? Math.max(0, lo - pad) : lo - pad, hi + pad];
		}

		// A pinned end overrides the fitted one; the other stays fitted.
		if (domain?.[0] !== null && domain?.[0] !== undefined) min = domain[0];
		if (domain?.[1] !== null && domain?.[1] !== undefined) max = domain[1];
		return { min, max };
	});

	const plotW = $derived(Math.max(1, width - PAD.left - PAD.right));
	const plotH = $derived(height - PAD.top - PAD.bottom);

	function xAt(i: number): number {
		const n = Math.max(1, points.length - 1);
		return PAD.left + (i / n) * plotW;
	}
	function yAt(v: number): number {
		const { min, max } = bounds;
		const t = (v - min) / (max - min || 1);
		return PAD.top + (1 - t) * plotH;
	}

	/** Breaks the line at gaps so a missing day is a gap, not an invented value. */
	const segments = $derived.by(() => {
		const out: { i: number; y: number }[][] = [];
		let run: { i: number; y: number }[] = [];
		points.forEach((p, i) => {
			if (p.y === null) {
				if (run.length) out.push(run);
				run = [];
			} else {
				run.push({ i, y: p.y });
			}
		});
		if (run.length) out.push(run);
		return out;
	});

	const last = $derived(withData.at(-1) ?? null);
	const lastIndex = $derived(points.findLastIndex((p) => p.y !== null));
	const hovered = $derived(hoverIndex === null ? null : points[hoverIndex]);

	function onMove(event: PointerEvent) {
		const rect = (event.currentTarget as SVGElement).getBoundingClientRect();
		const x = event.clientX - rect.left;
		const n = Math.max(1, points.length - 1);
		const i = Math.round(((x - PAD.left) / plotW) * n);
		hoverIndex = Math.min(points.length - 1, Math.max(0, i));
	}
</script>

<div class="relative" bind:clientWidth={width}>
	{#if withData.length === 0}
		<!-- An axis fitted to nothing still prints numbers and a target line, and at
		     a glance reads as a measurement that happens to be flat. On a fresh
		     install there is no measurement at all, and every other empty state in
		     the app says so outright rather than drawing furniture around it. -->
		<p
			class="flex items-center justify-center text-xs text-muted"
			style="height: {height}px"
			data-testid="chart-empty"
		>
			{emptyLabel}
		</p>
	{:else}
		<svg
			{width}
			{height}
			viewBox="0 0 {width} {height}"
			role="img"
			aria-label="{label}. {last ? `Latest ${format(last.y)}` : 'No data yet'}"
			onpointermove={onMove}
			onpointerleave={() => (hoverIndex = null)}
			class="touch-none"
		>
			<!-- Recessive grid: three lines, no box -->
			{#each [0, 0.5, 1] as t (t)}
				<line
					x1={PAD.left}
					x2={width - PAD.right}
					y1={PAD.top + t * plotH}
					y2={PAD.top + t * plotH}
					stroke="var(--color-line)"
					stroke-width="1"
				/>
			{/each}

			<text x="2" y={PAD.top + 4} font-size="9" fill="var(--color-muted)">
				{format(bounds.max)}
			</text>
			<text x="2" y={PAD.top + plotH + 4} font-size="9" fill="var(--color-muted)">
				{format(bounds.min)}
			</text>

			{#if target}
				<line
					x1={PAD.left}
					x2={width - PAD.right}
					y1={yAt(target.value)}
					y2={yAt(target.value)}
					stroke="var(--color-muted)"
					stroke-width="1"
					stroke-dasharray="3 3"
				/>
				<!-- Left-anchored: the right edge belongs to the series' end label,
				     and the two collided into an unreadable smudge when both sat there. -->
				<text
					x={PAD.left + 3}
					y={yAt(target.value) - 5}
					font-size="9"
					text-anchor="start"
					fill="var(--color-muted)">{target.label}</text
				>
			{/if}

			{#each segments as seg, si (si)}
				{#if seg.length > 1}
					<path
						d={seg.map((p, k) => `${k === 0 ? 'M' : 'L'}${xAt(p.i)},${yAt(p.y)}`).join(' ')}
						fill="none"
						stroke={color}
						stroke-width="2"
						stroke-linecap="round"
						stroke-linejoin="round"
					/>
				{:else}
					<circle cx={xAt(seg[0].i)} cy={yAt(seg[0].y)} r="2.5" fill={color} />
				{/if}
			{/each}

			{#if hovered && hovered.y !== null && hoverIndex !== null}
				<line
					x1={xAt(hoverIndex)}
					x2={xAt(hoverIndex)}
					y1={PAD.top}
					y2={PAD.top + plotH}
					stroke="var(--color-muted)"
					stroke-width="1"
				/>
				<circle
					cx={xAt(hoverIndex)}
					cy={yAt(hovered.y)}
					r="5"
					fill={color}
					stroke="var(--color-surface)"
					stroke-width="2"
				/>
			{/if}

			{#if last && lastIndex >= 0}
				<circle
					cx={xAt(lastIndex)}
					cy={yAt(last.y)}
					r="4"
					fill={color}
					stroke="var(--color-surface)"
					stroke-width="2"
				/>
			{/if}
		</svg>
	{/if}

	{#if hovered}
		<div
			class="pointer-events-none absolute top-0 rounded-md border border-line bg-surface-2 px-2 py-1 text-[10px] shadow-lg"
			style="left: {Math.min(Math.max(0, xAt(hoverIndex ?? 0) - 40), Math.max(0, width - 90))}px"
			role="status"
		>
			<div class="text-muted">{hovered.x}</div>
			<div class="font-semibold">{hovered.y === null ? 'no reviews' : format(hovered.y)}</div>
		</div>
	{:else if last}
		<div class="absolute right-2 top-0 text-[10px] font-semibold" style="color: {color}">
			{format(last.y)}
		</div>
	{/if}
</div>
