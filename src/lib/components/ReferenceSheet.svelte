<script lang="ts">
	/**
	 * The reference, shown over a running session.
	 *
	 * A dialog rather than a link, because the session queue lives in this
	 * component's state — navigating away would throw the session away. Native
	 * <dialog> brings focus trapping and Escape-to-close with it.
	 */
	import ReferenceBody from './ReferenceBody.svelte';
	import { TOPICS_BY_ID } from '$lib/content/reference';

	interface Props {
		topicId: string | null;
		onclose: () => void;
	}

	let { topicId, onclose }: Props = $props();
	let dialog = $state<HTMLDialogElement | null>(null);

	const topic = $derived(topicId ? (TOPICS_BY_ID[topicId] ?? null) : null);

	$effect(() => {
		if (!dialog) return;
		if (topic && !dialog.open) dialog.showModal();
		if (!topic && dialog.open) dialog.close();
	});
</script>

<dialog
	bind:this={dialog}
	class="w-full max-w-md rounded-t-2xl border border-line bg-surface p-0 text-ink backdrop:bg-black/60"
	aria-label={topic ? topic.title : 'Reference'}
	onclose={onclose}
	data-testid="reference-sheet"
>
	{#if topic}
		<div class="flex items-start justify-between gap-3 border-b border-line p-4">
			<div>
				<h2 class="text-base font-semibold">{topic.title}</h2>
				<p class="text-xs text-muted">{topic.blurb}</p>
			</div>
			<button
				type="button"
				class="-mr-2 -mt-2 min-h-[44px] min-w-[44px] shrink-0 text-sm text-muted"
				onclick={() => dialog?.close()}
				data-testid="close-reference"
				aria-label="Close">✕</button
			>
		</div>
		<!-- tabindex, because a scroll container that only a mouse can reach is
		     unusable from a keyboard. Svelte's linter dislikes tabindex on a
		     non-interactive element; axe's scrollable-region-focusable rule
		     requires it, and that rule is the one describing a real user. -->
		<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
		<div
			class="max-h-[70dvh] overflow-y-auto p-4"
			role="region"
			aria-label="{topic.title} — reference"
			tabindex="0"
		>
			<ReferenceBody {topic} showRelated={false} />
		</div>
	{/if}
</dialog>

<style>
	dialog {
		/* Bottom sheet on a phone; the browser centres it otherwise. */
		margin: auto auto 0;
	}
	dialog::backdrop {
		background: rgb(0 0 0 / 0.6);
	}
</style>
