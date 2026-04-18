package com.app.modules.health;

/**
 * Health check service — business logic.
 */
public class HealthService {
    public HealthResponse check() {
        return new HealthResponse("ok", "1.0.0");
    }
}
