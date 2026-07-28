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

	const NAV = [
		{ href: '/', label: 'Today', icon: '◉' },
		{ href: '/progress', label: 'Progress', icon: '▤' },
		{ href: '/reference', label: 'Reference', icon: '☰' },
		{ href: '/settings', label: 'Settings', icon: '⚙' }
	];
</script>

<div class="mx-auto flex min-h-dvh w-full max-w-md flex-col">
	<main
		class="flex-1 px-4 pt-[max(1rem,env(safe-area-inset-top))]"
		class:pb-24={!inSession}
		class:pb-4={inSession}
	>
		{@render children()}
	</main>

	{#if !inSession}
		<nav
			class="fixed inset-x-0 bottom-0 mx-auto flex w-full max-w-md border-t border-line bg-surface pb-[env(safe-area-inset-bottom)]"
			aria-label="Main"
		>
			{#each NAV as item (item.href)}
				{@const active =
					item.href === '/' ? page.url.pathname === '/' : page.url.pathname.startsWith(item.href)}
				<a
					href={item.href}
					class="flex min-h-[56px] flex-1 flex-col items-center justify-center gap-0.5 text-[11px]"
					class:text-accent={active}
					class:text-muted={!active}
					aria-current={active ? 'page' : undefined}
				>
					<span aria-hidden="true" class="text-base leading-none">{item.icon}</span>
					{item.label}
				</a>
			{/each}
		</nav>
	{/if}
</div>
