<script lang="ts">
	/**
	 * Something failed while loading a screen.
	 *
	 * There is no server and no crash reporter, so if this page is not specific
	 * the failure is invisible — the app would just show a blank "500". It shows
	 * the actual message, and offers the two things that actually recover: try
	 * again, or go back to a screen that works.
	 */
	import { page } from '$app/state';

	const message = $derived(page.error?.message ?? 'Something went wrong.');
	const isNotFound = $derived(page.status === 404);
</script>

<svelte:head><title>Problem · Comp</title></svelte:head>

<section class="mt-6 border-l-2 border-felt bg-felt/10 py-3 pr-3 pl-4" data-testid="error-page">
	<h1 class="text-base font-semibold text-felt-ink">
		{isNotFound ? 'Nothing here' : 'That screen failed to load'}
	</h1>
	<p class="mt-2 text-sm break-words" data-testid="error-message">{message}</p>

	{#if !isNotFound}
		<p class="mt-2 text-xs text-muted">
			Your practice history is stored on this device and is not affected by this.
		</p>
	{/if}

	<div class="mt-4 flex gap-2">
		<button
			type="button"
			class="eyebrow min-h-[48px] flex-1 rounded-sm bg-brass !text-on-brass"
			onclick={() => location.reload()}>Try again</button
		>
		<a
			href="/"
			class="eyebrow flex min-h-[48px] flex-1 items-center justify-center rounded-sm border border-line"
			>Theory</a
		>
	</div>
</section>
