/**
 * The database seam.
 *
 * There is no server any more: the database lives on the device. Two drivers
 * sit behind this interface — real native SQLite on iOS and Android, and
 * SQLite-compiled-to-WASM in a browser — so every line of SQL in the app is
 * written once and runs on all three.
 *
 * Everything is async because the native plugin is. That is the only concession
 * the interface makes to either implementation.
 */

export interface Db {
	/** Run a statement for its effect. */
	run(sql: string, params?: unknown[]): Promise<void>;
	/** Run a query and return every row. */
	all<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>;
	/** Run a query and return the first row, or undefined. */
	get<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T | undefined>;
	/** Execute a multi-statement script (schema DDL). */
	exec(sql: string): Promise<void>;
	/**
	 * Run `fn` inside a transaction, rolling back if it throws. Not reentrant —
	 * SQLite has no nested transactions and neither does this.
	 */
	tx<T>(fn: () => Promise<T>): Promise<T>;
	/**
	 * Flush to durable storage. A no-op on drivers that write through; the WASM
	 * driver holds the database in memory and needs telling.
	 */
	persist(): Promise<void>;
	/** Whole database as bytes, for backup and export. */
	serialise(): Promise<Uint8Array>;
	/** Replace the whole database, for restore and import. */
	restore(bytes: Uint8Array): Promise<void>;
	close(): Promise<void>;
}

/**
 * Schema, applied as idempotent DDL at open. A single CREATE-IF-NOT-EXISTS pass
 * is easier to reason about than a migration runner and impossible to
 * half-apply — which matters more now that the database is on a user's phone
 * and nobody can go and fix it.
 */
export const SCHEMA = `
CREATE TABLE IF NOT EXISTS cards (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  root TEXT,
  quality TEXT,
  voicing_type TEXT,
  key_center TEXT,
  variant TEXT,
  transition TEXT,
  root_pitch_class INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS card_state (
  card_id TEXT PRIMARY KEY,
  due INTEGER NOT NULL,
  stability REAL NOT NULL,
  difficulty REAL NOT NULL,
  elapsed_days REAL NOT NULL DEFAULT 0,
  scheduled_days REAL NOT NULL DEFAULT 0,
  learning_steps INTEGER NOT NULL DEFAULT 0,
  reps INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0,
  state INTEGER NOT NULL DEFAULT 0,
  last_review INTEGER,
  median_response_ms INTEGER,
  consecutive_correct INTEGER NOT NULL DEFAULT 0,
  mastery TEXT NOT NULL DEFAULT 'new'
);
CREATE INDEX IF NOT EXISTS idx_card_state_due ON card_state (due);

CREATE TABLE IF NOT EXISTS reviews (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  card_id TEXT NOT NULL,
  ts INTEGER NOT NULL,
  grade INTEGER NOT NULL,
  response_ms INTEGER NOT NULL,
  correct INTEGER NOT NULL,
  answer_given TEXT,
  session_id TEXT,
  mode TEXT NOT NULL DEFAULT 'srs'
);
CREATE INDEX IF NOT EXISTS idx_reviews_card ON reviews (card_id);
CREATE INDEX IF NOT EXISTS idx_reviews_ts ON reviews (ts);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  card_count INTEGER NOT NULL DEFAULT 0,
  mode TEXT NOT NULL DEFAULT 'srs'
);

CREATE TABLE IF NOT EXISTS daily_stats (
  date TEXT PRIMARY KEY,
  reviews INTEGER NOT NULL DEFAULT 0,
  correct INTEGER NOT NULL DEFAULT 0,
  median_response_ms INTEGER,
  minutes REAL NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
`;
