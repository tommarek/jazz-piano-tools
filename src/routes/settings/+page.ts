import { getSettings } from '$lib/data/settings';
import { CARD_TYPE_HINT, CARD_TYPE_LABEL, EAR_STAGES, STAGES, type Stage } from '$lib/music/cards';
import { QUALITIES, QUALITY_LABEL } from '$lib/music/voicings';
import type { PageLoad } from './$types';

/** Drill toggles grouped by stage, in path order — one list per section. */
const toRows = (stages: Stage[]) =>
	stages.map((stage) => ({
		n: stage.n,
		title: stage.title,
		types: stage.types.map((t) => ({
			value: t,
			label: CARD_TYPE_LABEL[t],
			hint: CARD_TYPE_HINT[t]
		}))
	}));

export const load: PageLoad = async () => ({
	settings: await getSettings(),
	qualities: QUALITIES.map((q) => ({ value: q, label: QUALITY_LABEL[q] })),
	stages: toRows(STAGES),
	earStages: toRows(EAR_STAGES)
});
