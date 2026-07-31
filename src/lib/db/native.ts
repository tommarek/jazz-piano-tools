/**
 * Real SQLite on iOS and Android, via @capacitor-community/sqlite.
 *
 * Writes go straight to a file the OS backs up, so nothing is held in memory
 * waiting to be flushed. This is the driver that matters for durability: losing
 * somebody's review history is not recoverable and not forgivable.
 */

import { CapacitorSQLite, SQLiteConnection, type SQLiteDBConnection } from '@capacitor-community/sqlite';
import type { Db } from './driver';
import { SCHEMA } from './driver';

const DB_NAME = 'voicings';

export async function openNativeDb(): Promise<Db> {
	const sqlite = new SQLiteConnection(CapacitorSQLite);

	// A connection left behind by a previous run would make createConnection throw.
	const check = await sqlite.checkConnectionsConsistency().catch(() => ({ result: false }));
	const exists = await sqlite.isConnection(DB_NAME, false).catch(() => ({ result: false }));
	if (check.result && exists.result) {
		await sqlite.closeConnection(DB_NAME, false).catch(() => undefined);
	}

	const conn: SQLiteDBConnection = await sqlite.createConnection(
		DB_NAME,
		false,
		'no-encryption',
		1,
		false
	);
	await conn.open();
	// `execute` is for statements that return nothing. `PRAGMA journal_mode`
	// returns the resulting mode as a row, and Android's plugin rejects it with
	// "Queries can be performed using SQLiteDatabase query or rawQuery methods
	// only" — so it has to go through `query`. The plugin already opens in WAL;
	// this makes sure of it without assuming.
	await conn.query('PRAGMA journal_mode = WAL;');
	// transaction=false, and not for the reason exec() below has: SQLite makes
	// `PRAGMA foreign_keys` a silent no-op inside a transaction, and the plugin
	// wraps `execute` in a BEGIN by default — so left alone this pragma takes
	// effect on the wasm driver and nowhere else, and the divergence would only
	// ever show up on a device.
	await conn.execute('PRAGMA foreign_keys = ON;', false);
	await conn.execute(SCHEMA);

	return {
		async run(sql, params = []) {
			await conn.run(sql, params as never[], false);
		},
		async all<T>(sql: string, params: unknown[] = []) {
			const res = await conn.query(sql, params as never[]);
			return (res.values ?? []) as T[];
		},
		async get<T>(sql: string, params: unknown[] = []) {
			const res = await conn.query(sql, params as never[]);
			return (res.values ?? [])[0] as T | undefined;
		},
		async exec(sql) {
			// transaction=false, like run() above: the plugin wraps `execute` in a
			// BEGIN of its own by default, and every exec() in the app runs inside
			// conn.tx already — a nested BEGIN throws on both platforms, and
			// Android's finally then rolls back the transaction we own.
			await conn.execute(sql, false);
		},
		async tx<T>(fn: () => Promise<T>) {
			await conn.beginTransaction();
			try {
				const result = await fn();
				await conn.commitTransaction();
				return result;
			} catch (err) {
				await conn.rollbackTransaction().catch(() => undefined);
				throw err;
			}
		},
		async persist() {
			// Written through already.
		},
		async close() {
			await conn.close();
			await sqlite.closeConnection(DB_NAME, false);
		}
	};
}
