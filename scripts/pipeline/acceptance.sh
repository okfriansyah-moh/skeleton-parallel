#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/pipeline/acceptance.sh — Stages [5b], [5c]: acceptance + test-builder
#                                   sufficiency + feedback router
# ─────────────────────────────────────────────────────────────────────────────
# Implements:
#   run_5b()          — [5b] acceptance-gates.sh + optional LLM evaluator
#   run_5c()          — [5c] test-builder sufficiency check
#   feedback_router() — route failure class back to the appropriate fix path
#
# Spec references:
#   §12 (global validation and acceptance)
#   §12.1 (Stage 5 flow)
#   §12.3 (feedback router)
#   §8.6 (deep knowledge feedback router table)
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/pipeline/acceptance.sh"
#   run_5b "${PROJECT_ROOT}"            # returns 0 on pass, 1 on fail
#   run_5c "${PROJECT_ROOT}"            # returns 0=SUFFICIENT, 1=NEEDS_TESTS/FIX
#   feedback_router "missing_tests" 3   # routes failure, returns 0 always
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_ACCEPTANCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_ACCEPTANCE_DIR}/../lib/common.sh"
# shellcheck source=scripts/lib/hooks.sh
source "${_ACCEPTANCE_DIR}/../lib/hooks.sh"
# shellcheck source=scripts/lib/agent.sh
source "${_ACCEPTANCE_DIR}/../lib/agent.sh"
# shellcheck source=scripts/lib/state.sh
source "${_ACCEPTANCE_DIR}/../lib/state.sh"

# ── Config defaults (override via environment or config/skeleton.yaml) ─────────
MAX_RETRIES_ACCEPTANCE="${MAX_RETRIES_ACCEPTANCE:-5}"
ACCEPTANCE_SKIP="${ACCEPTANCE_SKIP:-false}"
ACCEPTANCE_LLM_EVALUATOR="${ACCEPTANCE_LLM_EVALUATOR:-false}"

# ── run_5b ────────────────────────────────────────────────────────────────────
# Stage [5b]: run scripts/hooks/acceptance-gates.sh (hard gate).
# If ACCEPTANCE_SKIP=true → exits 0 immediately without calling hook.
# Optional LLM evaluation when ACCEPTANCE_LLM_EVALUATOR=true.
# Writes run-status.json: global-validation-5b → PASS | FAILED
# Caps retries at MAX_RETRIES_ACCEPTANCE; blocks PR on exceed.
#
# Usage: run_5b [project_root]
# Returns: 0 on pass, 1 on all retries exhausted
run_5b() {
    local project_root="${1:-${PROJECT_ROOT}}"

    log_step "[5b] Acceptance gates"

    # ── Skip gate ─────────────────────────────────────────────────────────────
    if [[ "${ACCEPTANCE_SKIP}" == "true" ]]; then
        log_info "[5b] Acceptance skipped (ACCEPTANCE_SKIP=true)"
        run_status_write "global-validation-5b" "acceptance" "SKIPPED"
        return 0
    fi

    # ── Hard gate: acceptance-gates.sh ───────────────────────────────────────
    local attempt=0
    while (( attempt < MAX_RETRIES_ACCEPTANCE )); do
        (( attempt++ ))

        log_info "[5b] Acceptance attempt ${attempt}/${MAX_RETRIES_ACCEPTANCE}"

        if run_hook "acceptance-gates" "false"; then
            log_ok "[5b] Acceptance gates passed (attempt ${attempt})"
            run_status_write "global-validation-5b" "acceptance" "PASS"
            _run_5b_llm "${project_root}" || true
            return 0
        fi

        log_warn "[5b] Acceptance gates failed (attempt ${attempt}/${MAX_RETRIES_ACCEPTANCE})"

        if (( attempt >= MAX_RETRIES_ACCEPTANCE )); then
            break
        fi

        # Route the failure to fix before retrying
        feedback_router "wrong_behavior_small" "${project_root}"
    done

    log_error "[5b] Acceptance gates failed after ${MAX_RETRIES_ACCEPTANCE} attempts — blocking PR"
    run_status_write "global-validation-5b" "acceptance" "FAILED"
    _run_5b_llm "${project_root}" || true
    return 1
}

# ── _run_5b_llm ───────────────────────────────────────────────────────────────
# Optional LLM evaluator for [5b]. Runs when ACCEPTANCE_LLM_EVALUATOR=true.
# Non-blocking — logs result but does not affect 5b exit code.
#
# Usage: _run_5b_llm <project_root>
_run_5b_llm() {
    local project_root="${1:-${PROJECT_ROOT}}"

    if [[ "${ACCEPTANCE_LLM_EVALUATOR}" != "true" ]]; then
        return 0
    fi

    log_info "[5b] Running optional LLM evaluator"

    local model="${SKELETON_MODEL:-claude-sonnet-4.6}"
    local log_file="${project_root}/.skeleton-dev/logs/acceptance-llm.log"
    mkdir -p "$(dirname "${log_file}")"

    local prompt_file
    prompt_file="$(mktemp)"

    cat > "${prompt_file}" <<PROMPT
Acceptance evaluation (soft LLM gate).
Review the implementation against the acceptance criteria defined in docs/PLAN.md.
Assess: Do the implemented tasks satisfy the stated goals and validation criteria?
Output a brief verdict: ACCEPT or NEEDS_REVISION followed by a one-sentence reason.
This is advisory — do not modify any files during this check.
Use skills: docs-sync, code-quality.
PROMPT

    log_info "[5b] LLM evaluator invoked (model: ${model})"
    invoke_agent "acceptance-llm" "merge-reviewer" "${project_root}" \
        "${prompt_file}" "${model}" "${log_file}" || true
    rm -f "${prompt_file}"

    log_info "[5b] LLM evaluator complete (advisory — see ${log_file})"
    return 0  # always non-blocking
}

# ── run_5c ────────────────────────────────────────────────────────────────────
# Stage [5c]: test-builder sufficiency check.
# Invokes the test-builder agent with "assess sufficiency" role.
# Expects the agent to emit one of:
#   VERDICT: SUFFICIENT
#   VERDICT: NEEDS_TESTS
#   VERDICT: NEEDS_FIX
# Retries up to MAX_RETRIES_ACCEPTANCE with feedback routing on NEEDS_* outcomes.
# Writes run-status.json: global-validation-5c → SUFFICIENT | NEEDS_TESTS | NEEDS_FIX | FAILED
#
# Usage: run_5c [project_root]
# Returns: 0 on SUFFICIENT, 1 on NEEDS_TESTS/NEEDS_FIX after retries exhausted
run_5c() {
    local project_root="${1:-${PROJECT_ROOT}}"

    log_step "[5c] Test-builder sufficiency check"

    local attempt=0
    while (( attempt < MAX_RETRIES_ACCEPTANCE )); do
        (( attempt++ ))
        log_info "[5c] Test-builder sufficiency attempt ${attempt}/${MAX_RETRIES_ACCEPTANCE}"

        local model="${SKELETON_MODEL:-claude-sonnet-4.6}"
        local log_file="${project_root}/.skeleton-dev/logs/test-sufficiency-${attempt}.log"
        mkdir -p "$(dirname "${log_file}")"

        local prompt_file
        prompt_file="$(mktemp)"

        cat > "${prompt_file}" <<PROMPT
Test-builder sufficiency assessment (attempt ${attempt}/${MAX_RETRIES_ACCEPTANCE}).
Assess whether the test suite adequately covers the implemented functionality.
Review: unit tests, integration tests, edge cases, error paths.
MANDATORY: End your response with exactly one of:
  VERDICT: SUFFICIENT
  VERDICT: NEEDS_TESTS
  VERDICT: NEEDS_FIX
Use skills: test-generation, code-quality.
Do not modify any files during this assessment — report only.
PROMPT

        invoke_agent "test-sufficiency" "test-builder" "${project_root}" \
            "${prompt_file}" "${model}" "${log_file}"
        local rc=$?
        rm -f "${prompt_file}"

        # Parse verdict from log
        local verdict="UNKNOWN"
        if [[ -f "${log_file}" ]]; then
            verdict="$(grep -oE 'VERDICT: (SUFFICIENT|NEEDS_TESTS|NEEDS_FIX)' "${log_file}" \
                | tail -1 | sed 's/VERDICT: //' || echo 'UNKNOWN')"
        fi

        # Agent error (non-zero exit) treated as NEEDS_FIX
        if [[ ${rc} -ne 0 ]]; then
            verdict="NEEDS_FIX"
        fi

        log_info "[5c] Verdict: ${verdict} (attempt ${attempt})"

        case "${verdict}" in
            SUFFICIENT)
                log_ok "[5c] Test sufficiency: SUFFICIENT"
                run_status_write "global-validation-5c" "test-builder" "SUFFICIENT"
                return 0
                ;;
            NEEDS_TESTS)
                run_status_write "global-validation-5c" "test-builder" "NEEDS_TESTS"
                if (( attempt < MAX_RETRIES_ACCEPTANCE )); then
                    log_warn "[5c] Tests insufficient — routing to test-builder (attempt ${attempt})"
                    feedback_router "missing_tests" "${project_root}"
                fi
                ;;
            NEEDS_FIX)
                run_status_write "global-validation-5c" "test-builder" "NEEDS_FIX"
                if (( attempt < MAX_RETRIES_ACCEPTANCE )); then
                    log_warn "[5c] Tests need fixes — routing to refactor (attempt ${attempt})"
                    feedback_router "lint_build_unit" "${project_root}"
                fi
                ;;
            *)
                log_warn "[5c] Unparseable verdict '${verdict}' — treating as NEEDS_FIX"
                run_status_write "global-validation-5c" "test-builder" "NEEDS_FIX"
                ;;
        esac
    done

    log_error "[5c] Test sufficiency check failed after ${MAX_RETRIES_ACCEPTANCE} attempts — blocking PR"
    run_status_write "global-validation-5c" "test-builder" "FAILED"
    return 1
}

# ── feedback_router ───────────────────────────────────────────────────────────
# Route a failure class to the appropriate fix path (spec §12.3, §8.7).
# Always returns 0 — the caller decides whether to retry the gate.
#
# Failure classes and routes:
#   lint_build_unit      → refactor agent       → caller retries 5a
#   wrong_behavior_small → refactor agent       → caller retries 5a → 5b
#   missing_tests        → test-builder agent   → caller retries 5a → 5c
#   wrong_feature        → task-runner on task  → Stage 0 for N → re-enter [2]–[6]
#   frontend_broken      → task-runner + E2E    → same as wrong_feature
#
# Usage: feedback_router <failure_class> <project_root_or_task_n>
#   failure_class — one of: lint_build_unit | wrong_behavior_small |
#                            missing_tests | wrong_feature | frontend_broken
#   project_root_or_task_n — PROJECT_ROOT path, or task number for wrong_feature
feedback_router() {
    local failure_class="${1:?failure_class required}"
    local target="${2:-${PROJECT_ROOT}}"

    log_info "[feedback] Routing failure class: ${failure_class}"

    case "${failure_class}" in

        lint_build_unit)
            _feedback_refactor "${target}" "lint_build_unit"
            ;;

        wrong_behavior_small)
            _feedback_refactor "${target}" "wrong_behavior_small"
            ;;

        missing_tests)
            _feedback_test_builder "${target}"
            ;;

        wrong_feature)
            local task_n="${target}"
            _feedback_task_runner "${task_n}"
            ;;

        frontend_broken)
            local task_n="${target}"
            _feedback_task_runner "${task_n}"
            ;;

        *)
            log_warn "[feedback] Unknown failure class '${failure_class}' — defaulting to refactor"
            _feedback_refactor "${PROJECT_ROOT}" "unknown"
            ;;
    esac

    return 0  # always non-blocking; caller retries the gate
}

# ── _feedback_refactor ────────────────────────────────────────────────────────
# Inner: invoke refactor agent to fix lint/build/behavior issues.
_feedback_refactor() {
    local work_dir="${1:-${PROJECT_ROOT}}"
    local reason="${2:-unknown}"

    local model="${SKELETON_MODEL:-claude-sonnet-4.6}"
    local log_file="${work_dir}/.skeleton-dev/logs/feedback-refactor-${reason}.log"
    mkdir -p "$(dirname "${log_file}")"

    local prompt_file
    prompt_file="$(mktemp)"

    cat > "${prompt_file}" <<PROMPT
Feedback router — refactor required (class: ${reason}).
Fix all issues that caused the acceptance/quality gate to fail:
  - lint errors, type errors, build failures
  - behavioral discrepancies vs. PLAN.md task validation criteria
  - code-quality violations (print statements, raw SQL, cross-module imports)
Use skills: code-quality, coding-standards, modularity, determinism.
Do NOT change architecture, interfaces, or DTO contracts.
Commit all fixes with message: fix(feedback): resolve ${reason} issues
PROMPT

    log_info "[feedback] Invoking refactor agent (reason: ${reason})"
    invoke_agent "feedback-refactor" "refactor" "${work_dir}" \
        "${prompt_file}" "${model}" "${log_file}" || true
    rm -f "${prompt_file}"
    return 0
}

# ── _feedback_test_builder ────────────────────────────────────────────────────
# Inner: invoke test-builder agent to add missing tests.
_feedback_test_builder() {
    local work_dir="${1:-${PROJECT_ROOT}}"

    local model="${SKELETON_MODEL:-claude-sonnet-4.6}"
    local log_file="${work_dir}/.skeleton-dev/logs/feedback-test-builder.log"
    mkdir -p "$(dirname "${log_file}")"

    local prompt_file
    prompt_file="$(mktemp)"

    cat > "${prompt_file}" <<PROMPT
Feedback router — test-builder required (class: missing_tests).
Add tests to reach sufficient coverage:
  - Unit tests for all public functions
  - Integration tests for stage boundaries
  - Edge cases and error paths
  - Tests MUST be runnable without network, GPU, or real data files
Use skills: test-generation, code-quality.
Commit all new tests with message: test(feedback): add missing tests
PROMPT

    log_info "[feedback] Invoking test-builder agent (missing_tests)"
    invoke_agent "feedback-test-builder" "test-builder" "${work_dir}" \
        "${prompt_file}" "${model}" "${log_file}" || true
    rm -f "${prompt_file}"
    return 0
}

# ── _feedback_task_runner ─────────────────────────────────────────────────────
# Inner: re-invoke task-runner for a specific task number.
# Used for wrong_feature and frontend_broken failure classes.
_feedback_task_runner() {
    local task_n="${1:?task_n required}"
    local work_dir="${PROJECT_ROOT}"

    local model="${SKELETON_MODEL:-claude-sonnet-4.6}"
    local log_file="${work_dir}/.skeleton-dev/logs/feedback-task-runner-${task_n}.log"
    mkdir -p "$(dirname "${log_file}")"

    local prompt_file
    prompt_file="$(mktemp)"

    cat > "${prompt_file}" <<PROMPT
Feedback router — wrong_feature detected for Task ${task_n}.
Re-implement Task ${task_n} correctly:
  1. Load the task definition from docs/PLAN.md §Task ${task_n}
  2. Review the Goal and Validation sections
  3. Fix the implementation to correctly satisfy ALL validation criteria
  4. Run the task's validation steps before completing
Use skills: plan-management, code-quality, coding-standards.
Do NOT modify files outside the task's declared File Ownership.
Commit with message: fix(task-${task_n}): re-implement to satisfy acceptance criteria
PROMPT

    log_info "[feedback] Invoking task-runner for Task ${task_n} (wrong_feature)"
    invoke_agent "feedback-task-${task_n}" "task-runner" "${work_dir}" \
        "${prompt_file}" "${model}" "${log_file}" || true
    rm -f "${prompt_file}"
    return 0
}
