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

	/** Which stage deck is showing its drills. One at a time; none by default. */
	let expanded = $state<string | null>(null);

	/** Says why a deck has no cards at all, in the terms the learner can act on. */
	const BLOCK_LABEL: Record<'off' | 'sound' | 'qualities', string> = {
		off: 'switched off',
		sound: 'needs sound',
		qualities: 'no qualities'
	};

	const stageNumber = (slug: string) => Number(slug.replace('stage-', ''));
</script>

<svelte:head><title>Theory · Comp</title></svelte:head>

<!-- The wordmark is the app's one piece of lettering: expanded caps, widely
     tracked, with a brass rule under it. -->
<header class="mb-6">
	<h1
		class="text-2xl font-bold uppercase"
		style="font-stretch:118%; letter-spacing:0.16em"
	>
		Theory
	</h1>
	<div class="rule-brass mt-1.5 mb-2"></div>
	<p class="text-xs text-muted">
		Everything you read: symbols into shapes, and the theory under them.
	</p>
</header>

<!-- The one metric: when this drops under 2s, the guide tones are automatic. It
     is the hero because it is the whole thesis of the app — recall speed, not
     notes. -->
<section class="mb-7" aria-labelledby="headline-label">
	<h2 id="headline-label" class="eyebrow">ii–V–I, per chord</h2>
	<div class="mt-2 flex items-baseline gap-2">
		<!-- Nothing measured yet is a quiet dash, not a 56px one: an empty hero
		     should not shout the loudest thing on the screen. -->
		<span
			class="figure leading-[0.85]"
			class:text-[3.5rem]={perChord !== null}
			class:text-4xl={perChord === null}
			class:text-muted={perChord === null}
			class:text-sage={onTarget}
			class:text-ink={perChord !== null && !onTarget}
			data-testid="headline-metric"
		>
			{perChord === null ? '—' : (perChord / 1000).toFixed(1)}
		</span>
		{#if perChord !== null}
			<span class="text-base text-muted">s</span>
		{/if}
		<span class="ml-auto text-xs text-muted">
			target &lt; <span class="figure">{(target / 1000).toFixed(1)}</span>s
		</span>
	</div>
	<p class="mt-3 text-xs leading-relaxed text-muted">
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
			{#if data.stages.unlocked === 3 && data.stages.rootlessActive}
				— rootless voicings are in the deck.
			{:else if data.stages.unlocked < 3 && !data.stages.keysMet}
				— next, get every key half automatic on guide tones (see below).
			{:else if data.stages.unlocked === 3}
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

<div class="rule mb-4"></div>

<section class="mb-7">
	<div class="flex items-baseline justify-between">
		<div>
			<div class="figure text-3xl" data-testid="due-count">{data.summary.total}</div>
			<div class="mt-0.5 text-xs text-muted">
				in today's session · {data.summary.due} due · {data.summary.new} new
			</div>
		</div>
		<div class="text-right">
			<div class="figure text-3xl text-brass" data-testid="today-count">
				{data.today.reviews}
			</div>
			<div class="mt-0.5 text-xs text-muted">done today</div>
		</div>
	</div>

	<!-- A brass plate with dark lettering: the pedal, and the only button in the
	     app that is filled at all. -->
	{#if nothingDue}
		<!-- A real disabled button, not a link with pointer events off: that only
		     stops the pointer, and Tab-then-Enter still opened a session that had
		     nothing to deal. Outlined rather than a faded brass plate — ebony
		     lettering on brass at 40% is 1.5:1, a label you cannot read rather
		     than a button you cannot press. -->
		<button
			type="button"
			disabled
			class="eyebrow mt-4 flex min-h-[56px] w-full items-center justify-center rounded-sm border border-line text-muted"
			style="font-size:0.8125rem"
			data-testid="start-session"
		>
			{data.summary.deckEmpty ? 'Deck is empty' : 'Nothing due'}
		</button>
	{:else}
		<a
			href="/session"
			class="eyebrow mt-4 flex min-h-[56px] items-center justify-center rounded-sm bg-brass !text-on-brass"
			style="font-size:0.8125rem"
			data-testid="start-session"
		>
			Start
		</a>
	{/if}

	{#if data.summary.deckEmpty}
		<p class="mt-2 text-center text-xs text-muted" data-testid="deck-empty">
			Your drill and quality switches leave nothing to deal, so tomorrow will look the same.
			<a href="/settings" class="text-brass underline underline-offset-2">Settings</a> is where to widen it.
		</p>
	{:else if nothingDue && data.summary.newBudgetZero}
		<p class="mt-2 text-center text-xs text-muted" data-testid="new-budget-zero">
			Nothing due, and new cards per day is 0 — so tomorrow will look the same. Raise it in
			<a href="/settings" class="text-brass underline underline-offset-2">Settings</a>, or run a
			<a href="/session?mode=speed" class="text-brass underline underline-offset-2">speed round</a>.
		</p>
	{:else if nothingDue}
		<p class="mt-2 text-center text-xs text-muted">
			Come back tomorrow, or run a <a
				href="/session?mode=speed"
				class="text-brass underline underline-offset-2">speed round</a
			>.
		</p>
	{:else}
		<p class="mt-2 text-center text-xs text-muted">
			<a href="/session?mode=speed" class="text-brass underline underline-offset-2">Speed round</a> · no scheduling, automatic
			cards only
		</p>
	{/if}
</section>

<div class="rule mb-4"></div>

<!--
	The deck picker. Mixed practice is the default above and this is the escape
	hatch from it, not the main road: interleaved sessions transfer better, and a
	deck is for the weakness you have already identified. Hence the wording, and
	hence a stage — the drills that belong together — being the first thing
	offered, with single drills a level down.
-->
<section class="mb-7" data-testid="deck-picker">
	<h2 class="eyebrow">Or drill one deck</h2>
	<ul class="mt-3">
		{#each data.decks.stages as deck (deck.slug)}
			{@const open = expanded === deck.slug}
			<li class="border-t border-line">
				<div class="flex items-stretch">
					{#if deck.block}
						<!-- Not a link: there is nothing to deal, and a row that starts an
						     empty session is worse than one that says why. Muted rather
						     than faded — dimming muted text with opacity lands at 2.5:1,
						     which is a row you cannot read rather than one you cannot tap.
						     What marks it unavailable is the missing count and the tag. -->
						<div class="flex flex-1 items-baseline gap-3 py-3.5">
							<span class="flex-1 text-sm font-semibold text-muted">{deck.label}</span>
							<span class="eyebrow">{BLOCK_LABEL[deck.block]}</span>
						</div>
					{:else}
						<a
							href="/session?deck={deck.slug}"
							class="flex flex-1 items-baseline gap-3 py-3.5"
							data-testid="deck-{deck.slug}"
						>
							<span class="flex-1 text-sm font-semibold">
								{deck.label}{#if deck.ahead}<span class="eyebrow ml-2 !text-[9px]">ahead</span
									>{/if}
							</span>
						</a>
						<!-- The count is the way in to the deck itself. Two targets in one
						     row: the name starts drilling, the number opens the list — which
						     is the reading the words already have. -->
						<a
							href="/deck/{deck.slug}"
							class="flex min-h-[44px] items-baseline py-3.5 pl-3 text-xs text-muted"
							data-testid="browse-{deck.slug}"
						>
							{#if deck.due > 0}
								<span class="figure text-ink">{deck.due}</span>&nbsp;due
							{:else}
								<span class="figure">{deck.size}</span>&nbsp;cards
							{/if}
							<span aria-hidden="true" class="ml-1.5 text-brass">›</span>
							<span class="sr-only">— look inside {deck.label}</span>
						</a>
					{/if}
					<button
						type="button"
						class="-mr-2 min-h-[44px] w-11 shrink-0 text-muted"
						aria-expanded={open}
						aria-label="{open ? 'Hide' : 'Show'} the drills in {deck.label}"
						data-testid="expand-{deck.slug}"
						onclick={() => (expanded = open ? null : deck.slug)}
					>
						<span aria-hidden="true">{open ? '−' : '+'}</span>
					</button>
				</div>

				{#if open}
					<ul class="mb-2 ml-3 border-l border-line pl-3">
						{#each data.decks.types[stageNumber(deck.slug)] ?? [] as drill (drill.slug)}
							<li>
								{#if drill.block}
									<div class="flex items-baseline gap-3 py-2.5">
										<span class="flex-1 text-xs text-muted">{drill.label}</span>
										<span class="eyebrow">{BLOCK_LABEL[drill.block]}</span>
									</div>
								{:else}
									<div class="flex items-stretch">
										<a
											href="/session?deck={drill.slug}"
											class="flex flex-1 items-baseline gap-3 py-2.5"
											data-testid="deck-{drill.slug}"
										>
											<span class="flex-1 text-xs">
												{drill.label}{#if drill.ahead}<span
														class="eyebrow ml-2 !text-[9px]">ahead</span
													>{/if}
											</span>
										</a>
										<a
											href="/deck/{drill.slug}"
											class="flex min-h-[44px] items-baseline py-2.5 pl-3 text-[11px] text-muted"
											data-testid="browse-{drill.slug}"
										>
											{#if drill.due > 0}
												<span class="figure text-ink">{drill.due}</span>&nbsp;due
											{:else}
												<span class="figure">{drill.size}</span>&nbsp;cards
											{/if}
											<span aria-hidden="true" class="ml-1.5 text-brass">›</span>
											<span class="sr-only">— look inside {drill.label}</span>
										</a>
									</div>
								{/if}
							</li>
						{/each}
					</ul>
				{/if}
			</li>
		{/each}
	</ul>
	<p class="mt-3 border-t border-line pt-3 text-xs leading-relaxed text-muted">
		{#if data.decks.newBudget > 0}
			<span class="figure text-ink">{data.decks.newBudget}</span> new card{data.decks.newBudget ===
			1
				? ''
				: 's'} left today, shared by every deck here. Ear training has its own.
		{/if}
		A deck session schedules exactly like a mixed one — same cards, same history. Mixing drills is
		what transfers, so keep coming back to Start.
		{#if data.decks.stages.some((d) => d.ahead)}
			Decks marked <span class="eyebrow !text-[9px]">ahead</span> are further along the path than
			you are: drill them whenever you like, but their cards only join the daily mix once the
			stage opens.
		{/if}
	</p>
</section>

{#if data.stages.justUnlocked}
	{@const opened = STAGES.find((st) => st.n === data.stages.justUnlocked)}
	<!-- The one moment the app celebrates, so it gets the one filled panel. -->
	<section
		class="mb-7 border-l-2 border-sage bg-sage/10 py-3 pr-3 pl-4"
		role="status"
		data-testid="gate-unlocked"
	>
		<h2 class="text-sm font-semibold text-sage">
			Stage {opened?.n} unlocked — {opened?.title}
		</h2>
		<p class="mt-1 text-xs text-muted">
			New in the deck: {opened?.types.map((t) => CARD_TYPE_LABEL[t]).join(', ')}.
		</p>
	</section>
{:else if data.stages.next}
	<div class="rule mb-4"></div>
	<section class="mb-7" data-testid="gate-progress">
		<h2 class="eyebrow">Next: stage {data.stages.next.n} of {STAGES.length} — {data.stages.next.title}</h2>
		<ul class="mt-3 space-y-2 text-xs">
			{#each data.stages.next.criteria as criterion (criterion.label)}
				<li class="flex items-baseline gap-2.5">
					<!-- A filled square or an empty one, not a tick and a circle: the
					     checklist reads as a row of stops filling up. Said in words too:
					     the square is decorative and a criterion whose label carries no
					     figures reads identically met or not. -->
					<span
						aria-hidden="true"
						class="mt-px inline-block size-2 shrink-0 border"
						class:border-sage={criterion.met}
						class:bg-sage={criterion.met}
						class:border-line={!criterion.met}
					></span>
					<span class:text-muted={!criterion.met}>
						{criterion.label}<span class="sr-only">
							— {criterion.met ? 'done' : 'not yet'}</span
						>
					</span>
				</li>
			{/each}
		</ul>
		<p class="mt-3 text-xs text-muted">
			<a href="/settings" class="text-brass underline underline-offset-2">Start it anyway</a> if you'd
			rather not wait.
		</p>
	</section>
{/if}

<div class="rule mb-4"></div>

<section>
	<div class="flex items-baseline justify-between">
		<h2 class="eyebrow">This week</h2>
		<!-- Only the number is a figure; tabular spacing on the words closes them up. -->
		<span class="text-xs text-muted"
			><span class="figure">{data.streakDays}</span>-day streak</span
		>
	</div>
	<!-- Seven ledger marks. A day practised is a brass line on the stave; a day
	     missed is the stave with nothing written on it. The bar height is the
	     whole graphic, and a `title` on a div is announced by nothing and hovered
	     by no phone — so each day carries its count as text as well, and the
	     initial (S M T W T F S, three of them repeats) is left to the eye. -->
	<div class="mt-4 flex items-end justify-between gap-1.5">
		{#each data.week as day (day.date)}
			<div class="flex flex-1 flex-col items-center gap-2">
				<div
					class="w-full"
					class:h-6={day.reviews > 0}
					class:bg-brass={day.reviews > 0}
					class:h-px={day.reviews === 0}
					class:bg-line={day.reviews === 0}
					title="{day.date}: {day.reviews} reviews"
				></div>
				<span class="eyebrow !text-[9px] !tracking-[0.1em]" aria-hidden="true">{day.label}</span>
				<span class="sr-only">{day.date}: {day.reviews} reviews</span>
			</div>
		{/each}
	</div>
</section>
