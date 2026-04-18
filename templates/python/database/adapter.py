"""Database adapter — Single entry point for all database access.

Modules MUST NOT import any database driver directly.
Modules MUST NOT contain SQL strings or execute queries.
The adapter accepts and returns immutable DTOs — no raw rows, no dicts.
Only the orchestrator calls the adapter — modules never touch the database.
"""
import logging

logger = logging.getLogger(__name__)


class DatabaseAdapter:
    """Database adapter — all DB access goes through here."""

    def __init__(self, connection_url: str) -> None:
        self._url = connection_url
        logger.info("Database adapter initialized")

    def checkpoint(self, run_id: str, stage_name: str) -> None:
        """Write checkpoint after stage completion."""
        # TODO: Implement with parameterized SQL
        # INSERT INTO pipeline_runs ... ON CONFLICT DO NOTHING
        pass

    def get_last_checkpoint(self, run_id: str) -> str | None:
        """Get last completed stage for resume."""
        # TODO: Implement
        return None
