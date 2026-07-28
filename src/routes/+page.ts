import { queueSummary } from '$lib/data/queue';
import { getStats } from '$lib/data/stats';
import { evaluateStages } from '$lib/data/stages';
import type { PageLoad } from './$types';

export const load: PageLoad = async () => {
	const now = Date.now();
	// Evaluated before the queue is counted, so a session started right after
	// a stage opens already contains its cards.
	const stages = await evaluateStages();
	const [stats, summary] = await Promise.all([getStats(now, 14), queueSummary(now)]);

	return {
		summary,
		headline: stats.headline,
		today: stats.today,
		streakDays: stats.streakDays,
		week: lastSevenDays(stats.byDay, now),
		stages
	};
};

function lastSevenDays(byDay: { date: string; reviews: number }[], now: number) {
	const map = new Map(byDay.map((d) => [d.date, d.reviews]));
	const out: { date: string; label: string; reviews: number }[] = [];
	for (let i = 6; i >= 0; i--) {
		// Calendar-day steps, not now − i·24h: a DST day would duplicate or skip
		// a date and break the keyed {#each} on the week strip.
		const d = new Date(now);
		d.setHours(0, 0, 0, 0);
		d.setDate(d.getDate() - i);
		const pad = (n: number) => String(n).padStart(2, '0');
		const key = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
		out.push({
			date: key,
			label: ['S', 'M', 'T', 'W', 'T', 'F', 'S'][d.getDay()],
			reviews: map.get(key) ?? 0
		});
	}
	return out;
}
