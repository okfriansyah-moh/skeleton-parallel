"""Integration tests for the health module."""
from app.modules.health.feature.check import HealthService, HealthHandler


def test_health_check():
    service = HealthService()
    handler = HealthHandler(service)
    result = handler.handle()

    assert result["status"] == "ok"
    assert "version" in result
