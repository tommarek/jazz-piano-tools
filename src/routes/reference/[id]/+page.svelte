<script lang="ts">
	import ReferenceBody from '$lib/components/ReferenceBody.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head><title>{data.topic.title} · Comp</title></svelte:head>

<a href="/reference" class="eyebrow mb-2 inline-flex min-h-[44px] items-center !text-brass">
	← Reference
</a>

<h1 class="text-xl font-bold uppercase" style="font-stretch:112%; letter-spacing:0.1em">
	{data.topic.title}
</h1>
<div class="rule-brass mt-1.5 mb-2"></div>
<p class="mb-5 text-xs leading-relaxed text-muted">{data.topic.blurb}</p>

<ReferenceBody topic={data.topic} />
