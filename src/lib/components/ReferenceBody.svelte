<script lang="ts">
	import { TOPICS_BY_ID, type ReferenceTopic } from '$lib/content/reference';

	interface Props {
		topic: ReferenceTopic;
		/** Renders related-topic links. Off inside the session sheet, which has
		 *  nowhere to navigate to without losing the queue. */
		showRelated?: boolean;
		/** Level the section headings sit at. The two hosts nest the same body
		 *  differently — the topic page's title is the h1, the sheet's is an h2 —
		 *  and a fixed level left a hole in one outline or the other. */
		level?: 2 | 3;
	}

	let { topic, showRelated = true, level = 2 }: Props = $props();
	const heading = $derived(`h${level}` as 'h2' | 'h3');
</script>

<div class="space-y-4">
	{#each topic.sections as section, i (i)}
		<section>
			{#if section.heading}
				<svelte:element this={heading} class="mb-1 text-sm font-semibold"
					>{section.heading}</svelte:element
				>
			{/if}

			{#each section.body ?? [] as paragraph, j (j)}
				<p class="mb-2 text-sm leading-relaxed text-muted">{paragraph}</p>
			{/each}

			{#if section.list}
				<ul class="mb-2 list-disc space-y-1 pl-5 text-sm leading-relaxed text-muted">
					{#each section.list as item, j (j)}
						<li>{item}</li>
					{/each}
				</ul>
			{/if}

			{#if section.table}
				<div class="mb-2 overflow-x-auto">
					<table class="w-full text-left text-xs">
						<thead class="text-muted">
							<tr>
								{#each section.table.head as cell, j (j)}
									<th scope="col" class="py-1 pr-3 font-normal whitespace-nowrap">{cell}</th>
								{/each}
							</tr>
						</thead>
						<tbody>
							{#each section.table.rows as row, r (r)}
								<tr class="border-t border-line">
									{#each row as cell, c (c)}
										<td class="py-1 pr-3 whitespace-nowrap" class:font-semibold={c === 0}>
											{cell}
										</td>
									{/each}
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</section>
	{/each}

	{#if showRelated && topic.related.length > 0}
		<nav class="border-t border-line pt-3" aria-label="Related topics">
			<svelte:element this={heading} class="eyebrow mb-2">See also</svelte:element>
			<ul class="space-y-1">
				{#each topic.related as id (id)}
					<li>
						<a href="/reference/{id}" class="text-sm text-brass underline underline-offset-2"
						>{TOPICS_BY_ID[id]?.title ?? id.replace(/-/g, ' ')}</a
					>
					</li>
				{/each}
			</ul>
		</nav>
	{/if}
</div>
