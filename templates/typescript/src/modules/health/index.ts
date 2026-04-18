/**
 * Health module endpoint registration.
 */
import { HealthService, HealthHandler } from './feature/check';

export function registerHealthRoutes(app: unknown): void {
  const service = new HealthService();
  const handler = new HealthHandler(service);
  // Framework-specific route registration goes here
  void handler;
}
