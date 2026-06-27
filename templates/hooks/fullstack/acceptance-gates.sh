#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# templates/hooks/fullstack/acceptance-gates.sh — Fullstack acceptance gates
# ─────────────────────────────────────────────────────────────────────────────
# Stage [5b] acceptance gate hook for fullstack projects.
# Exits 0 by default — add project-specific E2E tests here.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "${PROJECT_ROOT:-$(pwd)}"

echo "[acceptance-gates] Running fullstack acceptance gates..."

# TODO: add project-specific E2E tests
# Examples:
#   npx playwright test
#   docker-compose -f docker-compose.test.yml up --exit-code-from e2e
#   ./scripts/run-e2e.sh

echo "[acceptance-gates] PASS: acceptance gates passed (stub — add E2E tests)"
exit 0
