#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# templates/hooks/python/quality-gates.sh — Python quality gates
# ─────────────────────────────────────────────────────────────────────────────
# T1 (per-task) and T3 (post-integration) quality gate hook for Python projects.
# Called by task_executor.sh after each task and by global_validation.sh.
#
# Requirements: ruff, mypy, pytest (pip install ruff mypy pytest)
# Override checkers via env: SKIP_RUFF=1, SKIP_MYPY=1, SKIP_PYTEST=1
# Exit: 0 on pass, non-zero on any failure
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "${PROJECT_ROOT:-$(pwd)}"

echo "[quality-gates] Running Python quality gates..."

# Lint — ruff (fast, replaces flake8/isort/pycodestyle)
if [[ "${SKIP_RUFF:-0}" != "1" ]]; then
    if command -v ruff &>/dev/null; then
        echo "[quality-gates] ruff check..."
        ruff check . || { echo "[quality-gates] FAIL: ruff check"; exit 1; }
    else
        echo "[quality-gates] WARN: ruff not found — skipping lint"
    fi
fi

# Type check — mypy
if [[ "${SKIP_MYPY:-0}" != "1" ]]; then
    if command -v mypy &>/dev/null; then
        echo "[quality-gates] mypy..."
        mypy . || { echo "[quality-gates] FAIL: mypy"; exit 1; }
    else
        echo "[quality-gates] WARN: mypy not found — skipping type check"
    fi
fi

# Tests — pytest
if [[ "${SKIP_PYTEST:-0}" != "1" ]]; then
    if command -v pytest &>/dev/null; then
        echo "[quality-gates] pytest..."
        pytest || { echo "[quality-gates] FAIL: pytest"; exit 1; }
    else
        echo "[quality-gates] WARN: pytest not found — skipping tests"
    fi
fi

echo "[quality-gates] PASS: all Python quality gates passed"
