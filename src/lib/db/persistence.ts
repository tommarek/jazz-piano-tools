/**
 * Where the WASM driver keeps its bytes between runs.
 *
 * Split out so the same SQLite build can run against IndexedDB in a browser and
 * against nothing at all in a unit test — which is what lets the test suite
 * exercise the real SQL rather than a mock of it.
 */

export interface Persistence {
	load(): Promise<Uint8Array | null>;
	save(bytes: Uint8Array): Promise<void>;
}

/** Keeps nothing. Used by tests and by throwaway in-memory databases. */
export const ephemeral: Persistence = {
	async load() {
		return null;
	},
	async save() {
		// Deliberately nothing.
	}
};

const DB_NAME = 'voicings';
const STORE = 'db';
const KEY = 'main';

function openIdb(): Promise<IDBDatabase> {
	return new Promise((resolve, reject) => {
		const req = indexedDB.open(DB_NAME, 1);
		req.onupgradeneeded = () => req.result.createObjectStore(STORE);
		req.onsuccess = () => resolve(req.result);
		req.onerror = () => reject(req.error);
	});
}

export const indexedDbPersistence: Persistence = {
	async load() {
		const idb = await openIdb();
		return new Promise((resolve, reject) => {
			const req = idb.transaction(STORE, 'readonly').objectStore(STORE).get(KEY);
			req.onsuccess = () => resolve((req.result as Uint8Array) ?? null);
			req.onerror = () => reject(req.error);
		});
	},
	async save(bytes) {
		const idb = await openIdb();
		return new Promise((resolve, reject) => {
			const tx = idb.transaction(STORE, 'readwrite');
			tx.objectStore(STORE).put(bytes, KEY);
			tx.oncomplete = () => resolve();
			tx.onerror = () => reject(tx.error);
		});
	}
};
