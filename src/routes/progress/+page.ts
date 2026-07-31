import { addDays, dateKey } from '$lib/data/queue';
import { earStats, getStats } from '$lib/data/stats';
import { QUALITY_LABEL, type Quality } from '$lib/music/voicings';
import type { PageLoad } from './$types';

export const load: PageLoad = async () => {
	const now = Date.now();
	const [stats, ear] = await Promise.all([getStats(now, 30), earStats(now, 30)]);
	return {
		...stats,
		// The ear figures are computed over their own population and never folded
		// into the ones above: the charts up there are about reading speed.
		ear: { ...ear, series: densify(ear.byDay, now, 30) },
		// Fill in the days with no reviews so gaps read as gaps, not as flat lines.
		series: densify(stats.byDay, now, 30),
		qualityLabels: Object.fromEntries(
			Object.entries(QUALITY_LABEL) as [Quality, string][]
		) as Record<string, string>
	};
};

function densify(
	byDay: { date: string; reviews: number; accuracy: number; medianResponseMs: number | null }[],
	now: number,
	days: number
) {
	const map = new Map(byDay.map((d) => [d.date, d]));
	const out: { date: string; short: string; medianMs: number | null; accuracy: number | null }[] =
		[];
	for (let i = days - 1; i >= 0; i--) {
		// Calendar-day steps — see lastSevenDays on the Today loader.
		const d = new Date(addDays(now, -i));
		const pad = (n: number) => String(n).padStart(2, '0');
		const key = dateKey(d.getTime());
		const row = map.get(key);
		out.push({
			date: key,
			short: `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`,
			medianMs: row?.medianResponseMs ?? null,
			accuracy: row && row.reviews > 0 ? row.accuracy : null
		});
	}
	return out;
}
