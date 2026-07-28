/// <reference types="@sveltejs/kit" />
/// <reference lib="webworker" />

/**
 * App-shell cache.
 *
 * Navigations are network-first with a cached fallback, so a fresh deploy is
 * picked up immediately but the app still opens on the underground. API calls
 * are never cached — a stale queue or stale stats would be worse than an error,
 * and reviews taken offline are held in the client outbox instead.
 */

import { build, files, version } from '$service-worker';

const sw = self as unknown as ServiceWorkerGlobalScope;

const CACHE = `voicings-${version}`;
const PRECACHE = [...build, ...files];
/** The fallback document for any navigation that cannot reach the network. */
const SHELL = '/';

sw.addEventListener('install', (event) => {
	event.waitUntil(
		caches
			.open(CACHE)
			// The shell is fetched at install time, so the very first offline load
			// works — waiting for a controlled navigation to warm it would leave a
			// window where the app is installed but blank.
			.then((cache) => cache.addAll([...PRECACHE, SHELL]))
			.then(() => sw.skipWaiting())
	);
});

sw.addEventListener('activate', (event) => {
	event.waitUntil(
		caches
			.keys()
			.then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
			.then(() => sw.clients.claim())
	);
});

sw.addEventListener('fetch', (event) => {
	const { request } = event;
	if (request.method !== 'GET') return;

	const url = new URL(request.url);
	if (url.origin !== sw.location.origin) return;
	if (url.pathname.startsWith('/api/')) return;

	// Hashed build assets never change under a given URL.
	if (PRECACHE.includes(url.pathname)) {
		event.respondWith(
			caches.match(request).then((hit) => hit ?? fetch(request))
		);
		return;
	}

	event.respondWith(
		fetch(request)
			.then((response) => {
				if (response.ok && response.type === 'basic') {
					const copy = response.clone();
					caches.open(CACHE).then((cache) => cache.put(request, copy));
				}
				return response;
			})
			.catch(async () => {
				const cached = await caches.match(request);
				if (cached) return cached;
				// Any unseen route falls back to the shell rather than the browser error page.
				const shell = await caches.match(SHELL);
				if (shell) return shell;
				return new Response('Offline', { status: 503, statusText: 'Offline' });
			})
	);
});
