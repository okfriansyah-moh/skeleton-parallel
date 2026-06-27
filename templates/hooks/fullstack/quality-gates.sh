#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# templates/hooks/fullstack/quality-gates.sh — Fullstack quality gates
# ─────────────────────────────────────────────────────────────────────────────
# T1 (per-task) and T3 (post-integration) quality gate hook for full-stack
# projects with separate backend and frontend directories.
# Auto-detects backend (Go/Python/Node) and frontend (TypeScript/Node).
#
# Exit: 0 on pass, non-zero on any failure
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="${PROJECT_ROOT:-$(pwd)}"
cd "${ROOT}"

echo "[quality-gates] Running fullstack quality gates..."
FAILURES=0

# ── Detect and run backend checks ─────────────────────────────────────────────
BACKEND_DIR=""
for d in backend api server app; do
    [[ -d "${ROOT}/${d}" ]] && BACKEND_DIR="${d}" && break
done

if [[ -n "${BACKEND_DIR}" ]]; then
    echo "[quality-gates] Backend: ${BACKEND_DIR}/"
    cd "${ROOT}/${BACKEND_DIR}"

    if [[ -f "go.mod" ]]; then
        echo "[quality-gates]   go build + vet + test..."
        go build ./... && go vet ./... && go test ./... || FAILURES=$(( FAILURES + 1 ))
    elif [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]]; then
        echo "[quality-gates]   Python: ruff + mypy + pytest..."
        command -v ruff &>/dev/null && ruff check . || FAILURES=$(( FAILURES + 1 ))
        command -v mypy &>/dev/null && mypy . || true  # advisory for backend
        command -v pytest &>/dev/null && pytest || FAILURES=$(( FAILURES + 1 ))
    elif [[ -f "package.json" ]]; then
        echo "[quality-gates]   Node backend: tsc + eslint + test..."
        [[ -f "node_modules/.bin/tsc" ]] && npx --no tsc --noEmit || FAILURES=$(( FAILURES + 1 ))
        [[ -f "node_modules/.bin/eslint" ]] && npx --no eslint . || FAILURES=$(( FAILURES + 1 ))
        [[ -f "node_modules/.bin/vitest" ]] && npx --no vitest run || \
            [[ -f "node_modules/.bin/jest" ]] && npx --no jest || true
    fi

    cd "${ROOT}"
else
    echo "[quality-gates] No backend directory found (checked: backend/ api/ server/ app/)"
fi

# ── Detect and run frontend checks ────────────────────────────────────────────
FRONTEND_DIR=""
for d in frontend web client ui; do
    [[ -d "${ROOT}/${d}" ]] && FRONTEND_DIR="${d}" && break
done

if [[ -n "${FRONTEND_DIR}" ]]; then
    echo "[quality-gates] Frontend: ${FRONTEND_DIR}/"
    cd "${ROOT}/${FRONTEND_DIR}"

    if [[ -f "package.json" ]]; then
        echo "[quality-gates]   Frontend: tsc + eslint + test..."
        [[ -f "node_modules/.bin/tsc" ]] && npx --no tsc --noEmit || FAILURES=$(( FAILURES + 1 ))
        [[ -f "node_modules/.bin/eslint" ]] && npx --no eslint . || FAILURES=$(( FAILURES + 1 ))
        [[ -f "node_modules/.bin/vitest" ]] && npx --no vitest run || \
            [[ -f "node_modules/.bin/jest" ]] && npx --no jest || true
    fi

    cd "${ROOT}"
else
    echo "[quality-gates] No frontend directory found (checked: frontend/ web/ client/ ui/)"
fi

# ── Root-level checks (if no sub-dirs detected) ───────────────────────────────
if [[ -z "${BACKEND_DIR}" ]] && [[ -z "${FRONTEND_DIR}" ]]; then
    echo "[quality-gates] No sub-dirs found — running root-level checks..."
    if [[ -f "go.mod" ]]; then
        go build ./... && go vet ./... && go test ./... || FAILURES=$(( FAILURES + 1 ))
    elif [[ -f "package.json" ]]; then
        [[ -f "node_modules/.bin/tsc" ]] && npx --no tsc --noEmit || FAILURES=$(( FAILURES + 1 ))
        [[ -f "node_modules/.bin/eslint" ]] && npx --no eslint . || FAILURES=$(( FAILURES + 1 ))
    fi
fi

if (( FAILURES > 0 )); then
    echo "[quality-gates] FAIL: ${FAILURES} quality gate(s) failed"
    exit 1
fi

echo "[quality-gates] PASS: all fullstack quality gates passed"
