<script lang="ts">
	import { GATE_MIN_SAMPLE } from '$lib/data/stages';
	import { CARD_TYPE_LABEL, STAGES } from '$lib/music/cards';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	const perChord = $derived(data.headline.chainPerChordMs);
	const target = $derived(data.headline.targetPerChordMs);
	// "Under target" means what the gate means by it: fast AND over enough
	// chains — a green verdict off three quick attempts would contradict the
	// still-unmet checklist right below it.
	const onTarget = $derived(
		perChord !== null && perChord < target && data.headline.chainSampleSize >= GATE_MIN_SAMPLE
	);
	const nothingDue = $derived(data.summary.total === 0);
</script>

<svelte:head><title>Today · Voicings</title></svelte:head>

<header class="mb-5">
	<h1 class="text-lg font-semibold">Voicings</h1>
	<p class="text-xs text-muted">Shell voicings, a few minutes a day.</p>
</header>

<!-- The one metric: when this drops under 2s, shells are automatic. -->
<section
	class="mb-4 rounded-xl border border-line bg-surface p-4"
	aria-labelledby="headline-label"
>
	<h2 id="headline-label" class="text-[11px] uppercase tracking-wider text-muted">
		ii–V–I, per chord
	</h2>
	<div class="mt-1 flex items-baseline gap-2">
		<span
			class="text-4xl font-bold tabular-nums"
			class:text-good={onTarget}
			class:text-ink={!onTarget}
			data-testid="headline-metric"
		>
			{perChord === null ? '—' : (perChord / 1000).toFixed(1)}
		</span>
		{#if perChord !== null}
			<span class="text-sm text-muted">s</span>
		{/if}
		<span class="ml-auto text-xs text-muted">target &lt; {(target / 1000).toFixed(1)}s</span>
	</div>
	<p class="mt-2 text-xs text-muted">
		{#if perChord === null}
			<!-- The metric counts major chains only, so an empty one usually means
			     "not yet" but can equally mean "your filters withhold them" — and
			     only one of those gets better by practising. -->
			{#if data.stages.chainBlocked === 'qualities'}
				No major chains in the deck: the ii–V–I needs m7, 7 and maj7 (see Settings).
			{:else if data.stages.chainBlocked === 'type'}
				The ii–V–I chain drill is switched off in Settings.
			{:else}
				No chain cards answered yet.
			{/if}
		{:else if onTarget}
			Under target over your last {data.headline.chainSampleSize} correct chains
			{#if data.stages.unlocked === 4 && data.stages.rootlessActive}
				— rootless voicings are in the deck.
			{:else if data.stages.unlocked < 4 && !data.stages.stage4KeysMet}
				— next, get every key half automatic on shells (see below).
			{:else if data.stages.unlocked === 4}
				— time to add rootless voicings.
			{:else}
				— the rootless stage is close (see below).
			{/if}
		{:else}
			Median over your last {data.headline.chainSampleSize} correct chain{data.headline
				.chainSampleSize === 1
				? ''
				: 's'}.
		{/if}
	</p>
</section>

<section class="mb-4 rounded-xl border border-line bg-surface p-4">
	<div class="flex items-baseline justify-between">
		<div>
			<div class="text-3xl font-bold tabular-nums" data-testid="due-count">
				{data.summary.total}
			</div>
			<div class="text-xs text-muted">
				in today's session · {data.summary.due} due · {data.summary.new} new
			</div>
		</div>
		<div class="text-right">
			<div class="text-3xl font-bold tabular-nums text-accent" data-testid="today-count">
				{data.today.reviews}
			</div>
			<div class="text-xs text-muted">done today</div>
		</div>
	</div>

	<a
		href="/session"
		class="mt-4 flex min-h-[56px] items-center justify-center rounded-xl bg-accent-solid text-base font-semibold text-white"
		class:pointer-events-none={nothingDue}
		class:opacity-40={nothingDue}
		aria-disabled={nothingDue}
		data-testid="start-session"
	>
		{data.summary.deckEmpty ? 'Deck is empty' : nothingDue ? 'Nothing due' : 'Start'}
	</a>

	{#if data.summary.deckEmpty}
		<p class="mt-2 text-center text-xs text-muted" data-testid="deck-empty">
			Your drill and quality switches leave nothing to deal, so tomorrow will look the same.
			<a href="/settings" class="text-accent underline">Settings</a> is where to widen it.
		</p>
	{:else if nothingDue && data.summary.newBudgetZero}
		<p class="mt-2 text-center text-xs text-muted" data-testid="new-budget-zero">
			Nothing due, and new cards per day is 0 — so tomorrow will look the same. Raise it in
			<a href="/settings" class="text-accent underline">Settings</a>, or run a
			<a href="/session?mode=speed" class="text-accent underline">speed round</a>.
		</p>
	{:else if nothingDue}
		<p class="mt-2 text-center text-xs text-muted">
			Come back tomorrow, or run a <a href="/session?mode=speed" class="text-accent underline"
				>speed round</a
			>.
		</p>
	{:else}
		<p class="mt-2 text-center text-xs text-muted">
			<a href="/session?mode=speed" class="text-accent underline">Speed round</a> · no scheduling, automatic
			cards only
		</p>
	{/if}
</section>

{#if data.stages.justUnlocked}
	{@const opened = STAGES.find((st) => st.n === data.stages.justUnlocked)}
	<section
		class="mb-4 rounded-xl border border-good bg-good/10 p-4"
		role="status"
		data-testid="gate-unlocked"
	>
		<h2 class="text-sm font-semibold text-good">
			Stage {opened?.n} unlocked — {opened?.title}
		</h2>
		<p class="mt-1 text-xs text-muted">
			New in the deck: {opened?.types.map((t) => CARD_TYPE_LABEL[t]).join(', ')}.
		</p>
	</section>
{:else if data.stages.next}
	<section class="mb-4 rounded-xl border border-line bg-surface p-4" data-testid="gate-progress">
		<h2 class="text-[11px] uppercase tracking-wider text-muted">
			Next: stage {data.stages.next.n} of 4 — {data.stages.next.title}
		</h2>
		<ul class="mt-2 space-y-1 text-xs">
			{#each data.stages.next.criteria as criterion (criterion.label)}
				<li class="flex items-center gap-2">
					<span aria-hidden="true" class={criterion.met ? 'text-good' : 'text-muted'}>
						{criterion.met ? '✓' : '○'}
					</span>
					<span class:text-muted={!criterion.met}>{criterion.label}</span>
				</li>
			{/each}
		</ul>
		<p class="mt-2 text-xs text-muted">
			<a href="/settings" class="text-accent underline">Start it anyway</a> if you'd rather not wait.
		</p>
	</section>
{/if}

<section class="rounded-xl border border-line bg-surface p-4">
	<div class="flex items-center justify-between">
		<h2 class="text-[11px] uppercase tracking-wider text-muted">This week</h2>
		<span class="text-xs text-muted">{data.streakDays}-day streak</span>
	</div>
	<div class="mt-3 flex justify-between gap-1">
		{#each data.week as day (day.date)}
			<div class="flex flex-1 flex-col items-center gap-1">
				<div
					class="h-8 w-full rounded"
					class:bg-good={day.reviews > 0}
					class:bg-surface-2={day.reviews === 0}
					title="{day.date}: {day.reviews} reviews"
				></div>
				<span class="text-[10px] text-muted">{day.label}</span>
			</div>
		{/each}
	</div>
</section>
