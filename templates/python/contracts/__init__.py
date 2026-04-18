"""Contracts — Immutable DTO definitions.

All inter-module communication flows through these types.
DTOs are frozen dataclasses — no mutable state crossing module boundaries.
This package is the ONLY coupling between modules.
"""
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class PipelineRun:
    """Pipeline execution state."""
    run_id: str
    input_path: str
    status: str
    last_completed_stage: Optional[str]
    config_hash: str


@dataclass(frozen=True)
class EntityResult:
    """Processed entity result."""
    entity_id: str
    name: str
    status: str
    score: float
    metadata: Optional[str] = None
