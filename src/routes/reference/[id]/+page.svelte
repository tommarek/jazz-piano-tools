<script lang="ts">
	import ReferenceBody from '$lib/components/ReferenceBody.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head><title>{data.topic.title} · Voicings</title></svelte:head>

<a href="/reference" class="mb-3 inline-flex min-h-[44px] items-center text-xs text-accent">
	← Reference
</a>

<h1 class="text-lg font-semibold">{data.topic.title}</h1>
<p class="mb-4 text-xs text-muted">{data.topic.blurb}</p>

<ReferenceBody topic={data.topic} />
