<script lang="ts">
	import LineChart from '$lib/components/LineChart.svelte';
	import { MASTERY_LABEL } from '$lib/scheduler/grading';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	// Mastery is an ordered state, so it gets an ordered scale: one hue, dark to
	// light, brass gaining strength as a card is learned. It is deliberately NOT
	// four separate colours — two hues far enough apart to name (sage against
	// brass, say) sit at ΔE 4.9 under protanopia and 10.4 with full colour
	// vision, which is to say they are one colour to a lot of people. Every step
	// carries its label and its count regardless, so nothing here is read from
	// colour alone; the bottom step is under 3:1 on the ground on purpose, being
	// the absence of progress rather than a value.
	// Order and colour are this chart's; the wording is the scheduler's, so a
	// state cannot be called one thing here and another in the deck browser.
	const MASTERY = [
		{ key: 'automatic', label: MASTERY_LABEL.automatic, color: '#e8bd70' },
		{ key: 'familiar', label: MASTERY_LABEL.familiar, color: '#c9963f' },
		{ key: 'new', label: MASTERY_LABEL.new, color: '#87673a' },
		{ key: 'unseen', label: MASTERY_LABEL.unseen, color: '#3a3330' }
	] as const;

	// The same idea for magnitude: on the ebony ground, more mastery = more brass.
	const RAMP = ['#231e19', '#4a3a22', '#7d5f2c', '#b58a3d', '#e0b566'];
	// The bright steps are light enough that page ink on them reads at 2.6:1 and
	// 1.6:1 — a well-learned key would have been the unreadable one. The
	// foreground is chosen with the background instead: ivory on the dark steps
	// (13.8 / 9.2 / 5.0), ebony on the bright ones (6.0 / 9.8).
	const RAMP_INK = ['#f2eadb', '#f2eadb', '#f2eadb', '#13110f', '#13110f'];

	function rampStep(score: number, total: number): number {
		if (total === 0) return 0;
		return Math.min(RAMP.length - 1, Math.round(score * (RAMP.length - 1)));
	}

	let showTable = $state(false);

	// Null-aware, because a drill can have attempts and still no median: every
	// median on this screen is over correct answers only, and a card answered
	// wrong three times has none.
	const secs = (ms: number | null) => (ms === null ? '—' : `${(ms / 1000).toFixed(1)}s`);
	const pct = (v: number) => `${Math.round(v * 100)}%`;

	const medianSeries = $derived(
		data.series.map((d) => ({ x: d.short, y: d.medianMs }))
	);
	const accuracySeries = $derived(
		data.series.map((d) => ({ x: d.short, y: d.accuracy }))
	);
	const statesTotal = $derived(data.states.total || 1);
	const earSeries = $derived(data.ear.series.map((d) => ({ x: d.short, y: d.accuracy })));
</script>

<svelte:head><title>Progress · Comp</title></svelte:head>

<header class="mb-6">
	<h1 class="text-2xl font-bold uppercase" style="font-stretch:118%; letter-spacing:0.16em">
		Progress
	</h1>
	<div class="rule-brass mt-1.5"></div>
</header>

<!-- Headline stat tile: a single number needs no chart -->
<section class="mb-8 grid grid-cols-2 divide-x divide-line">
	<div class="pr-4">
		<div class="eyebrow">ii–V–I, per chord</div>
		<div class="figure mt-1.5 text-3xl">
			{secs(data.headline.chainPerChordMs)}
		</div>
		<div class="mt-1 text-[11px] text-muted">
			target &lt; {secs(data.headline.targetPerChordMs)}
		</div>
	</div>
	<div class="pl-4">
		<div class="eyebrow">Retention</div>
		<div class="figure mt-1.5 text-3xl">
			{data.retention.rate === null ? '—' : pct(data.retention.rate)}
		</div>
		<div class="mt-1 text-[11px] text-muted">
			{data.retention.reviewed} scheduled recall{data.retention.reviewed === 1 ? '' : 's'} · all
			time
		</div>
	</div>
</section>

<!-- 12-key heatmap -->
<div class="rule mb-4"></div>
<section class="mb-8">
	<h2 class="eyebrow">The twelve keys</h2>
	<p class="mt-2 mb-4 text-[11px] leading-relaxed text-muted">
		Share of each key's <em>guide-tone family</em> cards (symbol → guide tones, guide tones →
		symbol, and the major ii–V–I chain and comping cards) that are automatic — the same measure
		the path's last stage uses. Rootless voicings, theory drills and minor progressions are
		counted under Cards by state once they are in your deck.
	</p>
	<div class="grid grid-cols-4 gap-1.5" data-testid="heatmap">
		{#each data.heatmap as cell (cell.pitchClass)}
			{@const step = rampStep(cell.score, cell.total)}
			<div
				class="p-2 text-center"
				style="background: {RAMP[step]}; color: {RAMP_INK[step]}"
				title="{cell.label}: {cell.automatic}/{cell.total} automatic{cell.medianResponseMs
					? `, median ${secs(cell.medianResponseMs)}`
					: ''}"
				data-key={cell.label}
				data-score={cell.score.toFixed(2)}
			>
				<div class="text-sm font-bold">{cell.label}</div>
				<!-- No dimming: at 80% the percentage drops under AA on the mid step. -->
				<div class="figure text-[10px]">
					{Math.round(cell.score * 100)}%
				</div>
				<!-- The counts and the median are in the `title` for a pointer, and a
				     `title` on a div is announced by nothing and hovered by no phone —
				     so they are text as well, the same way the week strip carries its
				     day counts. -->
				<span class="sr-only"
					>{cell.label}: {cell.automatic} of {cell.total} automatic{cell.medianResponseMs
						? `, median ${secs(cell.medianResponseMs)}`
						: ''}</span
				>
			</div>
		{/each}
	</div>
</section>

<!-- Median response time: the headline trend -->
<div class="rule mb-4"></div>
<section class="mb-8">
	<h2 class="eyebrow">Median response time</h2>
	<p class="mt-2 mb-3 text-[11px] text-muted">
		Every theory drill, per day; ear training and speed rounds excluded. Should trend down.
	</p>
	<LineChart
		points={medianSeries}
		format={secs}
		label="Median response time per day"
		color="var(--color-brass)"
	/>
</section>

<div class="rule mb-4"></div>
<section class="mb-8">
	<h2 class="eyebrow">Accuracy</h2>
	<p class="mt-2 mb-3 text-[11px] text-muted">
		Every theory attempt, per day; ear training and speed rounds excluded.
	</p>
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
		color="var(--color-sage)"
		domain={[null, 1]}
	/>
</section>

<!-- Cards by state -->
<div class="rule mb-4"></div>
<section class="mb-8">
	<h2 class="eyebrow mb-3">Cards by state</h2>
	<div class="flex h-3 w-full gap-[2px]" data-testid="state-bar">
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
					class="size-3 shrink-0"
					style="background: {m.color}"
					aria-hidden="true"
				></span>
				<span class="flex-1">{m.label}</span>
				<span class="figure text-muted">{data.states[m.key]}</span>
			</li>
		{/each}
	</ul>
</section>

<div class="rule mb-4"></div>

<!--
	Ear training, kept apart. Its accuracy and its median are computed over ear
	cards only, and none of the figures above include them: perception is slower
	than recall for a long time after it is reliable, so one average over both
	described neither.
-->
<section class="mb-8" data-testid="ear-stats">
	<h2 class="eyebrow">Ear training</h2>
	<p class="mt-2 mb-4 text-[11px] leading-relaxed text-muted">
		Counted separately from everything above. Accuracy is the measure here — speed comes on its
		own schedule and is not what the ear path is judged on.
	</p>

	{#if data.ear.attempts === 0}
		<p class="text-xs text-muted" data-testid="ear-stats-empty">
			No ear cards answered yet. <a
				href="/ear"
				class="text-brass underline underline-offset-2">Ear training</a
			> is its own section.
		</p>
	{:else}
		<div class="grid grid-cols-2 divide-x divide-line">
			{#each data.ear.byType as row (row.type)}
				<div class="px-4 first:pl-0 last:pr-0">
					<div class="eyebrow">{row.label}</div>
					<div class="figure mt-1.5 text-2xl">
						{row.accuracy === null ? '—' : pct(row.accuracy)}
					</div>
					<div class="mt-1 text-[11px] text-muted">
						{#if row.attempts > 0}
							over {row.attempts}, median {secs(row.medianResponseMs)}
						{:else}
							not started
						{/if}
					</div>
				</div>
			{/each}
		</div>

		<h3 class="eyebrow mt-6">Accuracy by ear, per day</h3>
		<div class="mt-3">
			<LineChart
				points={earSeries}
				format={pct}
				label="Ear accuracy per day"
				color="var(--color-sage)"
				domain={[null, 1]}
			/>
		</div>
	{/if}
</section>

<!-- Accessible alternative to every chart on this screen, the ear one included:
     a chart nobody can read is a figure the app is keeping to itself. -->
<div class="rule mb-2"></div>
<section>
	<button
		type="button"
		class="eyebrow flex min-h-[44px] w-full items-center justify-between"
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
							<td class="py-1 pr-2 figure">{row.date}</td>
							<td class="py-1 pr-2 figure">
								{row.accuracy === null ? '—' : pct(row.accuracy)}
							</td>
							<td class="py-1 figure">
								{secs(row.medianMs)}
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
								<td class="py-1 pr-2 figure">
									{q.accuracy === null ? '—' : pct(q.accuracy)}
								</td>
								<td class="py-1 figure">
									{secs(q.medianResponseMs)}
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}

		{#if data.ear.attempts > 0}
			<div class="overflow-x-auto">
				<table class="mt-3 w-full text-left text-xs" data-testid="ear-table">
					<caption class="sr-only">Ear accuracy per day</caption>
					<thead class="text-muted">
						<tr>
							<th scope="col" class="py-1 pr-2 font-normal">Day</th>
							<th scope="col" class="py-1 font-normal">Ear accuracy</th>
						</tr>
					</thead>
					<tbody>
						{#each [...data.ear.series].reverse().filter((d) => d.accuracy !== null) as row (row.date)}
							<tr class="border-t border-line">
								<td class="py-1 pr-2 figure">{row.date}</td>
								<td class="py-1 figure">{row.accuracy === null ? '—' : pct(row.accuracy)}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	{/if}
</section>
