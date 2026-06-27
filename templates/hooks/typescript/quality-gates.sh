#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# templates/hooks/typescript/quality-gates.sh — TypeScript quality gates
# ─────────────────────────────────────────────────────────────────────────────
# T1 (per-task) and T3 (post-integration) quality gate hook for TypeScript/Node
# projects. Called by task_executor.sh after each task and by global_validation.
#
# Requirements: TypeScript, ESLint, vitest or jest
# Override via env: SKIP_TSC=1, SKIP_ESLINT=1, SKIP_TESTS=1
# Exit: 0 on pass, non-zero on any failure
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "${PROJECT_ROOT:-$(pwd)}"

echo "[quality-gates] Running TypeScript quality gates..."

# Type check — tsc --noEmit (no output files, just check)
if [[ "${SKIP_TSC:-0}" != "1" ]]; then
    if command -v tsc &>/dev/null || [[ -f "node_modules/.bin/tsc" ]]; then
        echo "[quality-gates] tsc --noEmit..."
        npx --no tsc --noEmit || { echo "[quality-gates] FAIL: tsc --noEmit"; exit 1; }
    else
        echo "[quality-gates] WARN: tsc not found — skipping type check"
    fi
fi

# Lint — ESLint
if [[ "${SKIP_ESLINT:-0}" != "1" ]]; then
    if command -v eslint &>/dev/null || [[ -f "node_modules/.bin/eslint" ]]; then
        echo "[quality-gates] eslint..."
        npx --no eslint . || { echo "[quality-gates] FAIL: eslint"; exit 1; }
    else
        echo "[quality-gates] WARN: eslint not found — skipping lint"
    fi
fi

# Tests — vitest (preferred) or jest
if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
    if [[ -f "node_modules/.bin/vitest" ]]; then
        echo "[quality-gates] vitest run..."
        npx --no vitest run || { echo "[quality-gates] FAIL: vitest"; exit 1; }
    elif [[ -f "node_modules/.bin/jest" ]]; then
        echo "[quality-gates] jest..."
        npx --no jest || { echo "[quality-gates] FAIL: jest"; exit 1; }
    else
        echo "[quality-gates] WARN: no test runner found (vitest/jest) — skipping tests"
    fi
fi

echo "[quality-gates] PASS: all TypeScript quality gates passed"
