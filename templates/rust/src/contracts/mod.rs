//! Contracts — Immutable DTO definitions.
//! All inter-module communication flows through these types.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineRun {
    pub run_id: String,
    pub input_path: String,
    pub status: String,
    pub last_completed_stage: Option<String>,
    pub config_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntityResult {
    pub entity_id: String,
    pub name: String,
    pub status: String,
    pub score: f64,
    pub metadata: Option<String>,
}
