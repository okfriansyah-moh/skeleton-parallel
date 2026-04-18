'use strict';

/**
 * Health module — public entry point.
 *
 * Exports only the public contract. The orchestrator imports from here.
 * Do not import internal files from outside this module.
 *
 * @module src/modules/health
 */

const { checkHealth } = require('./feature/check');

module.exports = { checkHealth };
