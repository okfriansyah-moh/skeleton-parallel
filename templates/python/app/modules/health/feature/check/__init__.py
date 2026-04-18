"""Health check feature — handler, service, DTO."""
from dataclasses import dataclass


@dataclass(frozen=True)
class HealthResponse:
    """Health check response DTO."""
    status: str
    version: str


class HealthService:
    """Health check business logic."""

    def execute(self) -> HealthResponse:
        return HealthResponse(status="ok", version="1.0.0")


class HealthHandler:
    """HTTP handler for health checks."""

    def __init__(self, service: HealthService) -> None:
        self._service = service

    def handle(self) -> dict:
        result = self._service.execute()
        return {"status": result.status, "version": result.version}
