<script lang="ts">
	import '../app.css';
	import { page } from '$app/state';
	import { onMount } from 'svelte';
	import { installTestHooks } from '$lib/data/testhooks';
	import { Capacitor } from '@capacitor/core';
	import { dev } from '$app/environment';

	let { children } = $props();

	const inSession = $derived(page.url.pathname.startsWith('/session'));

	onMount(() => {
		installTestHooks();
		if (!Capacitor.isNativePlatform() && 'serviceWorker' in navigator && !dev) {
			void navigator.serviceWorker.register('./service-worker.js', { scope: './' });
		}
	});

	// No icons. Five glyphs picked from whatever a font happens to carry say
	// nothing about this app, and the words are shorter to read than a symbol is
	// to decode. The active tab is marked the way a stave marks a line: a brass
	// rule laid across the top of it.
	// Five items on a 320dp phone, so the labels are short words rather than
	// short sentences. The first two are the app's two halves and are named for
	// what is in them — the app itself is Comp, which appears in the title bar
	// and the launcher rather than taking a tab of its own.
	const NAV = [
		{ href: '/', label: 'Theory' },
		{ href: '/ear', label: 'Ear' },
		{ href: '/progress', label: 'Progress' },
		{ href: '/reference', label: 'Reference' },
		{ href: '/settings', label: 'Settings' }
	];
</script>

<div class="mx-auto flex min-h-dvh w-full max-w-md flex-col">
	<main
		class="flex-1 px-4 pt-[var(--pad-top)]"
		class:pb-24={!inSession}
		class:pb-4={inSession}
	>
		{@render children()}
	</main>

	{#if !inSession}
		<nav
			class="fixed inset-x-0 bottom-0 mx-auto flex w-full max-w-md border-t border-line bg-bg/95 backdrop-blur pb-[env(safe-area-inset-bottom)]"
			aria-label="Main"
		>
			{#each NAV as item (item.href)}
				{@const active =
					item.href === '/' ? page.url.pathname === '/' : page.url.pathname.startsWith(item.href)}
				<a
					href={item.href}
					class="relative flex min-h-[56px] flex-1 items-center justify-center"
					aria-current={active ? 'page' : undefined}
				>
					{#if active}
						<span
							aria-hidden="true"
							class="absolute inset-x-4 top-0 h-[2px] bg-brass"
						></span>
					{/if}
					<span
						class="eyebrow !tracking-[0.08em] !text-[9px]"
						class:!text-brass={active}>{item.label}</span
					>
				</a>
			{/each}
		</nav>
	{/if}
</div>
