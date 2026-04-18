'use strict';

/**
 * Entry point for myapp.
 *
 * Initialises the database adapter and runs the pipeline orchestrator.
 * All configuration is read from environment variables or config/phases.yaml.
 *
 * @module src/main
 */

const path = require('path');
const { DatabaseAdapter } = require('../database/adapter');
const { runPipeline } = require('./orchestrator');
const { logger } = require('./logger');

async function main() {
  logger.info('myapp starting');

  const db = new DatabaseAdapter({
    path: path.join(process.cwd(), 'output', 'myapp.db'),
  });

  try {
    await runPipeline(db);
    logger.info('myapp finished');
  } finally {
    db.close();
  }
}

main().catch((err) => {
  logger.error('Fatal error', { error: err.message, stack: err.stack });
  process.exit(1);
});
