'use strict';

/**
 * Database adapter for myapp.
 *
 * Single entry point for all database access.
 * Modules MUST NOT import any database driver directly.
 * Only the orchestrator calls this adapter.
 *
 * Swap the engine by changing the require() below — no module changes needed.
 *
 * @module database/adapter
 */

const path = require('path');
const { makePipelineRun, makeEntityResult } = require('../contracts');

// ── Engine selection ──────────────────────────────────────────────────────────
// Default: SQLite via better-sqlite3 (synchronous, file-based, zero-config).
// To switch engines, replace this block and update package.json devDependencies.
let Database;
try {
  Database = require('better-sqlite3');
} catch {
  throw new Error(
    'Database engine not installed. Run: npm install better-sqlite3'
  );
}

// ── DatabaseAdapter ───────────────────────────────────────────────────────────

class DatabaseAdapter {
  /**
   * @param {object} config
   * @param {string} config.path - Path to the SQLite database file
   */
  constructor(config) {
    const dbPath = config.path ?? path.join(process.cwd(), 'output', 'myapp.db');
    this._db = new Database(dbPath);
    this._db.pragma('journal_mode = WAL');
    this._db.pragma('foreign_keys = ON');
    this._applyMigrations();
  }

  // ── Schema ──────────────────────────────────────────────────────────────────

  _applyMigrations() {
    this._db.exec(`
      CREATE TABLE IF NOT EXISTS pipeline_runs (
        run_id               TEXT PRIMARY KEY,
        input_hash           TEXT NOT NULL,
        status               TEXT NOT NULL DEFAULT 'started',
        started_at           TEXT NOT NULL,
        completed_at         TEXT,
        total_items          INTEGER NOT NULL DEFAULT 0,
        processed_items      INTEGER NOT NULL DEFAULT 0,
        last_completed_stage TEXT NOT NULL DEFAULT ''
      );

      CREATE TABLE IF NOT EXISTS entity_results (
        entity_id    TEXT PRIMARY KEY,
        run_id       TEXT NOT NULL REFERENCES pipeline_runs(run_id),
        status       TEXT NOT NULL DEFAULT 'created',
        error        TEXT,
        created_at   TEXT NOT NULL,
        completed_at TEXT
      );
    `);
  }

  // ── PipelineRun ─────────────────────────────────────────────────────────────

  /**
   * Upsert a pipeline run. Idempotent: ON CONFLICT DO NOTHING on insert.
   * @param {import('../contracts').PipelineRun} run
   * @returns {void}
   */
  upsertPipelineRun(run) {
    this._db.prepare(`
      INSERT INTO pipeline_runs
        (run_id, input_hash, status, started_at, completed_at, total_items, processed_items, last_completed_stage)
      VALUES
        (@run_id, @input_hash, @status, @started_at, @completed_at, @total_items, @processed_items, @last_completed_stage)
      ON CONFLICT(run_id) DO UPDATE SET
        status               = excluded.status,
        completed_at         = excluded.completed_at,
        total_items          = excluded.total_items,
        processed_items      = excluded.processed_items,
        last_completed_stage = excluded.last_completed_stage
    `).run(run);
  }

  /**
   * Get a pipeline run by ID, or null if not found.
   * @param {string} runId
   * @returns {import('../contracts').PipelineRun|null}
   */
  getPipelineRun(runId) {
    const row = this._db.prepare(
      'SELECT * FROM pipeline_runs WHERE run_id = ?'
    ).get(runId);
    return row ? makePipelineRun(row) : null;
  }

  // ── EntityResult ────────────────────────────────────────────────────────────

  /**
   * Insert an entity result. Idempotent: ON CONFLICT DO NOTHING.
   * @param {import('../contracts').EntityResult} entity
   * @returns {void}
   */
  insertEntityResult(entity) {
    this._db.prepare(`
      INSERT INTO entity_results
        (entity_id, run_id, status, error, created_at, completed_at)
      VALUES
        (@entity_id, @run_id, @status, @error, @created_at, @completed_at)
      ON CONFLICT(entity_id) DO NOTHING
    `).run(entity);
  }

  /**
   * Update entity status.
   * @param {string} entityId
   * @param {string} status
   * @param {string|null} error
   * @param {string|null} completedAt
   * @returns {void}
   */
  updateEntityStatus(entityId, status, error, completedAt) {
    this._db.prepare(`
      UPDATE entity_results
      SET status = ?, error = ?, completed_at = ?
      WHERE entity_id = ?
    `).run(status, error, completedAt, entityId);
  }

  /**
   * Get all entity results for a run, ordered deterministically.
   * @param {string} runId
   * @returns {ReadonlyArray<import('../contracts').EntityResult>}
   */
  getEntityResults(runId) {
    const rows = this._db.prepare(
      'SELECT * FROM entity_results WHERE run_id = ? ORDER BY entity_id ASC'
    ).all(runId);
    return Object.freeze(rows.map(makeEntityResult));
  }

  // ── Checkpoint ──────────────────────────────────────────────────────────────

  /**
   * Record the last successfully completed stage for a run.
   * @param {string} runId
   * @param {string} stageName
   * @returns {void}
   */
  checkpoint(runId, stageName) {
    this._db.prepare(`
      UPDATE pipeline_runs SET last_completed_stage = ? WHERE run_id = ?
    `).run(stageName, runId);
  }

  /**
   * Get the last completed stage for a run (for resume support).
   * @param {string} runId
   * @returns {string}
   */
  getLastCheckpoint(runId) {
    const row = this._db.prepare(
      'SELECT last_completed_stage FROM pipeline_runs WHERE run_id = ?'
    ).get(runId);
    return row ? (row.last_completed_stage ?? '') : '';
  }

  close() {
    this._db.close();
  }
}

module.exports = { DatabaseAdapter };
