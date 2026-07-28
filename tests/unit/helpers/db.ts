/**
 * Opens the same WASM SQLite the browser uses, with persistence off and the
 * .wasm read straight off disk — Node has no URL to fetch it from.
 *
 * This is what lets the unit suite exercise the real SQL rather than a mock of
 * it: the queries under test are byte-for-byte the ones that ship.
 */
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { openMemoryDb } from '../../../src/lib/db/wasm';
import { useDb } from '../../../src/lib/db';

const require = createRequire(import.meta.url);

export async function useMemoryDb() {
	const bytes = await readFile(require.resolve('sql.js/dist/sql-wasm.wasm'));
	const conn = await openMemoryDb(bytes);
	await useDb(conn);
	return conn;
}
