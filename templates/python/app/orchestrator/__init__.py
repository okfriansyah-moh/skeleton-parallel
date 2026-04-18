"""Orchestrator — Pipeline execution engine.

The orchestrator is the ONLY component that:
- Calls modules (modules never call each other)
- Manages execution order (the pipeline stage sequence)
- Performs checkpointing (writes last_completed_stage after each stage)
- Writes to the database (via database/adapter)
- Routes DTOs between modules
- Handles failures (decides retry, skip, or abort)
"""
import logging

logger = logging.getLogger(__name__)


def run_pipeline() -> None:
    """Execute the pipeline stages in sequence."""
    logger.info("Pipeline started")
    # TODO: Load config, instantiate adapter, run stages
    # See docs/orchestrator_spec.md for the full execution model
    logger.info("Pipeline completed")
