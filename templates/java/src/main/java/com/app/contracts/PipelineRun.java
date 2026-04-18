package com.app.contracts;

/**
 * Contracts — Immutable DTO definitions.
 * All inter-module communication flows through these record types.
 * Records are inherently immutable — no mutable state crossing module boundaries.
 */
public record PipelineRun(
    String runId,
    String inputPath,
    String status,
    String lastCompletedStage,
    String configHash
) {}
