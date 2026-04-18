/**
 * Database adapter — Single entry point for all database access.
 * No imports from src/ — this layer is database-only.
 */

const log = (level: string, msg: string, meta?: Record<string, unknown>): void => {
  process.stdout.write(
    JSON.stringify({ level, msg, ...meta, time: new Date().toISOString() }) + '\n',
  );
};

export class DatabaseAdapter {
  constructor(private readonly connectionUrl: string) {
    log('info', 'Database adapter initialized', { connectionUrl: '[redacted]' });
  }

  checkpoint(runId: string, stageName: string): void {
    // TODO: Implement with parameterized SQL
    log('info', 'Checkpoint saved', { runId, stageName });
  }

  getLastCheckpoint(runId: string): string | null {
    // TODO: Implement
    log('info', 'Getting last checkpoint', { runId });
    return null;
  }
}
