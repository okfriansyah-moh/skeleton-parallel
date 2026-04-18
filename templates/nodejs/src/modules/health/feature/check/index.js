'use strict';

/**
 * Health check feature.
 *
 * Pure function: accepts no external dependencies, returns an immutable DTO.
 * Modules MUST NOT call the database or other modules.
 *
 * @module src/modules/health/feature/check
 */

const { makeHealthStatus } = require('../../../../../contracts');

/**
 * Perform a system health check.
 * @returns {import('../../../../../contracts').HealthStatus}
 */
function checkHealth() {
  return makeHealthStatus({
    status: 'ok',
    checked_at: new Date().toISOString(),
  });
}

module.exports = { checkHealth };
