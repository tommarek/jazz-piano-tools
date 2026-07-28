/**
 * SQLite-compiled-to-WASM, for the browser, the PWA and the test suite.
 *
 * The whole database is held in memory and written back through a
 * {@link Persistence} as a single blob. That is only reasonable because this
 * database is small — 1296 cards plus a review log that grows by a few hundred
 * rows a month — and it buys one code path that behaves identically to the
 * native driver, and one that unit tests can drive with no browser at all.
 *
 * Writes are debounced, and flushed on pagehide, so closing the tab mid-session
 * cannot lose the review you just answered.
 */

import initSqlJs, { type Database, type SqlJsStatic } from 'sql.js';
import type { Db } from './driver';
import { SCHEMA } from './driver';
import { ephemeral, indexedDbPersistence, type Persistence } from './persistence';

const PERSIST_DEBOUNCE_MS = 400;

let SQL: SqlJsStatic | null = null;

/**
 * The .wasm is fetched by URL in app builds, where the bundler fingerprints it.
 * Tests run under Node with no fetch-able URL, so they hand in the bytes.
 */
async function loadSqlJs(wasmBinary?: ArrayBuffer | Uint8Array): Promise<SqlJsStatic> {
	if (SQL) return SQL;
	if (wasmBinary) {
		SQL = await initSqlJs({ wasmBinary } as Parameters<typeof initSqlJs>[0]);
	} else {
		const wasmUrl = (await import('sql.js/dist/sql-wasm.wasm?url')).default as string;
		SQL = await initSqlJs({ locateFile: () => wasmUrl });
	}
	return SQL;
}

export async function openWasmDb(
	persistence: Persistence = indexedDbPersistence,
	wasmBinary?: ArrayBuffer | Uint8Array
): Promise<Db> {
	const sqljs = await loadSqlJs(wasmBinary);
	const existing = await persistence.load();
	const database: Database = existing ? new sqljs.Database(existing) : new sqljs.Database();
	database.run('PRAGMA foreign_keys = ON;');
	database.run(SCHEMA);

	let timer: ReturnType<typeof setTimeout> | undefined;
	let inTransaction = false;

	async function flush(): Promise<void> {
		if (timer) {
			clearTimeout(timer);
			timer = undefined;
		}
		await persistence.save(database.export());
	}

	function schedule() {
		// Mid-transaction snapshots would persist a half-finished write.
		if (inTransaction) return;
		if (timer) clearTimeout(timer);
		timer = setTimeout(() => void flush(), PERSIST_DEBOUNCE_MS);
	}

	if (typeof window !== 'undefined' && persistence !== ephemeral) {
		// pagehide rather than beforeunload: it is the one iOS actually fires.
		window.addEventListener('pagehide', () => void flush());
		document.addEventListener('visibilitychange', () => {
			if (document.visibilityState === 'hidden') void flush();
		});
	}

	function rows<T>(sql: string, params: unknown[]): T[] {
		const stmt = database.prepare(sql);
		try {
			stmt.bind(params as never);
			const out: T[] = [];
			while (stmt.step()) out.push(stmt.getAsObject() as T);
			return out;
		} finally {
			stmt.free();
		}
	}

	return {
		async run(sql, params = []) {
			database.run(sql, params as never);
			schedule();
		},
		async all<T>(sql: string, params: unknown[] = []) {
			return rows<T>(sql, params);
		},
		async get<T>(sql: string, params: unknown[] = []) {
			return rows<T>(sql, params)[0];
		},
		async exec(sql) {
			database.run(sql);
			schedule();
		},
		async tx<T>(fn: () => Promise<T>) {
			database.run('BEGIN');
			inTransaction = true;
			try {
				const result = await fn();
				database.run('COMMIT');
				return result;
			} catch (err) {
				database.run('ROLLBACK');
				throw err;
			} finally {
				inTransaction = false;
				schedule();
			}
		},
		persist: flush,
		async serialise() {
			return database.export();
		},
		async restore(bytes) {
			await persistence.save(bytes);
			// The caller reloads; swapping the live handle underneath running
			// queries would be worse than a restart.
		},
		async close() {
			await flush();
			database.close();
		}
	};
}

/** A throwaway database with no persistence, for tests. */
export function openMemoryDb(wasmBinary?: ArrayBuffer | Uint8Array): Promise<Db> {
	return openWasmDb(ephemeral, wasmBinary);
}
