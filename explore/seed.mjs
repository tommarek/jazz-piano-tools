/**
 * Seeds the scratch database with plausible history so the stats screens have
 * something real to draw. Not part of the app or the test suite — a harness for
 * manual exploration.
 *
 *   node explore/seed.mjs <db-path> <profile>
 *
 * profiles: history | gate-ready
 */
import Database from 'better-sqlite3';

const [, , dbPath, profile = 'history'] = process.argv;
const db = new Database(dbPath);
const DAY = 86_400_000;
const now = Date.now();

function rng(seed) {
	return () => {
		seed = (seed * 1664525 + 1013904223) % 4294967296;
		return seed / 4294967296;
	};
}
const rand = rng(42);

const cards = db.prepare('SELECT id, type, root_pitch_class AS pc FROM cards').all();
const byType = (t) => cards.filter((c) => c.type === t);

const insertReview = db.prepare(
	`INSERT INTO reviews (card_id, ts, grade, response_ms, correct, mode)
	 VALUES (?, ?, ?, ?, ?, 'srs')`
);
const upsertState = db.prepare(
	`INSERT OR REPLACE INTO card_state
	 (card_id, due, stability, difficulty, elapsed_days, scheduled_days, learning_steps,
	  reps, lapses, state, last_review, median_response_ms, consecutive_correct, mastery)
	 VALUES (?, ?, ?, ?, 0, 3, 0, ?, ?, 2, ?, ?, ?, ?)`
);
const upsertDay = db.prepare(
	`INSERT OR REPLACE INTO daily_stats (date, reviews, correct, median_response_ms, minutes)
	 VALUES (?, ?, ?, ?, ?)`
);

function dateKey(ts) {
	const d = new Date(ts);
	const p = (n) => String(n).padStart(2, '0');
	return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

const seed = db.transaction(() => {
	db.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM daily_stats;');

	const shellPool = [...byType('s2n'), ...byType('n2s'), ...byType('vl')];
	const chainPool = byType('chain').filter((c) => !c.id.endsWith(':minor'));

	// 30 days of practice, getting steadily faster.
	for (let day = 29; day >= 0; day--) {
		// A couple of rest days, so the streak and the gaps look real.
		if (day === 12 || day === 13) continue;
		const ts0 = now - day * DAY + 9 * 3600_000;
		const progress = (29 - day) / 29;
		const base = 5200 - 2600 * progress;
		const times = [];
		let correct = 0;
		const count = 18 + Math.floor(rand() * 10);

		for (let i = 0; i < count; i++) {
			const chain = i % 5 === 0;
			const card = chain
				? chainPool[Math.floor(rand() * chainPool.length)]
				: shellPool[Math.floor(rand() * shellPool.length)];
			const ms = Math.round((chain ? base * 2.6 : base) * (0.75 + rand() * 0.55));
			const ok = rand() > 0.14 - 0.06 * progress;
			if (ok) correct++;
			times.push(ms);
			insertReview.run(card.id, ts0 + i * 20_000, ok ? 3 : 1, ms, ok ? 1 : 0);
		}

		const sorted = [...times].sort((a, b) => a - b);
		upsertDay.run(
			dateKey(ts0),
			count,
			correct,
			sorted[Math.floor(sorted.length / 2)],
			Math.round((times.reduce((a, b) => a + b, 0) / 60_000) * 100) / 100
		);
	}

	// Card states: strong in white-note keys, weak in the flats — so the heatmap
	// has something to say.
	const strongKeys = profile === 'gate-ready' ? [...Array(12).keys()] : [0, 2, 4, 5, 7, 9, 11];
	for (const card of cards) {
		const isShell =
			card.type === 's2n' ||
			card.type === 'n2s' ||
			((card.type === 'chain' || card.type === 'vl') && !card.id.endsWith(':minor'));
		if (!isShell) continue;

		const strong = strongKeys.includes(card.pc);
		const r = rand();
		let mastery = 'new';
		let median = 3400;
		let streak = 1;
		if (strong && r > 0.25) {
			mastery = 'automatic';
			median = card.type === 'chain' ? 4200 : 1500;
			streak = 6;
		} else if (r > 0.4) {
			mastery = 'familiar';
			median = card.type === 'chain' ? 9000 : 3100;
			streak = 3;
		}
		upsertState.run(
			card.id,
			now + (1 + Math.floor(rand() * 10)) * DAY,
			8 + rand() * 20,
			5,
			5,
			0,
			now - DAY,
			median,
			streak,
			mastery
		);
	}

	// Chain history that decides the headline metric and the gate.
	const perChord = profile === 'gate-ready' ? 1500 : 2600;
	for (let i = 0; i < 26; i++) {
		insertReview.run(
			chainPool[i % chainPool.length].id,
			now - i * 3600_000,
			3,
			perChord * 3 + Math.round((rand() - 0.5) * 400),
			1
		);
	}
});

seed();
const counts = db.prepare('SELECT COUNT(*) n FROM reviews').get();
console.log(`seeded ${profile}: ${counts.n} reviews`);
db.close();
