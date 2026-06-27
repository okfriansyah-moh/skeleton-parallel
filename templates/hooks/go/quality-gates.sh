#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# templates/hooks/go/quality-gates.sh — Go quality gates
# ─────────────────────────────────────────────────────────────────────────────
# T1 (per-task) and T3 (post-integration) quality gate hook for Go projects.
# Called by task_executor.sh after each task and by global_validation.sh.
#
# Requirements: go 1.18+
# Exit: 0 on pass, non-zero on any failure
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "${PROJECT_ROOT:-$(pwd)}"

echo "[quality-gates] Running Go quality gates..."

# Build — catches compilation errors
echo "[quality-gates] go build..."
go build ./... || { echo "[quality-gates] FAIL: go build"; exit 1; }

# Vet — catches common mistakes
echo "[quality-gates] go vet..."
go vet ./... || { echo "[quality-gates] FAIL: go vet"; exit 1; }

# Tests — run all tests
echo "[quality-gates] go test..."
go test ./... || { echo "[quality-gates] FAIL: go test"; exit 1; }

echo "[quality-gates] PASS: all Go quality gates passed"
