<script lang="ts">
	import { TOPICS } from '$lib/content/reference';
</script>

<svelte:head><title>Reference · Comp</title></svelte:head>

<header class="mb-6">
	<h1 class="text-2xl font-bold uppercase" style="font-stretch:118%; letter-spacing:0.16em">
		Reference
	</h1>
	<div class="rule-brass mt-1.5 mb-2"></div>
	<p class="text-xs text-muted">
		The theory behind the drills. Also reachable from any card once you've answered it.
	</p>
</header>

<!-- A table of contents, ruled like one. The numbers are not decoration: the
     topics are written to be read in this order, each leaning on the last. -->
<ul>
	{#each TOPICS as topic, i (topic.id)}
		<li class="border-t border-line">
			<a
				href="/reference/{topic.id}"
				class="flex items-baseline gap-3 py-4"
				data-testid="topic-{topic.id}"
			>
				<span class="figure w-5 shrink-0 text-xs text-brass">{String(i + 1).padStart(2, '0')}</span>
				<span>
					<span class="block text-sm font-semibold">{topic.title}</span>
					<span class="mt-1 block text-xs leading-relaxed text-muted">{topic.blurb}</span>
				</span>
			</a>
		</li>
	{/each}
</ul>
