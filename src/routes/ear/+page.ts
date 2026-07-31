import { deckCounts } from '$lib/data/queue';
import { evaluateEarPath } from '$lib/data/stages';
import { earStats } from '$lib/data/stats';
import { getSettings } from '$lib/data/settings';
import type { PageLoad } from './$types';

export const load: PageLoad = async () => {
	const now = Date.now();
	// Evaluated before the decks are counted, so a session started right after
	// the qualities stage opens already contains its cards.
	const path = await evaluateEarPath();
	const [decks, stats, settings] = await Promise.all([
		deckCounts('ear', now),
		earStats(),
		getSettings()
	]);
	return { decks, path, stats, soundEnabled: settings.soundEnabled };
};
