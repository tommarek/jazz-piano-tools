/**
 * Test-only handles on the device database.
 *
 * With no server there is no endpoint for Playwright to POST a reset to, so the
 * suite drives the app through `window.__voicings` instead. Compiled in only
 * when VITE_VT_TEST is set at build time — the store builds never define it, so
 * the whole module is dead code and gets dropped.
 */

import { resetAll } from '$lib/db';
import { saveSettings, type Settings } from './settings';

export const TEST_HOOKS_ENABLED = import.meta.env.VITE_VT_TEST === '1';

export function installTestHooks(): void {
	if (!TEST_HOOKS_ENABLED || typeof window === 'undefined') return;

	(window as unknown as Record<string, unknown>).__voicings = {
		async reset(settings: Partial<Settings> = {}) {
			await resetAll();
			// Tests exercise the whole deck by default; the path's own specs
			// override unlockedStages to test the progression.
			await saveSettings({ unlockedStages: 4, ...settings });
		}
	};
}
