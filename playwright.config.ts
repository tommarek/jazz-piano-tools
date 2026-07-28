import { defineConfig, devices } from '@playwright/test';

const PORT = 4173;

export default defineConfig({
	testDir: 'tests/e2e',
	fullyParallel: false,
	// The suite shares one server process and one SQLite file, and each spec
	// resets it — running them in parallel would have them wipe each other.
	workers: 1,
	forbidOnly: !!process.env.CI,
	retries: process.env.CI ? 1 : 0,
	reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
	use: {
		baseURL: `http://127.0.0.1:${PORT}`,
		trace: 'retain-on-failure',
		// The phone is the primary target, so that is what the suite runs on.
		...devices['iPhone 14 Pro'],
		// devices[] pins WebKit; Chromium is what is installed by default in CI
		// and the app uses no WebKit-specific behaviour.
		defaultBrowserType: 'chromium'
	},
	webServer: {
		// A static file server: the app has no backend, and its database lives in
		// the browser. VITE_VT_TEST compiles in the reset hook the suite drives.
		command: `VITE_VT_TEST=1 npm run build && npx sirv-cli build --single --host 127.0.0.1 --port ${PORT}`,
		port: PORT,
		reuseExistingServer: !process.env.CI,
		timeout: 180_000
	}
});
