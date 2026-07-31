<script lang="ts">
	import { EAR_STAGES } from '$lib/music/cards';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	const nothingDue = $derived(data.decks.section.total === 0);

	// One row per drill, not per stage: a row states a deck's counts and links to
	// that deck, and an ear stage that ever grows a second drill would otherwise
	// advertise both drills' cards under a link that deals only the first. Taken
	// in path order — the record is keyed by the stage's own number.
	const drills = $derived(EAR_STAGES.flatMap((st) => data.decks.types[st.n] ?? []));

	// A drill deck ignores the path, so an unblocked row is a drill that is
	// switched on and merely ahead of the path. The section deck applies the
	// path, so it can be empty while a row below it is still a live link — and
	// "both drills are off" would then contradict the list on the same screen.
	const anyDrillOn = $derived(drills.some((d) => d.block === null));

	/** Same wording as the theory picker; the reasons are the same reasons. */
	const BLOCK_LABEL: Record<'off' | 'sound' | 'qualities', string> = {
		off: 'switched off',
		sound: 'needs sound',
		qualities: 'no qualities'
	};
	const pct = (v: number | null) => (v === null ? '—' : `${Math.round(v * 100)}%`);
	const secs = (ms: number | null) => (ms === null ? '—' : `${(ms / 1000).toFixed(1)}s`);
</script>

<svelte:head><title>Ear · Comp</title></svelte:head>

<header class="mb-6">
	<h1 class="text-2xl font-bold uppercase" style="font-stretch:118%; letter-spacing:0.16em">
		Ear
	</h1>
	<div class="rule-brass mt-1.5 mb-2"></div>
	<p class="text-xs leading-relaxed text-muted">
		Naming what you hear. A separate practice from reading a symbol, on its own path and its own
		clock — accuracy first, speed never.
	</p>
</header>

{#if !data.soundEnabled}
	<!-- The whole section IS the sound. Nothing below can be practised without
	     it, so this replaces the screen rather than sitting above it. -->
	<section class="border-l-2 border-felt bg-felt/[0.07] py-3 pr-3 pl-4" data-testid="ear-no-sound">
		<h2 class="text-sm font-semibold text-felt-ink">Sound is off</h2>
		<p class="mt-1 text-xs leading-relaxed text-muted">
			Every card here is a sound and nothing else — with playback off there is no question on the
			screen to answer. Turn "Play the answer" on in
			<a href="/settings" class="text-brass underline underline-offset-2">Settings</a>.
		</p>
	</section>
{:else}
	<section class="mb-7">
		<div class="flex items-baseline justify-between">
			<div>
				<div class="figure text-3xl" data-testid="ear-due-count">{data.decks.section.total}</div>
				<div class="mt-0.5 text-xs text-muted">
					in this session · {data.decks.section.due} due · {data.decks.section.new} new
				</div>
			</div>
			<div class="text-right">
				<div class="figure text-3xl text-brass" data-testid="ear-accuracy">
					{pct(data.stats.accuracy)}
				</div>
				<div class="mt-0.5 text-xs text-muted">accuracy, all time</div>
			</div>
		</div>

		{#if nothingDue}
			<!-- Disabled for the keyboard too, not just the pointer, and outlined
			     rather than faded brass — see Today. -->
			<button
				type="button"
				disabled
				class="eyebrow mt-4 flex min-h-[56px] w-full items-center justify-center rounded-sm border border-line text-muted"
				style="font-size:0.8125rem"
				data-testid="start-ear"
			>
				{#if data.decks.section.size > 0}Nothing due{:else if anyDrillOn}Nothing in the mix{:else}Nothing
					switched on{/if}
			</button>
		{:else}
			<a
				href="/session?deck=ear"
				class="eyebrow mt-4 flex min-h-[56px] items-center justify-center rounded-sm bg-brass !text-on-brass"
				style="font-size:0.8125rem"
				data-testid="start-ear"
			>
				Start
			</a>
		{/if}

		{#if data.decks.section.size === 0 && anyDrillOn}
			<p class="mt-2 text-center text-xs text-muted" data-testid="ear-ahead-only">
				What is left switched on sits ahead of the path, so it stays out of the mix — drill it from
				the list below, or open its stage in
				<a href="/settings" class="text-brass underline underline-offset-2">Settings</a>.
			</p>
		{:else if data.decks.section.size === 0}
			<p class="mt-2 text-center text-xs text-muted" data-testid="ear-empty">
				Both ear drills are switched off in
				<a href="/settings" class="text-brass underline underline-offset-2">Settings</a>.
			</p>
		{:else if nothingDue && data.decks.newBudget === 0}
			<!-- "Nothing due" alone reads as "come back tomorrow", which is only half
			     of it: this section's own new-card allowance is spent, and that is a
			     setting rather than a wait. -->
			<p class="mt-2 text-center text-xs text-muted" data-testid="ear-budget-spent">
				Nothing due, and today's new cards are spent. Each section has its own daily allowance —
				raise it in <a href="/settings" class="text-brass underline underline-offset-2">Settings</a>, or
				come back tomorrow.
			</p>
		{:else if nothingDue}
			<p class="mt-2 text-center text-xs text-muted">
				Nothing due. Ear training rewards little and often more than most of this app.
			</p>
		{/if}
	</section>

	<div class="rule mb-4"></div>

	<!-- Two drills, so no expanding: the whole section fits on the screen. -->
	<section class="mb-7" data-testid="ear-decks">
		<h2 class="eyebrow">Or drill one</h2>
		<ul class="mt-3">
			{#each drills as drill (drill.slug)}
				{@const stats = data.stats.byType.find((s) => s.type === drill.slug)}
				<li class="border-t border-line">
					{#if drill.block}
						<div class="flex items-baseline gap-3 py-3.5">
							<span class="flex-1 text-sm font-semibold text-muted">{drill.label}</span>
							<span class="eyebrow">{BLOCK_LABEL[drill.block]}</span>
						</div>
					{:else}
						<div class="flex items-stretch">
							<a
								href="/session?deck={drill.slug}"
								class="flex flex-1 items-baseline gap-3 py-3.5"
								data-testid="deck-{drill.slug}"
							>
								<span class="flex-1 text-sm font-semibold">
									{drill.label}{#if drill.ahead}<span class="eyebrow ml-2 !text-[9px]">ahead</span
										>{/if}
								</span>
							</a>
							<a
								href="/deck/{drill.slug}"
								class="flex min-h-[44px] items-baseline py-3.5 pl-3 text-xs text-muted"
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
					{#if stats && stats.attempts > 0}
						<p class="-mt-1 pb-3 text-[11px] text-muted">
							<span class="figure">{pct(stats.accuracy)}</span> right over
							<span class="figure">{stats.attempts}</span>, median
							<span class="figure">{secs(stats.medianResponseMs)}</span>
						</p>
					{/if}
				</li>
			{/each}
		</ul>
	</section>

	{#if data.path.justUnlocked}
		{@const opened = EAR_STAGES.find((st) => st.n === data.path.justUnlocked)}
		<section
			class="mb-7 border-l-2 border-sage bg-sage/10 py-3 pr-3 pl-4"
			role="status"
			data-testid="ear-unlocked"
		>
			<h2 class="text-sm font-semibold text-sage">{opened?.title} unlocked</h2>
			<p class="mt-1 text-xs text-muted">Your ear is reliable enough to work on colour.</p>
		</section>
	{:else if data.path.next}
		<div class="rule mb-4"></div>
		<section class="mb-7" data-testid="ear-gate">
			<h2 class="eyebrow">Next: {data.path.next.title}</h2>
			<ul class="mt-3 space-y-2 text-xs">
				{#each data.path.next.criteria as criterion (criterion.label)}
					<li class="flex items-baseline gap-2.5">
						<!-- Decorative square, so the state is said in words as well —
						     the same reason Today's checklist carries it. -->
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
			<p class="mt-3 text-xs leading-relaxed text-muted">
				Chord qualities are heard as the intervals inside them, so intervals come first —
				guessing at m7 against 7 trains the guess.
				<a href="/settings" class="text-brass underline underline-offset-2">Open it anyway</a> if you'd
				rather not wait.
			</p>
		</section>
	{/if}
{/if}
