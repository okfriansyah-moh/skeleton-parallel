'use strict';

/**
 * Immutable DTO contracts for myapp.
 *
 * All objects are sealed via Object.freeze() — no mutation after construction.
 * Modules MUST NOT define their own DTOs; import from here instead.
 *
 * @module contracts
 */

/**
 * @typedef {Object} PipelineRun
 * @property {string} run_id        - Content-addressable ID (SHA256[:16])
 * @property {string} input_hash    - SHA256 of the canonical input
 * @property {string} status        - 'started' | 'processing' | 'completed' | 'partial' | 'failed'
 * @property {string} started_at    - ISO 8601 UTC timestamp
 * @property {string|null} completed_at - ISO 8601 UTC timestamp or null
 * @property {number} total_items   - Total items to process
 * @property {number} processed_items - Items processed so far
 * @property {string} last_completed_stage - Name of last successfully completed stage
 */

/**
 * @typedef {Object} EntityResult
 * @property {string} entity_id     - Content-addressable ID (SHA256[:16])
 * @property {string} run_id        - Parent PipelineRun.run_id
 * @property {string} status        - 'created' | 'queued' | 'processed' | 'completed' | 'failed'
 * @property {string|null} error    - Error message if status is 'failed', else null
 * @property {string} created_at    - ISO 8601 UTC timestamp
 * @property {string|null} completed_at - ISO 8601 UTC timestamp or null
 */

/**
 * @typedef {Object} HealthStatus
 * @property {string} status        - 'ok' | 'degraded' | 'error'
 * @property {string} checked_at    - ISO 8601 UTC timestamp
 */

/**
 * Create an immutable PipelineRun DTO.
 * @param {Partial<PipelineRun>} fields
 * @returns {Readonly<PipelineRun>}
 */
function makePipelineRun(fields) {
  return Object.freeze({
    run_id: fields.run_id ?? '',
    input_hash: fields.input_hash ?? '',
    status: fields.status ?? 'started',
    started_at: fields.started_at ?? new Date().toISOString(),
    completed_at: fields.completed_at ?? null,
    total_items: fields.total_items ?? 0,
    processed_items: fields.processed_items ?? 0,
    last_completed_stage: fields.last_completed_stage ?? '',
  });
}

/**
 * Create an immutable EntityResult DTO.
 * @param {Partial<EntityResult>} fields
 * @returns {Readonly<EntityResult>}
 */
function makeEntityResult(fields) {
  return Object.freeze({
    entity_id: fields.entity_id ?? '',
    run_id: fields.run_id ?? '',
    status: fields.status ?? 'created',
    error: fields.error ?? null,
    created_at: fields.created_at ?? new Date().toISOString(),
    completed_at: fields.completed_at ?? null,
  });
}

/**
 * Create an immutable HealthStatus DTO.
 * @param {Partial<HealthStatus>} fields
 * @returns {Readonly<HealthStatus>}
 */
function makeHealthStatus(fields) {
  return Object.freeze({
    status: fields.status ?? 'ok',
    checked_at: fields.checked_at ?? new Date().toISOString(),
  });
}

module.exports = { makePipelineRun, makeEntityResult, makeHealthStatus };
