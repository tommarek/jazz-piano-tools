import { addDays, dateKey, deckCounts, queueSummary } from '$lib/data/queue';
import { getStats } from '$lib/data/stats';
import { evaluateStages } from '$lib/data/stages';
import type { PageLoad } from './$types';

export const load: PageLoad = async () => {
	const now = Date.now();
	// Evaluated before the queue is counted, so a session started right after
	// a stage opens already contains its cards.
	const stages = await evaluateStages();
	const [stats, summary, decks] = await Promise.all([
		getStats(now, 14),
		queueSummary(now),
		deckCounts('theory', now)
	]);

	return {
		summary,
		decks,
		headline: stats.headline,
		today: stats.today,
		streakDays: stats.streakDays,
		week: lastSevenDays(stats.byDay, now),
		stages
	};
};

// The strip answers "did you practise", so it counts every attempt including
// speed rounds — not daily_stats' sprint-free quality column.
function lastSevenDays(byDay: { date: string; attempts: number }[], now: number) {
	const map = new Map(byDay.map((d) => [d.date, d.attempts]));
	const out: { date: string; label: string; reviews: number }[] = [];
	for (let i = 6; i >= 0; i--) {
		// queue.ts's own day, not now − i·24h: a DST day would duplicate or skip a
		// date and break the keyed {#each}, and a key computed any other way than
		// daily_stats' would look up rows that are not there.
		const day = addDays(now, -i);
		const key = dateKey(day);
		out.push({
			date: key,
			label: ['S', 'M', 'T', 'W', 'T', 'F', 'S'][new Date(day).getDay()],
			reviews: map.get(key) ?? 0
		});
	}
	return out;
}
