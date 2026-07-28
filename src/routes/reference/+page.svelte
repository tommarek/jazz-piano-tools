<script lang="ts">
	import { TOPICS } from '$lib/content/reference';
</script>

<svelte:head><title>Reference · Voicings</title></svelte:head>

<h1 class="mb-1 text-lg font-semibold">Reference</h1>
<p class="mb-4 text-xs text-muted">
	The theory behind the drills. Also reachable from any card once you've answered it.
</p>

<ul class="space-y-2">
	{#each TOPICS as topic (topic.id)}
		<li>
			<a
				href="/reference/{topic.id}"
				class="block rounded-xl border border-line bg-surface p-4"
				data-testid="topic-{topic.id}"
			>
				<span class="block text-sm font-semibold">{topic.title}</span>
				<span class="mt-0.5 block text-xs text-muted">{topic.blurb}</span>
			</a>
		</li>
	{/each}
</ul>
