#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# templates/hooks/typescript/acceptance-gates.sh — TypeScript acceptance gates
# ─────────────────────────────────────────────────────────────────────────────
# Stage [5b] acceptance gate hook for TypeScript/Node projects.
# Exits 0 by default — add project-specific E2E tests here.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "${PROJECT_ROOT:-$(pwd)}"

echo "[acceptance-gates] Running TypeScript acceptance gates..."

# TODO: add project-specific E2E tests
# Examples:
#   npx playwright test
#   npx cypress run
#   npx vitest run tests/e2e/

echo "[acceptance-gates] PASS: acceptance gates passed (stub — add E2E tests)"
exit 0
