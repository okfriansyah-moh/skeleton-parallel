#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# templates/hooks/go/acceptance-gates.sh — Go acceptance gates (stub)
# ─────────────────────────────────────────────────────────────────────────────
# Stage [5b] acceptance gate hook for Go projects.
# Exits 0 by default — add project-specific E2E tests here.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "${PROJECT_ROOT:-$(pwd)}"

echo "[acceptance-gates] Running Go acceptance gates..."

# TODO: add project-specific E2E tests
# Examples:
#   go run ./cmd/e2e/... --config=test/e2e.yaml
#   ./scripts/run-e2e.sh

echo "[acceptance-gates] PASS: acceptance gates passed (stub — add E2E tests)"
exit 0
