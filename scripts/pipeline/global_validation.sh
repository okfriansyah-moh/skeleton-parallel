#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/pipeline/global_validation.sh — Stage [5a]: quality gates + refactor
# ─────────────────────────────────────────────────────────────────────────────
# Provides run_5a() which runs scripts/hooks/quality-gates.sh and drives
# bounded refactor cycles (up to MAX_REFACTOR_CYCLES, default 5).
# Blocks PR creation on persistent failure.
#
# Extracted from run_parallel.sh run_global_validation() + run_remediation().
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/pipeline/global_validation.sh"
#   run_5a "${PROJECT_ROOT}"   # returns 0 on pass, 1 on all cycles exhausted
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_GV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_GV_DIR}/../lib/common.sh"
# shellcheck source=scripts/lib/hooks.sh
source "${_GV_DIR}/../lib/hooks.sh"
# shellcheck source=scripts/lib/agent.sh
source "${_GV_DIR}/../lib/agent.sh"

# Maximum refactor cycles before blocking PR (can be overridden)
MAX_REFACTOR_CYCLES="${MAX_REFACTOR_CYCLES:-5}"

# ── run_5a ────────────────────────────────────────────────────────────────────
# Stage [5a]: run full T3 quality gates; on failure invoke refactor agent and
# retry — bounded by MAX_REFACTOR_CYCLES. Blocks PR on exhaustion.
#
# Usage: run_5a [project_root]
# Returns: 0 on pass, 1 if all cycles exhausted
run_5a() {
    local project_root="${1:-${PROJECT_ROOT}}"

    log_step "[5a] Global quality gates (T3)"

    if run_hook "quality-gates" "false"; then
        log_ok "[5a] Quality gates passed"
        return 0
    fi

    log_warn "[5a] Quality gates failed — starting refactor cycles (max ${MAX_REFACTOR_CYCLES})"

    local cycle=0
    while (( cycle < MAX_REFACTOR_CYCLES )); do
        (( cycle++ ))
        log_info "[5a] Refactor cycle ${cycle}/${MAX_REFACTOR_CYCLES}"

        run_refactor "${project_root}" "${cycle}"

        if run_hook "quality-gates" "false"; then
            log_ok "[5a] Quality gates passed after refactor cycle ${cycle}"
            return 0
        fi
    done

    log_error "[5a] Quality gates failed after ${MAX_REFACTOR_CYCLES} refactor cycles — blocking PR"
    return 1
}

# ── run_refactor ──────────────────────────────────────────────────────────────
# Invoke the refactor agent to fix quality gate violations.
# Called by run_5a() on each failed cycle.
#
# Usage: run_refactor <work_dir> [attempt]
run_refactor() {
    local work_dir="${1:-${PROJECT_ROOT}}"
    local attempt="${2:-1}"

    local model="${SKELETON_MODEL:-claude-sonnet-4.6}"
    local log_file="${work_dir}/.skeleton-dev/logs/refactor-${attempt}.log"
    mkdir -p "$(dirname "${log_file}")"

    local prompt_file
    prompt_file="$(mktemp)"

    cat > "${prompt_file}" <<PROMPT
Quality gates failed (refactor cycle ${attempt}/${MAX_REFACTOR_CYCLES}).
Fix ALL violations found by quality-gates.sh:
  - lint errors and type errors
  - failing tests
  - cross-module imports (only contracts/ types allowed between modules)
  - raw SQL or DB driver imports in app/modules/
  - print() / console.log() statements
  - non-frozen DTOs in contracts/
  - orchestrator authority violations (modules calling other modules)
Use skills: code-quality, coding-standards, modularity, determinism, idempotency.
MANDATORY: Use ONLY skills as primary knowledge source.
Do not change architecture or interfaces.
Commit all fixes.
PROMPT

    log_info "[5a] Refactor attempt ${attempt}/${MAX_REFACTOR_CYCLES} (model: ${model})"

    invoke_agent "refactor" "refactor" "${work_dir}" "${prompt_file}" "${model}" "${log_file}"
    local rc=$?
    rm -f "${prompt_file}"
    return ${rc}
}
