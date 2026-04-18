package com.app.modules.health;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class HealthServiceTest {
    @Test
    void healthCheckReturnsOk() {
        var service = new HealthService();
        var result = service.check();

        assertEquals("ok", result.status());
        assertNotNull(result.version());
    }
}
