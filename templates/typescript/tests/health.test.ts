import { HealthService, HealthHandler } from '../../src/modules/health/feature/check';

describe('Health Check', () => {
  it('should return ok status', () => {
    const service = new HealthService();
    const handler = new HealthHandler(service);
    const result = handler.handle();

    expect(result.status).toBe('ok');
    expect(result.version).toBeDefined();
  });
});
