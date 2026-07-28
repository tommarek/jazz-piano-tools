<script lang="ts">
	import { TOPICS_BY_ID, type ReferenceTopic } from '$lib/content/reference';

	interface Props {
		topic: ReferenceTopic;
		/** Renders related-topic links. Off inside the session sheet, which has
		 *  nowhere to navigate to without losing the queue. */
		showRelated?: boolean;
	}

	let { topic, showRelated = true }: Props = $props();
</script>

<div class="space-y-4">
	{#each topic.sections as section, i (i)}
		<section>
			{#if section.heading}
				<h3 class="mb-1 text-sm font-semibold">{section.heading}</h3>
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
			<h3 class="mb-2 text-[11px] uppercase tracking-wider text-muted">See also</h3>
			<ul class="space-y-1">
				{#each topic.related as id (id)}
					<li>
						<a href="/reference/{id}" class="text-sm text-accent underline"
						>{TOPICS_BY_ID[id]?.title ?? id.replace(/-/g, ' ')}</a
					>
					</li>
				{/each}
			</ul>
		</nav>
	{/if}
</div>
