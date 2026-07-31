/**
 * Import is the one operation that can destroy a user's only copy of their
 * practice history. These tests pin the rule that makes it survivable: nothing
 * is deleted until the whole payload has been read, and the wipe rides in the
 * same transaction as the inserts.
 */

import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { useMemoryDb } from './helpers/db';
import { db } from '../../src/lib/db';
import { buildExport, importExport, type ExportPayload } from '../../src/lib/data/export';

beforeAll(async () => {
	await useMemoryDb();
});

afterAll(async () => {
	await (await db()).close();
});

async function seed() {
	const conn = await db();
	await conn.exec('DELETE FROM reviews; DELETE FROM card_state; DELETE FROM settings;');
	await conn.run(
		`INSERT INTO reviews (card_id, ts, grade, response_ms, correct, mode)
		 VALUES ('gt:C:m7', 1000, 3, 2400, 1, 'srs')`
	);
	await conn.run(
		`INSERT INTO card_state
		 (card_id, due, stability, difficulty, median_response_ms, consecutive_correct, mastery)
		 VALUES ('gt:C:m7', 2000, 1.5, 5, 2400, 1, 'familiar')`
	);
}

async function counts() {
	const conn = await db();
	const row = await conn.get<{ reviews: number; states: number }>(
		`SELECT (SELECT COUNT(*) FROM reviews) AS reviews,
		        (SELECT COUNT(*) FROM card_state) AS states`
	);
	return row!;
}

beforeEach(seed);

describe('importing a malformed backup', () => {
	// Every one of these is JSON that got as far as saying "version: 1", which
	// is exactly what a truncated or hand-edited backup looks like.
	const bad: [string, unknown][] = [
		['nothing but the version stamp', { version: 1 }],
		['a missing table', { ...emptyPayload(), reviews: undefined }],
		['a table that is not an array', { ...emptyPayload(), cardState: {} }],
		['settings replaced by a scalar', { ...emptyPayload(), settings: 'nope' }],
		['a newer format', { ...emptyPayload(), version: 2 }]
	];

	for (const [name, payload] of bad) {
		it(`throws on ${name} and leaves the existing history untouched`, async () => {
			await expect(importExport(payload as ExportPayload)).rejects.toThrow();
			expect(await counts()).toEqual({ reviews: 1, states: 1 });
		});
	}

	it('ignores column names the schema does not have', async () => {
		// The insert statement is built from the file's own keys, so a key can
		// carry SQL of its own. Nothing here may run, and the row's real columns
		// still import.
		const payload = {
			...emptyPayload(),
			reviews: [
				{
					card_id: 'gt:D:m7',
					ts: 5000,
					grade: 3,
					response_ms: 1000,
					correct: 1,
					mode: 'srs',
					"x) VALUES ('gt:E:m7',1,1,1,1,'srs'); DELETE FROM reviews; --": 1
				}
			]
		};
		const result = await importExport(payload as ExportPayload);
		expect(result.reviews).toBe(1);
		const conn = await db();
		const row = await conn.get<{ card_id: string; ts: number }>('SELECT card_id, ts FROM reviews');
		expect(row).toEqual({ card_id: 'gt:D:m7', ts: 5000 });
	});

	it('rolls the wipe back when a row fails half way through', async () => {
		// The second review is missing its NOT NULL ts, so the insert throws
		// after the deletes and after a good row has already gone in.
		const payload = {
			...emptyPayload(),
			reviews: [
				{ card_id: 'gt:D:m7', ts: 5000, grade: 3, response_ms: 1000, correct: 1, mode: 'srs' },
				{ card_id: 'gt:E:m7', grade: 3, response_ms: 1000, correct: 1, mode: 'srs' }
			]
		};
		await expect(importExport(payload as ExportPayload)).rejects.toThrow();
		expect(await counts()).toEqual({ reviews: 1, states: 1 });
		const conn = await db();
		const row = await conn.get<{ card_id: string }>('SELECT card_id FROM reviews');
		expect(row?.card_id).toBe('gt:C:m7');
	});
});

describe('importing a well-formed backup', () => {
	it('replaces the history with the payload', async () => {
		const payload = {
			...emptyPayload(),
			reviews: [
				{ card_id: 'gt:D:m7', ts: 5000, grade: 3, response_ms: 1000, correct: 1, mode: 'srs' }
			]
		};
		const result = await importExport(payload as ExportPayload);
		expect(result.reviews).toBe(1);
		expect(await counts()).toEqual({ reviews: 1, states: 0 });
	});

	it('round-trips what buildExport produced', async () => {
		const snapshot = await buildExport();
		await importExport(snapshot);
		expect(await counts()).toEqual({ reviews: 1, states: 1 });
	});

	it('drops history for cards this build no longer has', async () => {
		// A backup written before the root-shell drills were cut still carries
		// their reviews. Card rows are deliberately not restored, so the
		// catalogue sync's purge — which walks the cards table — can never reach
		// these; left in, they would keep feeding the chain median and the stage
		// gates from a drill nobody can be dealt.
		const payload = {
			...emptyPayload(),
			reviews: [
				{ card_id: 'gt:D:m7', ts: 5000, grade: 3, response_ms: 1000, correct: 1, mode: 'srs' },
				{ card_id: 'chain:C:737', ts: 6000, grade: 3, response_ms: 900, correct: 1, mode: 'srs' }
			],
			cardState: [
				{
					card_id: 'chain:C:737',
					due: 1,
					stability: 1,
					difficulty: 5,
					median_response_ms: 900,
					consecutive_correct: 1,
					mastery: 'automatic'
				}
			]
		};
		const result = await importExport(payload as ExportPayload);
		expect(await counts()).toEqual({ reviews: 1, states: 0 });
		// What the settings screen prints. Reporting the file's row count would
		// promise a review that was dropped a statement earlier.
		expect(result.reviews).toBe(1);
		const conn = await db();
		const row = await conn.get<{ card_id: string }>('SELECT card_id FROM reviews');
		expect(row?.card_id).toBe('gt:D:m7');
	});
});

function emptyPayload() {
	return {
		exportedAt: new Date().toISOString(),
		version: 1,
		settings: {},
		cards: [],
		cardState: [],
		reviews: [],
		sessions: [],
		dailyStats: []
	};
}
