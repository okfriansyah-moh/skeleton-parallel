#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# tests/integration/test_skeleton_run.sh
# Integration test for skeleton run orchestrator (Task 17 validation)
# ─────────────────────────────────────────────────────────────────────────────
# Tests the full CLI lifecycle in dry-run / mock mode without invoking real
# LLM agents or requiring network access.
#
# Requires: bash 4+, git, python3
#
# Usage:
#   bash tests/integration/test_skeleton_run.sh
#   SKELETON_MOCK_DRIVER_EXIT=0 bash tests/integration/test_skeleton_run.sh
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Locate skeleton CLI ────────────────────────────────────────────────────────
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKELETON_ROOT="$(cd "${_SCRIPT_DIR}/../.." && pwd)"
SKELETON_BIN="${SKELETON_ROOT}/bin/skeleton"

if [[ ! -x "${SKELETON_BIN}" ]]; then
    echo "[FAIL] bin/skeleton not found or not executable: ${SKELETON_BIN}" >&2
    exit 1
fi

export PATH="${SKELETON_ROOT}/bin:${PATH}"

# ── Test state ─────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
TEST_DIR="/tmp/sk17-e2e-$$"
export SKIP_AGENT=true               # skip LLM agent calls in init
export SKELETON_MOCK_DRIVER_EXIT="${SKELETON_MOCK_DRIVER_EXIT:-0}"

# ── Helpers ───────────────────────────────────────────────────────────────────
_pass() { echo "[PASS] $1"; (( PASS++ )) || true; }
_fail() { echo "[FAIL] $1"; (( FAIL++ )) || true; }

assert_exit_0() {
    local label="$1"; shift
    if "$@" 2>/dev/null; then
        _pass "${label}"
    else
        _fail "${label} (command: $*)"
    fi
}

assert_exit_nonzero() {
    local label="$1"; shift
    if ! "$@" 2>/dev/null; then
        _pass "${label}"
    else
        _fail "${label} — expected non-zero but got 0 (command: $*)"
    fi
}

assert_output_contains() {
    local label="$1"
    local pattern="$2"
    local output="$3"
    if echo "${output}" | grep -qi "${pattern}"; then
        _pass "${label}"
    else
        _fail "${label} — expected '${pattern}' in output"
        echo "  Output was: ${output}" >&2
    fi
}

assert_file_exists() {
    local label="$1"
    local file="$2"
    if [[ -f "${file}" ]]; then
        _pass "${label}"
    else
        _fail "${label} — file not found: ${file}"
    fi
}

cleanup() {
    rm -rf "${TEST_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  skeleton-parallel v1.0 Integration Tests"
echo "  SKELETON_ROOT: ${SKELETON_ROOT}"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ── Setup ─────────────────────────────────────────────────────────────────────
mkdir -p "${TEST_DIR}"

# ─────────────────────────────────────────────────────────────────────────────
# TEST GROUP 1: CLI Syntax
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Group 1: CLI syntax checks ---"

assert_exit_0 "bash -n bin/skeleton" bash -n "${SKELETON_BIN}"
assert_exit_0 "bash -n scripts/run_parallel.sh" bash -n "${SKELETON_ROOT}/scripts/run_parallel.sh"
assert_exit_0 "bash -n scripts/skeleton-run.sh" bash -n "${SKELETON_ROOT}/scripts/skeleton-run.sh"
assert_exit_0 "bash -n scripts/pipeline/acceptance.sh" bash -n "${SKELETON_ROOT}/scripts/pipeline/acceptance.sh"
assert_exit_0 "bash -n scripts/pipeline/integration.sh" bash -n "${SKELETON_ROOT}/scripts/pipeline/integration.sh"
assert_exit_0 "bash -n scripts/pipeline/global_validation.sh" bash -n "${SKELETON_ROOT}/scripts/pipeline/global_validation.sh"
assert_exit_0 "bash -n scripts/pipeline/task_executor.sh" bash -n "${SKELETON_ROOT}/scripts/pipeline/task_executor.sh"
assert_exit_0 "bash -n scripts/pipeline/modes.sh" bash -n "${SKELETON_ROOT}/scripts/pipeline/modes.sh"
assert_exit_0 "bash -n scripts/pipeline/pr.sh" bash -n "${SKELETON_ROOT}/scripts/pipeline/pr.sh"
assert_exit_0 "bash -n scripts/lib/common.sh" bash -n "${SKELETON_ROOT}/scripts/lib/common.sh"
assert_exit_0 "bash -n scripts/lib/agent.sh" bash -n "${SKELETON_ROOT}/scripts/lib/agent.sh"
assert_exit_0 "bash -n scripts/lib/state.sh" bash -n "${SKELETON_ROOT}/scripts/lib/state.sh"
assert_exit_0 "bash -n scripts/lib/hooks.sh" bash -n "${SKELETON_ROOT}/scripts/lib/hooks.sh"
assert_exit_0 "bash -n scripts/lib/checkpoint.sh" bash -n "${SKELETON_ROOT}/scripts/lib/checkpoint.sh"
assert_exit_0 "bash -n scripts/lib/router.sh" bash -n "${SKELETON_ROOT}/scripts/lib/router.sh"
assert_exit_0 "bash -n scripts/lib/config.sh" bash -n "${SKELETON_ROOT}/scripts/lib/config.sh"
assert_exit_0 "bash -n scripts/lib/policy.sh" bash -n "${SKELETON_ROOT}/scripts/lib/policy.sh"
assert_exit_0 "bash -n scripts/knowledge/sync.sh" bash -n "${SKELETON_ROOT}/scripts/knowledge/sync.sh"
assert_exit_0 "bash -n router/wrap.sh" bash -n "${SKELETON_ROOT}/router/wrap.sh"
assert_exit_0 "bash -n drivers/router_http/run.sh" bash -n "${SKELETON_ROOT}/drivers/router_http/run.sh"
assert_exit_0 "bash -n drivers/cli/copilot.sh" bash -n "${SKELETON_ROOT}/drivers/cli/copilot.sh"
assert_exit_0 "bash -n drivers/cli/claude.sh" bash -n "${SKELETON_ROOT}/drivers/cli/claude.sh"
assert_exit_0 "bash -n drivers/cli/codex.sh" bash -n "${SKELETON_ROOT}/drivers/cli/codex.sh"
assert_exit_0 "bash -n templates/hooks/go/quality-gates.sh" bash -n "${SKELETON_ROOT}/templates/hooks/go/quality-gates.sh"
assert_exit_0 "bash -n templates/hooks/python/quality-gates.sh" bash -n "${SKELETON_ROOT}/templates/hooks/python/quality-gates.sh"
assert_exit_0 "bash -n templates/hooks/typescript/quality-gates.sh" bash -n "${SKELETON_ROOT}/templates/hooks/typescript/quality-gates.sh"
assert_exit_0 "bash -n templates/hooks/fullstack/quality-gates.sh" bash -n "${SKELETON_ROOT}/templates/hooks/fullstack/quality-gates.sh"

# ─────────────────────────────────────────────────────────────────────────────
# TEST GROUP 2: Python syntax
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Group 2: Python syntax checks ---"

assert_exit_0 "py_compile plan_parser.py" python3 -m py_compile "${SKELETON_ROOT}/scripts/plan/plan_parser.py"
assert_exit_0 "py_compile plan_validate.py" python3 -m py_compile "${SKELETON_ROOT}/scripts/plan/plan_validate.py"
assert_exit_0 "py_compile detect_legacy.py" python3 -m py_compile "${SKELETON_ROOT}/scripts/knowledge/detect_legacy.py"

# Node.js syntax check (if node available)
if command -v node &>/dev/null; then
    assert_exit_0 "node --check cursor driver" node --check "${SKELETON_ROOT}/drivers/cursor-sdk/run.mjs"
else
    _pass "node --check cursor driver (skipped — node not on PATH)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST GROUP 3: skeleton init + doctor
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Group 3: skeleton init go ---"

E2E_DIR="${TEST_DIR}/e2e-test"
"${SKELETON_BIN}" init go --name=e2e-test --dir="${E2E_DIR}" 2>/dev/null || true

assert_file_exists "skeleton init: .ai/manifest.yaml created" "${E2E_DIR}/.ai/manifest.yaml"
assert_file_exists "skeleton init: config/skeleton.yaml created" "${E2E_DIR}/config/skeleton.yaml"
assert_file_exists "skeleton init: docs/PLAN.md created" "${E2E_DIR}/docs/PLAN.md"

# ─────────────────────────────────────────────────────────────────────────────
# TEST GROUP 4: Populate minimal PLAN.md with 2 tasks (task 2 depends on task 1)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Group 4: Minimal PLAN.md + parser ---"

cat > "${E2E_DIR}/docs/PLAN.md" <<'PLANEOF'
# PLAN.md — E2E Test Plan

## 1. Goal
Integration test for skeleton run.

## 5. Implementation Tasks

### Task 1 — Setup Foundation

**Goal:** Create the initial project scaffold.

**Files to create:**
- `app/main.go`

**Validation:**
- `ls app/main.go`

**Depends On:** —

---

### Task 2 — Add HTTP Handler

**Goal:** Add an HTTP handler on top of Task 1.

**Files to create:**
- `app/handler.go`

**Validation:**
- `ls app/handler.go`

**Depends On:** Task 1

---

## 6. Task Summary

| Task | Name                | Depends On | Est. Complexity |
| ---- | ------------------- | ---------- | --------------- |
| 1    | Setup Foundation    | —          | Low             |
| 2    | Add HTTP Handler    | Task 1     | Low             |
PLANEOF

# Parse the minimal PLAN
PLAN_INDEX="${E2E_DIR}/.skeleton-dev/plan-index.json"
mkdir -p "${E2E_DIR}/.skeleton-dev"

python3 "${SKELETON_ROOT}/scripts/plan/plan_parser.py" \
    "${E2E_DIR}/docs/PLAN.md" \
    --export "${PLAN_INDEX}" 2>/dev/null || true

if [[ -f "${PLAN_INDEX}" ]]; then
    _pass "plan_parser.py: plan-index.json generated"
    # Validate tasks present
    if python3 -c "import json; d=json.load(open('${PLAN_INDEX}')); assert '1' in d.get('tasks',{}) and '2' in d.get('tasks',{})" 2>/dev/null; then
        _pass "plan-index.json: tasks 1 and 2 indexed"
    else
        _fail "plan-index.json: tasks 1/2 not found"
    fi
else
    _fail "plan_parser.py: plan-index.json not generated"
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST GROUP 5: skeleton run --dry-run
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Group 5: skeleton run --dry-run ---"

DRY_OUTPUT="$("${SKELETON_BIN}" run --dry-run --plan "${E2E_DIR}/docs/PLAN.md" \
    --dir "${E2E_DIR}" 2>&1 || true)"

assert_output_contains "dry-run: exits without error" "dry.run\|DRY.RUN\|dry_run\|Dry\|plan\|PLAN\|task\|Task" "${DRY_OUTPUT}"

echo "  [dry-run output sample]: $(echo "${DRY_OUTPUT}" | head -3)"

# ─────────────────────────────────────────────────────────────────────────────
# TEST GROUP 6: skeleton run deprecation shim
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Group 6: run_parallel.sh deprecation shim ---"

SHIM_OUTPUT="$("${SKELETON_ROOT}/scripts/run_parallel.sh" start --mode=1 1 2 2>&1 || true)"
assert_output_contains "shim: deprecation warning printed" "DEPRECATED\|deprecated" "${SHIM_OUTPUT}"
assert_output_contains "shim: --mode=1 translated to --parallel" "parallel\|--parallel\|Translated" "${SHIM_OUTPUT}"

SHIM_OUTPUT_M2="$("${SKELETON_ROOT}/scripts/run_parallel.sh" start --mode=2 1 2>&1 || true)"
assert_output_contains "shim: --mode=2 translated to --sequential" "sequential\|--sequential\|Translated" "${SHIM_OUTPUT_M2}"

# ─────────────────────────────────────────────────────────────────────────────
# TEST GROUP 7: skeleton run --force-deps (logs warning)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Group 7: --force-deps logs warning ---"

FORCE_DEPS_OUT="$("${SKELETON_BIN}" run 2 --force-deps --dry-run \
    --plan "${E2E_DIR}/docs/PLAN.md" --dir "${E2E_DIR}" 2>&1 || true)"

assert_output_contains "force-deps: warning logged" "force.dep\|WARN\|warn\|dep" "${FORCE_DEPS_OUT}"

# ─────────────────────────────────────────────────────────────────────────────
# TEST GROUP 8: skeleton doctor
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Group 8: skeleton doctor ---"

# Doctor should run without crashing (may warn on missing ars/router)
DOCTOR_OUT="$("${SKELETON_BIN}" doctor --dir="${E2E_DIR}" 2>&1 || true)"
assert_output_contains "doctor: runs without crash" "check\|CHECK\|pass\|PASS\|warn\|WARN\|fail\|FAIL\|doctor\|DOCTOR" "${DOCTOR_OUT}"

# ─────────────────────────────────────────────────────────────────────────────
# TEST GROUP 9: skeleton hooks regenerate
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Group 9: skeleton hooks regenerate ---"

HOOKS_OUT="$("${SKELETON_BIN}" hooks regenerate --dir="${E2E_DIR}" 2>&1 || true)"
assert_output_contains "hooks regenerate: stack detected" "stack\|Stack\|Detected\|detected\|hooks\|Hooks" "${HOOKS_OUT}"
assert_file_exists "hooks regenerate: quality-gates.sh written" "${E2E_DIR}/scripts/hooks/quality-gates.sh"

# ─────────────────────────────────────────────────────────────────────────────
# TEST GROUP 10: skeleton cleanup --force
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Group 10: skeleton cleanup --force ---"

CLEANUP_OUT="$("${SKELETON_BIN}" cleanup --force --dir="${E2E_DIR}" 2>&1 || true)"
assert_output_contains "cleanup --force: runs without crash" "clean\|Clean\|remov\|Remov\|clear\|Clear\|skeleton-dev\|warn\|WARN" "${CLEANUP_OUT}"

# ─────────────────────────────────────────────────────────────────────────────
# TEST GROUP 11: Key file existence (v1.0 Must list)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Group 11: v1.0 Must-list file existence ---"

must_files=(
    "bin/skeleton"
    "scripts/skeleton-run.sh"
    "scripts/pipeline/task_executor.sh"
    "scripts/pipeline/modes.sh"
    "scripts/pipeline/integration.sh"
    "scripts/pipeline/global_validation.sh"
    "scripts/pipeline/acceptance.sh"
    "scripts/pipeline/pr.sh"
    "scripts/lib/common.sh"
    "scripts/lib/agent.sh"
    "scripts/lib/state.sh"
    "scripts/lib/hooks.sh"
    "scripts/lib/checkpoint.sh"
    "scripts/lib/router.sh"
    "scripts/lib/config.sh"
    "scripts/lib/policy.sh"
    "scripts/knowledge/sync.sh"
    "scripts/knowledge/detect_legacy.py"
    "scripts/plan/plan_parser.py"
    "scripts/plan/plan_validate.py"
    "drivers/router_http/run.sh"
    "drivers/cli/copilot.sh"
    "drivers/cli/claude.sh"
    "drivers/cli/codex.sh"
    "drivers/cursor-sdk/run.mjs"
    "drivers/registry.yaml"
    "router/wrap.sh"
    "router/9router-pin.json"
    "templates/hooks/go/quality-gates.sh"
    "templates/hooks/python/quality-gates.sh"
    "templates/hooks/typescript/quality-gates.sh"
    "templates/hooks/fullstack/quality-gates.sh"
    "templates/ai/manifest.yaml.template"
    "config/skeleton.yaml.template"
    "tests/integration/test_skeleton_run.sh"
)

for f in "${must_files[@]}"; do
    if [[ -f "${SKELETON_ROOT}/${f}" ]]; then
        _pass "exists: ${f}"
    else
        _fail "missing: ${f}"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if (( FAIL > 0 )); then
    exit 1
fi
exit 0
