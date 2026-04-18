/**
 * Contracts — Immutable DTO definitions.
 * All inter-module communication flows through these types.
 * Interfaces are readonly — no mutable state crossing module boundaries.
 */

export interface PipelineRun {
  readonly runId: string;
  readonly inputPath: string;
  readonly status: string;
  readonly lastCompletedStage: string | null;
  readonly configHash: string;
}

export interface EntityResult {
  readonly entityId: string;
  readonly name: string;
  readonly status: string;
  readonly score: number;
  readonly metadata?: string;
}
