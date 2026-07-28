import { getSettings } from '$lib/data/settings';
import { CARD_TYPE_HINT, CARD_TYPE_LABEL, STAGES } from '$lib/music/cards';
import { QUALITIES, QUALITY_LABEL } from '$lib/music/voicings';
import type { PageLoad } from './$types';

export const load: PageLoad = async () => ({
	settings: await getSettings(),
	qualities: QUALITIES.map((q) => ({ value: q, label: QUALITY_LABEL[q] })),
	// Drill toggles grouped by stage, in path order.
	stages: STAGES.map((stage) => ({
		n: stage.n,
		title: stage.title,
		types: stage.types.map((t) => ({
			value: t,
			label: CARD_TYPE_LABEL[t],
			hint: CARD_TYPE_HINT[t]
		}))
	}))
});
