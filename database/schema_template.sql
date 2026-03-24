-- ─────────────────────────────────────────────────────────────────────────────
-- Schema Template — Skeleton Parallel
-- ─────────────────────────────────────────────────────────────────────────────
-- This is a template. Replace with your actual schema after generating
-- docs/architecture.md and docs/dto_contracts.md.
--
-- Rules:
--   1. All SQL must use portable syntax (compatible with all supported engines)
--   2. Use ON CONFLICT DO NOTHING (not INSERT OR IGNORE)
--   3. Use parameterized queries only — no string interpolation
--   4. Migrations go in database/migrations/YYYYMMDD000NNN_description.sql
--   5. Engine-specific settings (e.g., WAL mode, connection pooling) belong in database/engines/ only
-- ─────────────────────────────────────────────────────────────────────────────

-- Pipeline run tracking
CREATE TABLE IF NOT EXISTS pipeline_runs (
    run_id          TEXT PRIMARY KEY,
    input_path      TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'started',
    -- status: started → processing → completed | partial | failed
    last_completed_stage TEXT,
    config_hash     TEXT NOT NULL,
    created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Example entity table (replace with your domain entities)
-- CREATE TABLE IF NOT EXISTS entities (
--     entity_id       TEXT PRIMARY KEY,   -- SHA256(content)[:16]
--     run_id          TEXT NOT NULL REFERENCES pipeline_runs(run_id),
--     status          TEXT NOT NULL DEFAULT 'created',
--     -- status: created → queued → processed → completed | failed
--     data            TEXT,               -- JSON or structured data
--     created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
-- );

-- Indexes
CREATE INDEX IF NOT EXISTS idx_pipeline_runs_status ON pipeline_runs(status);
