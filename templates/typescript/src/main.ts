/**
 * {{PROJECT_NAME}} — Entry point.
 */
import { logger } from './logger';

async function main(): Promise<void> {
  logger.info('Starting {{PROJECT_NAME}}');
  // TODO: Load config, instantiate orchestrator, run pipeline
  logger.info('{{PROJECT_NAME}} started');
}

main().catch((err) => {
  logger.error('Fatal error', { error: err });
  process.exit(1);
});
