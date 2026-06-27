#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# templates/hooks/python/acceptance-gates.sh — Python acceptance gates (stub)
# ─────────────────────────────────────────────────────────────────────────────
# Stage [5b] acceptance gate hook for Python projects.
# Exits 0 by default — add project-specific E2E tests here.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "${PROJECT_ROOT:-$(pwd)}"

echo "[acceptance-gates] Running Python acceptance gates..."

# TODO: add project-specific E2E tests
# Examples:
#   pytest tests/e2e/ --e2e
#   python -m pytest tests/integration/ -m integration

echo "[acceptance-gates] PASS: acceptance gates passed (stub — add E2E tests)"
exit 0
