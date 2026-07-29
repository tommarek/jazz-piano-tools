<script lang="ts">
	import LineChart from '$lib/components/LineChart.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	// Mastery is an ordered state, not a set of arbitrary series, so it reads as
	// grey → blue → green. Every swatch is labelled, so colour never carries the
	// meaning on its own.
	const MASTERY = [
		{ key: 'automatic', label: 'Automatic', color: '#1ea854' },
		{ key: 'familiar', label: 'Familiar', color: '#4f8cff' },
		{ key: 'new', label: 'Learning', color: '#8b8fa3' },
		{ key: 'unseen', label: 'Not started', color: '#2a2d3a' }
	] as const;

	// Single-hue sequential ramp: on a dark surface, more mastery = more light.
	const RAMP = ['#232733', '#17402c', '#176b3d', '#1ea854', '#45c97e'];
	// The top two steps are light enough that the page ink reads at 2.5:1 and
	// 1.7:1 on them — a well-learned key would have been the unreadable one. The
	// foreground is chosen with the background instead: ink on the dark steps
	// (11.9 / 9.3 / 5.2), and the page background on the bright ones (6.1 / 8.9).
	const RAMP_INK = ['#e4e6eb', '#e4e6eb', '#e4e6eb', '#0f1117', '#0f1117'];

	function rampStep(score: number, total: number): number {
		if (total === 0) return 0;
		return Math.min(RAMP.length - 1, Math.round(score * (RAMP.length - 1)));
	}

	let showTable = $state(false);

	const secs = (ms: number) => `${(ms / 1000).toFixed(1)}s`;
	const pct = (v: number) => `${Math.round(v * 100)}%`;

	const medianSeries = $derived(
		data.series.map((d) => ({ x: d.short, y: d.medianMs }))
	);
	const accuracySeries = $derived(
		data.series.map((d) => ({ x: d.short, y: d.accuracy }))
	);
	const statesTotal = $derived(data.states.total || 1);
</script>

<svelte:head><title>Progress · Voicings</title></svelte:head>

<h1 class="mb-4 text-lg font-semibold">Progress</h1>

<!-- Headline stat tile: a single number needs no chart -->
<section class="mb-4 grid grid-cols-2 gap-2">
	<div class="rounded-xl border border-line bg-surface p-3">
		<div class="text-[11px] uppercase tracking-wider text-muted">ii–V–I, per chord</div>
		<div class="mt-1 text-2xl font-bold tabular-nums">
			{data.headline.chainPerChordMs === null
				? '—'
				: secs(data.headline.chainPerChordMs)}
		</div>
		<div class="text-[11px] text-muted">
			target &lt; {secs(data.headline.targetPerChordMs)}
		</div>
	</div>
	<div class="rounded-xl border border-line bg-surface p-3">
		<div class="text-[11px] uppercase tracking-wider text-muted">Retention</div>
		<div class="mt-1 text-2xl font-bold tabular-nums">
			{data.retention.rate === null ? '—' : pct(data.retention.rate)}
		</div>
		<div class="text-[11px] text-muted">
			{data.retention.reviewed} scheduled recall{data.retention.reviewed === 1 ? '' : 's'} · all
			time
		</div>
	</div>
</section>

<!-- 12-key heatmap -->
<section class="mb-4 rounded-xl border border-line bg-surface p-4">
	<h2 class="text-[11px] uppercase tracking-wider text-muted">The twelve keys</h2>
	<p class="mb-3 text-[11px] text-muted">
		Share of each key's <em>shell-family</em> cards (shells, notes → symbol, major ii–V–I chains
		and voice-leading) that are automatic — the same measure the path's last stage uses. Rootless
		voicings, theory drills and minor progressions are counted under Cards by state once they
		are in your deck.
	</p>
	<div class="grid grid-cols-4 gap-1.5" data-testid="heatmap">
		{#each data.heatmap as cell (cell.pitchClass)}
			{@const step = rampStep(cell.score, cell.total)}
			<div
				class="rounded-lg border border-line p-2 text-center"
				style="background: {RAMP[step]}; color: {RAMP_INK[step]}"
				title="{cell.label}: {cell.automatic}/{cell.total} automatic{cell.medianResponseMs
					? `, median ${secs(cell.medianResponseMs)}`
					: ''}"
				data-key={cell.label}
				data-score={cell.score.toFixed(2)}
			>
				<div class="text-sm font-bold">{cell.label}</div>
				<!-- No dimming: at 80% the percentage drops under AA on the mid step. -->
				<div class="text-[10px] tabular-nums">
					{Math.round(cell.score * 100)}%
				</div>
			</div>
		{/each}
	</div>
</section>

<!-- Median response time: the headline trend -->
<section class="mb-4 rounded-xl border border-line bg-surface p-4">
	<h2 class="text-[11px] uppercase tracking-wider text-muted">Median response time</h2>
	<p class="mb-2 text-[11px] text-muted">All card types, per day; speed rounds excluded. Should trend down.</p>
	<LineChart
		points={medianSeries}
		format={secs}
		label="Median response time per day"
		color="#4f8cff"
	/>
</section>

<section class="mb-4 rounded-xl border border-line bg-surface p-4">
	<h2 class="text-[11px] uppercase tracking-wider text-muted">Accuracy</h2>
	<p class="mb-2 text-[11px] text-muted">Per day, all attempts; speed rounds excluded.</p>
	<!-- No target line. targetRetention is the scheduler's desired recall on a
	     scheduled review of an already-known card — the population retentionOf()
	     builds and the Retention tile above reports. This series counts every
	     attempt, first-ever sightings of brand-new cards included, and those are
	     meant to be wrong; drawing the scheduler's bar across them judges a
	     healthy learner against a number that was never about them. Moving the
	     line to the retention population would need a per-day retention series
	     the app does not compute, and the tile already states that figure. -->
	<LineChart
		points={accuracySeries}
		format={pct}
		label="Accuracy per day"
		color="#1ea854"
		domain={[null, 1]}
	/>
</section>

<!-- Cards by state -->
<section class="mb-4 rounded-xl border border-line bg-surface p-4">
	<h2 class="mb-3 text-[11px] uppercase tracking-wider text-muted">Cards by state</h2>
	<div class="flex h-4 w-full gap-[2px] overflow-hidden rounded" data-testid="state-bar">
		{#each MASTERY as m (m.key)}
			{@const n = data.states[m.key]}
			{#if n > 0}
				<div
					style="background: {m.color}; width: {(n / statesTotal) * 100}%"
					title="{m.label}: {n}"
				></div>
			{/if}
		{/each}
	</div>
	<ul class="mt-3 space-y-1">
		{#each MASTERY as m (m.key)}
			<li class="flex items-center gap-2 text-xs">
				<span
					class="size-3 shrink-0 rounded-sm border border-line"
					style="background: {m.color}"
					aria-hidden="true"
				></span>
				<span class="flex-1">{m.label}</span>
				<span class="tabular-nums text-muted">{data.states[m.key]}</span>
			</li>
		{/each}
	</ul>
</section>

<!-- Accessible alternative to every chart above -->
<section class="rounded-xl border border-line bg-surface p-4">
	<button
		type="button"
		class="flex min-h-[44px] w-full items-center justify-between text-[11px] uppercase tracking-wider text-muted"
		aria-expanded={showTable}
		onclick={() => (showTable = !showTable)}
	>
		<span>Table view</span>
		<span aria-hidden="true">{showTable ? '−' : '+'}</span>
	</button>

	{#if showTable}
		<div class="overflow-x-auto">
			<table class="mt-2 w-full text-left text-xs">
				<caption class="sr-only">Daily reviews, accuracy and median response time</caption>
				<thead class="text-muted">
					<tr>
						<th scope="col" class="py-1 pr-2 font-normal">Day</th>
						<th scope="col" class="py-1 pr-2 font-normal">Accuracy</th>
						<th scope="col" class="py-1 font-normal">Median</th>
					</tr>
				</thead>
				<tbody>
					{#each [...data.series].reverse().filter((d) => d.accuracy !== null) as row (row.date)}
						<tr class="border-t border-line">
							<td class="py-1 pr-2 tabular-nums">{row.date}</td>
							<td class="py-1 pr-2 tabular-nums">
								{row.accuracy === null ? '—' : pct(row.accuracy)}
							</td>
							<td class="py-1 tabular-nums">
								{row.medianMs === null ? '—' : secs(row.medianMs)}
							</td>
						</tr>
					{:else}
						<tr><td colspan="3" class="py-2 text-muted">No reviews yet.</td></tr>
					{/each}
				</tbody>
			</table>
		</div>

		{#if data.byQuality.length > 0}
			<div class="overflow-x-auto">
				<table class="mt-3 w-full text-left text-xs">
					<caption class="sr-only">Accuracy and median response time by chord quality</caption>
					<thead class="text-muted">
						<tr>
							<th scope="col" class="py-1 pr-2 font-normal">Quality</th>
							<th scope="col" class="py-1 pr-2 font-normal">Accuracy</th>
							<th scope="col" class="py-1 font-normal">Median</th>
						</tr>
					</thead>
					<tbody>
						{#each data.byQuality as q (q.quality)}
							<tr class="border-t border-line">
								<td class="py-1 pr-2">{data.qualityLabels[q.quality] ?? q.quality}</td>
								<td class="py-1 pr-2 tabular-nums">
									{q.accuracy === null ? '—' : pct(q.accuracy)}
								</td>
								<td class="py-1 tabular-nums">
									{q.medianResponseMs === null ? '—' : secs(q.medianResponseMs)}
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	{/if}
</section>
