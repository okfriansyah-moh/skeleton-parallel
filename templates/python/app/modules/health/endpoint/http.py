"""Health module HTTP endpoint registration."""


def register_routes(app) -> None:
    """Register health check routes with the web framework."""
    from app.modules.health.feature.check import HealthService, HealthHandler

    service = HealthService()
    handler = HealthHandler(service)

    # Framework-specific route registration goes here
    # Example for Flask: app.add_url_rule('/health', view_func=handler.handle)
    pass
