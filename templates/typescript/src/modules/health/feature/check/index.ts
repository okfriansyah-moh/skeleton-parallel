/**
 * Health module — Health check vertical slice.
 */

export interface HealthResponse {
  readonly status: string;
  readonly version: string;
}

export class HealthService {
  execute(): HealthResponse {
    return { status: 'ok', version: '1.0.0' };
  }
}

export class HealthHandler {
  constructor(private readonly service: HealthService) {}

  handle(): HealthResponse {
    return this.service.execute();
  }
}
