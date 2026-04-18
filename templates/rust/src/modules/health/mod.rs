//! Health module — Health check vertical slice.

use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
}

pub fn check() -> HealthResponse {
    HealthResponse {
        status: "ok".to_string(),
        version: "1.0.0".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_health_check() {
        let result = check();
        assert_eq!(result.status, "ok");
        assert!(!result.version.is_empty());
    }
}
