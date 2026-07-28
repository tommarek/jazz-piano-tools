import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	preprocess: vitePreprocess(),
	kit: {
		// A single-page app with no server at all: the database lives on the
		// device, so there is nothing for a server to do. The same build is the
		// web PWA and the payload inside the iOS and Android shells.
		adapter: adapter({
			pages: 'build',
			assets: 'build',
			fallback: 'index.html',
			precompress: false,
			strict: false
		}),
		// Capacitor serves from a custom scheme, so absolute asset paths must stay
		// relative to the document.
		paths: { relative: true },
		// Registered by hand, and only on the web: inside the native shell the app
		// is already local and the custom scheme has no service worker to speak of.
		serviceWorker: { register: false }
	}
};

export default config;
