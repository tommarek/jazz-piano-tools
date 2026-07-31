<script lang="ts">
	import ChordSymbol from '$lib/components/ChordSymbol.svelte';
	import { playSequence, stopAll } from '$lib/audio/piano';
	import { MASTERY_LABEL } from '$lib/scheduler/grading';
	import { startOfDay } from '$lib/data/queue';
	import { onDestroy } from 'svelte';
	import type { BrowseCard } from '$lib/data/browse';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	type Filter = 'all' | 'due' | 'weak' | 'automatic';
	let filter = $state<Filter>('all');

	/** One card at a time: two ear prompts overdubbed are neither of them. */
	function play(groups: number[][] | null) {
		if (!groups?.length) return;
		stopAll();
		playSequence(groups, groups.length > 2 ? { gapMs: 900 } : {});
	}

	onDestroy(stopAll);

	const FILTERS: { key: Filter; label: string }[] = [
		{ key: 'all', label: 'All' },
		{ key: 'due', label: 'Due' },
		{ key: 'weak', label: 'Weak' },
		{ key: 'automatic', label: 'Automatic' }
	];

	function keep(card: BrowseCard): boolean {
		if (filter === 'due') return card.due;
		// "Weak" is everything short of automatic, which is the state the whole
		// app is steering at — including cards never seen, because a key you have
		// not started is exactly as unplayable as one you keep missing.
		if (filter === 'weak') return card.mastery !== 'automatic';
		if (filter === 'automatic') return card.mastery === 'automatic';
		return true;
	}

	const groups = $derived(
		data.browse.groups
			.map((g) => ({ ...g, cards: g.cards.filter(keep) }))
			.filter((g) => g.cards.length > 0)
	);
	const shown = $derived(groups.reduce((n, g) => n + g.cards.length, 0));

	// The scheduler's own wording, lowercased: in this column it sits next to
	// "due" and "in 3d" as one more thing said about the row, not as a legend.
	const masteryLabel = (card: BrowseCard) => MASTERY_LABEL[card.mastery].toLowerCase();

	const secs = (ms: number | null) => (ms === null ? null : `${(ms / 1000).toFixed(1)}s`);

	/**
	 * Calendar days from today: the two ends are queue.ts's own day boundaries,
	 * and the rounding is what absorbs the 23- or 25-hour day between them.
	 */
	function dueLabel(card: BrowseCard): string {
		if (card.dueAt === null) return '';
		if (card.due) return 'due';
		const days = Math.round((startOfDay(card.dueAt) - startOfDay()) / 86_400_000);
		if (days <= 0) return 'due';
		if (days === 1) return 'tomorrow';
		if (days < 31) return `in ${days}d`;
		return `in ${Math.round(days / 30)}mo`;
	}
</script>

<svelte:head><title>{data.label} · Comp</title></svelte:head>

<a
	href={data.section === 'ear' ? '/ear' : '/'}
	class="eyebrow mb-2 inline-flex min-h-[44px] items-center !text-brass"
>
	← {data.section === 'ear' ? 'Ear' : 'Theory'}
</a>

<header class="mb-5">
	<h1 class="text-xl font-bold uppercase" style="font-stretch:112%; letter-spacing:0.1em">
		{data.label}
	</h1>
	<div class="rule-brass mt-1.5 mb-2"></div>
	<p class="text-xs text-muted">
		<span class="figure">{data.browse.total}</span> cards ·
		<span class="figure">{data.browse.counts.automatic}</span> automatic ·
		<span class="figure">{data.browse.counts.due}</span> due
	</p>
</header>

{#if data.browse.total === 0}
	<!-- Which switch emptied it, not just that a switch did: pointing at the
	     drill list when it was the sound is sending someone to the wrong row. -->
	<p class="text-xs text-muted" data-testid="deck-browse-empty">
		{#if data.browse.block === 'sound'}
			Nothing to show — every card here is a sound, and "Play the answer" is off in
		{:else if data.browse.block === 'qualities'}
			Nothing in this deck right now — its drills are on, but the chord qualities they need are
			switched off in
		{:else}
			Nothing in this deck right now — its drills are switched off in
		{/if}
		<a href="/settings" class="text-brass underline underline-offset-2">Settings</a>.
	</p>
{:else}
	<a
		href="/session?deck={data.slug}"
		class="eyebrow flex min-h-[56px] items-center justify-center rounded-sm bg-brass !text-on-brass"
		style="font-size:0.8125rem"
		data-testid="start-deck">Drill this deck</a
	>

	<!-- Filters, one row, above the list — the shape every other filtered list
	     on a phone has, because it is the one people already know. -->
	<div class="mt-5 flex gap-1.5" role="group" aria-label="Filter cards">
		{#each FILTERS as f (f.key)}
			<button
				type="button"
				class="eyebrow min-h-[44px] flex-1 border"
				class:border-brass={filter === f.key}
				class:!text-brass={filter === f.key}
				class:border-line={filter !== f.key}
				aria-pressed={filter === f.key}
				data-testid="filter-{f.key}"
				onclick={() => (filter = f.key)}>{f.label}</button
			>
		{/each}
	</div>

	{#if shown === 0}
		<p class="mt-6 text-xs text-muted" data-testid="filter-empty">
			No cards in this deck are {filter === 'due'
				? 'due right now'
				: filter === 'automatic'
					? 'automatic yet'
					: 'in that state'}.
		</p>
	{/if}

	{#each groups as group (group.type)}
		<section class="mt-6" data-testid="browse-group-{group.type}">
			<h2 class="eyebrow">{group.label}</h2>
			{#if group.sharedInstruction}
				<!-- Said once for the whole group rather than on every row. -->
				<p class="mt-1 text-[11px] text-muted">{group.sharedInstruction}</p>
			{/if}
			<ul class="mt-2">
				{#each group.cards as card (card.id)}
					<li class="flex items-start gap-3 border-t border-line py-3" data-testid="card-{card.id}">
						<div class="min-w-0 flex-1">
							<!-- The question as the card poses it: prompt, then the line the
							     drill prints under it. -->
							<div class="text-sm">
								<ChordSymbol text={card.title} size="inline" />
								{#if card.qualifier}
									<span class="ml-1.5 text-[11px] text-muted">{card.qualifier}</span>
								{/if}
							</div>
							{#if !card.qualifier && !group.sharedInstruction}
								<div class="mt-0.5 text-[11px] leading-snug text-muted">{card.instruction}</div>
							{/if}
							<!-- And the answer, in the ink the app uses for what it is telling
							     you. This is the one screen that shows both. -->
							<div class="mt-1 text-xs text-brass" data-testid="answer-{card.id}">
								<ChordSymbol text={card.answerText} size="inline" />
							</div>
							{#if card.reps > 0}
								<div class="mt-0.5 text-[10px] text-muted">
									<span class="figure">{card.reps}</span>
									review{card.reps === 1 ? '' : 's'}{#if card.lapses > 0}, <span class="figure"
											>{card.lapses}</span
										> lapse{card.lapses === 1 ? '' : 's'}{/if}
								</div>
							{/if}
						</div>

						{#if card.promptIsSound && card.sound}
							<!-- An ear card's question is the sound, so showing it means
							     playing it — a printed description is not the question. No
							     sound check here: with playback off the ear drills leave
							     liveDeckTypes, so this deck has no rows at all. Named by the
							     answer rather than the title: every ear card is titled
							     "Listen", so 132 buttons reading "Play Listen" locate a
							     screen-reader user on the list exactly as well as no name
							     would. The answer is on the row anyway — this is the one
							     screen that shows both. -->
							<button
								type="button"
								class="min-h-[44px] min-w-[44px] shrink-0 border border-line text-base text-brass"
								onclick={() => play(card.sound)}
								aria-label="Play {card.answerText}"
								data-testid="play-{card.id}">♪</button
							>
						{/if}

						<div class="shrink-0 text-right text-[11px] text-muted">
							<span
								class:text-sage={card.mastery === 'automatic'}
								class:text-ink={card.mastery === 'familiar'}
							>
								{masteryLabel(card)}
							</span>
							{#if card.medianResponseMs !== null}
								<span class="block figure">{secs(card.medianResponseMs)}</span>
							{/if}
							{#if card.dueAt !== null}
								<span class="block" class:text-brass={card.due}>{dueLabel(card)}</span>
							{/if}
						</div>
					</li>
				{/each}
			</ul>
		</section>
	{/each}
{/if}
