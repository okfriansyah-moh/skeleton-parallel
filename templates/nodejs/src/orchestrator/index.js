'use strict';

/**
 * Pipeline orchestrator for myapp.
 *
 * The orchestrator is the ONLY component that:
 *   - Calls modules (modules never call each other)
 *   - Writes to the database via the adapter
 *   - Manages checkpoint/resume logic
 *   - Routes DTOs between pipeline stages
 *
 * @module src/orchestrator
 */

const crypto = require('crypto');
const { makePipelineRun } = require('../../contracts');
const { checkHealth } = require('../modules/health/feature/check');
const { logger } = require('../logger');

/**
 * Run the full pipeline.
 * Resumes from the last successful checkpoint on restart.
 *
 * @param {import('../../database/adapter').DatabaseAdapter} db
 * @returns {Promise<void>}
 */
async function runPipeline(db) {
  const inputHash = _computeInputHash();
  const runId = inputHash.slice(0, 16);

  // Upsert run record (idempotent)
  const existingRun = db.getPipelineRun(runId);
  const run = existingRun ?? makePipelineRun({
    run_id: runId,
    input_hash: inputHash,
    status: 'started',
    started_at: new Date().toISOString(),
  });
  db.upsertPipelineRun(run);

  const lastStage = db.getLastCheckpoint(runId);
  logger.info('Pipeline run starting', { run_id: runId, resume_from: lastStage || 'beginning' });

  // ── Stage 1: health-check ─────────────────────────────────────────────────
  if (lastStage === '') {
    logger.info('Stage: health-check');
    const health = checkHealth();
    logger.info('Health check complete', { status: health.status });
    db.checkpoint(runId, 'health-check');
  } else {
    logger.info('Skipping health-check (already completed)');
  }

  // ── Mark complete ────────────────────────────────────────────────────────
  db.upsertPipelineRun(makePipelineRun({
    ...run,
    status: 'completed',
    completed_at: new Date().toISOString(),
    last_completed_stage: 'health-check',
  }));

  logger.info('Pipeline completed', { run_id: runId });
}

/**
 * Compute a deterministic hash of the pipeline input.
 * Replace this with a hash of your actual input data.
 * @returns {string}
 */
function _computeInputHash() {
  const signature = JSON.stringify({ version: '0.1.0', env: process.env.NODE_ENV ?? 'development' });
  return crypto.createHash('sha256').update(signature).digest('hex');
}

module.exports = { runPipeline };
