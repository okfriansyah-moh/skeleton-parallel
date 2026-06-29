#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/pipeline/task_executor.sh — Stage 0: Per-task executor (Agentic Loop L2)
# ─────────────────────────────────────────────────────────────────────────────
# Implements the L2 task loop per spec §8.4:
#   generate_task_prompt → checkpoint → 7-step agent chain → T1 hook → commit
#
# Functions:
#   generate_task_prompt <task_n> <plan_index>  — write .skeleton-dev/TASK_PROMPT.md
#   execute_task <task_n> [driver] [plan_index] [work_dir]  — full L2 loop
#
# Agent chain (spec §8.3):
#   1. task-runner     (max 5 retries, rollback on exceed)
#   2. dto-guardian    (max 5 retries, rollback on exceed)
#   3. integration     (max 5 retries, rollback on exceed)
#   4. security-auditor (max 3 retries, rollback on exceed)
#   5. test-builder    (max 3 retries, rollback on exceed)
#   6. protected file check (rollback on violation)
#   7. quality-gates.sh T1 (refactor ≤3, rollback on exceed)
#
# Testing overrides:
#   SKELETON_MOCK_DRIVER_EXIT=N  — makes _invoke_driver always return exit N
#   SKELETON_MOCK_DRIVER_EXIT=0  — all steps succeed (for success-path testing)
#   SKELETON_MOCK_DRIVER_EXIT=1  — all steps fail (for retry/rollback testing)
#
# CLI usage (standalone):
#   bash task_executor.sh generate_task_prompt <N> <plan_index>
#   bash task_executor.sh execute_task <N> [driver] [plan_index] [work_dir]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_TE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKELETON_ROOT="$(cd "${_TE_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${_SKELETON_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/checkpoint.sh
source "${_SKELETON_ROOT}/scripts/lib/checkpoint.sh"
# shellcheck source=scripts/lib/hooks.sh
source "${_SKELETON_ROOT}/scripts/lib/hooks.sh"
# shellcheck source=scripts/lib/config.sh
source "${_SKELETON_ROOT}/scripts/lib/config.sh"

# ── Retry limit defaults (overridable from config/skeleton.yaml) ──────────────
RETRIES_TASK_RUNNER="${RETRIES_TASK_RUNNER:-5}"
RETRIES_DTO_GUARDIAN="${RETRIES_DTO_GUARDIAN:-5}"
RETRIES_INTEGRATION="${RETRIES_INTEGRATION:-5}"
RETRIES_SECURITY_AUDITOR="${RETRIES_SECURITY_AUDITOR:-3}"
RETRIES_TEST_BUILDER="${RETRIES_TEST_BUILDER:-3}"
MAX_T1_REFACTOR="${MAX_T1_REFACTOR:-3}"

# ── generate_task_prompt ──────────────────────────────────────────────────────
# Load only the task's section from PLAN.md via plan-index.json byte offsets.
# Never loads the full PLAN.md into memory.
# Writes to ${PROJECT_ROOT}/.skeleton-dev/TASK_PROMPT.md.
#
# Usage: generate_task_prompt <task_n> <plan_index>
generate_task_prompt() {
    local task_n="${1:?task_n required}"
    local plan_index="${2:?plan_index required}"
    local output_file="${PROJECT_ROOT}/.skeleton-dev/TASK_PROMPT.md"

    mkdir -p "$(dirname "${output_file}")"

    python3 - "${plan_index}" "${task_n}" "${output_file}" <<'PYEOF'
import json, sys, os

plan_index_path = sys.argv[1]
task_n          = str(sys.argv[2])
output_path     = sys.argv[3]

with open(plan_index_path, encoding="utf-8") as f:
    index = json.load(f)

tasks = index.get("tasks", {})
task  = tasks.get(task_n)

if not task:
    print(f"[ERROR] Task {task_n} not found in {plan_index_path}", file=sys.stderr)
    sys.exit(1)

plan_path  = index.get("plan_path", "docs/PLAN.md")
line_start = task.get("line_start", 1)
line_end   = task.get("line_end",   -1)

# Read only the task's line range — O(line_end - line_start) memory
section_lines = []
try:
    with open(plan_path, encoding="utf-8") as f:
        for i, line in enumerate(f, start=1):
            if i < line_start:
                continue
            if line_end > 0 and i > line_end:
                break
            section_lines.append(line)
except FileNotFoundError:
    # plan_path might be relative to a different root; try common locations
    for candidate in ["docs/PLAN.md", plan_index_path.replace("plan-index.json", "../docs/PLAN.md")]:
        try:
            with open(candidate, encoding="utf-8") as f:
                for i, line in enumerate(f, start=1):
                    if i < line_start:
                        continue
                    if line_end > 0 and i > line_end:
                        break
                    section_lines.append(line)
            break
        except FileNotFoundError:
            continue

section = "".join(section_lines)
files_list  = "\n".join(f"- `{fp}`" for fp in task.get("files", []))
deps        = ", ".join(str(d) for d in task.get("depends_on", [])) or "none"
validations = "\n".join(f"- {v}" for v in task.get("validation", []))

prompt = f"""# Task {task_n} — {task.get("name", "")}

**Status:** {task.get("status", "pending")}
**Complexity:** {task.get("complexity", "")}
**Depends on:** {deps}

## Goal

{task.get("goal", "")}

## Files to create

{files_list}

## Validation

{validations}

---

## Full task section (from {plan_path})

{section}
"""

os.makedirs(os.path.dirname(output_path), exist_ok=True)
with open(output_path, "w", encoding="utf-8") as f:
    f.write(prompt)

print(f"[OK] Generated: {output_path}")
PYEOF
}

# ── _invoke_driver ────────────────────────────────────────────────────────────
# Dispatch to the active driver based on SKELETON_DRIVER + SKELETON_PROVIDER.
# Supports SKELETON_MOCK_DRIVER_EXIT=N to short-circuit for testing.
#
# Usage: _invoke_driver <stage> <work_dir> <prompt_file> <model> <log_file>
_invoke_driver() {
    local stage="${1:?stage required}"
    local work_dir="${2:?work_dir required}"
    local prompt_file="${3:?prompt_file required}"
    local model="${4:?model required}"
    local log_file="${5:?log_file required}"
    local driver="${SKELETON_DRIVER:-cli_subscription}"
    local provider="${SKELETON_PROVIDER:-copilot}"

    # ── Testing override ────────────────────────────────────────────────────
    if [[ -n "${SKELETON_MOCK_DRIVER_EXIT:-}" ]]; then
        local mock_exit="${SKELETON_MOCK_DRIVER_EXIT}"
        log_info "[${stage}] MOCK driver (exit ${mock_exit})"
        mkdir -p "$(dirname "${log_file}")"
        echo "[MOCK] stage=${stage} model=${model} exit=${mock_exit}" >> "${log_file}"
        return "${mock_exit}"
    fi

    mkdir -p "$(dirname "${log_file}")"

    case "${driver}" in
        router_http)
            bash "${_SKELETON_ROOT}/drivers/router_http/run.sh" \
                "router_http" "${stage}" "${work_dir}" "${prompt_file}" "${model}" "${log_file}"
            ;;
        cli_subscription)
            case "${provider}" in
                claude)
                    bash "${_SKELETON_ROOT}/drivers/cli/claude.sh" \
                        "cli_subscription" "${stage}" "${work_dir}" "${prompt_file}" "${model}" "${log_file}"
                    ;;
                codex)
                    bash "${_SKELETON_ROOT}/drivers/cli/codex.sh" \
                        "cli_subscription" "${stage}" "${work_dir}" "${prompt_file}" "${model}" "${log_file}"
                    ;;
                *)
                    bash "${_SKELETON_ROOT}/drivers/cli/copilot.sh" \
                        "cli_subscription" "${stage}" "${work_dir}" "${prompt_file}" "${model}" "${log_file}"
                    ;;
            esac
            ;;
        sdk_cursor)
            node "${_SKELETON_ROOT}/drivers/cursor-sdk/run.mjs" \
                "sdk_cursor" "${stage}" "${work_dir}" "${prompt_file}" "${model}" "${log_file}"
            ;;
        *)
            log_error "[${stage}] Unknown driver: ${driver}. Valid: router_http|cli_subscription|sdk_cursor"
            return 3
            ;;
    esac
}

# ── _run_agent_step ───────────────────────────────────────────────────────────
# Run one agent step with bounded retries.
# Returns 0 on success, 1 on exhausted retries, 2 on quota (caller handles).
#
# Usage: _run_agent_step <step_name> <max_retries> <stage> <work_dir> \
#                        <prompt_file> <model> <log_dir> <task_label>
_run_agent_step() {
    local step_name="$1"
    local max_retries="$2"
    local stage="$3"
    local work_dir="$4"
    local prompt_file="$5"
    local model="$6"
    local log_dir="$7"
    local task_label="$8"

    local attempt=0
    while (( attempt < max_retries )); do
        (( attempt++ ))
        local log_file="${log_dir}/${task_label}-${step_name}-${attempt}.log"
        log_info "[${task_label}] ${step_name} attempt ${attempt}/${max_retries}"

        _invoke_driver "${stage}" "${work_dir}" "${prompt_file}" "${model}" "${log_file}"
        local rc=$?

        # Quota exhaustion → propagate to caller for quota_retry handling
        if [[ ${rc} -eq 2 ]]; then
            log_warn "[${task_label}] ${step_name} quota/rate-limit (exit 2)"
            return 2
        fi

        if [[ ${rc} -eq 0 ]]; then
            log_ok "[${task_label}] ${step_name} passed"
            return 0
        fi

        log_warn "[${task_label}] ${step_name} attempt ${attempt} failed (exit ${rc})"
    done

    log_error "[${task_label}] ${step_name} failed after ${max_retries} retries"
    return 1
}

# ── _rollback_task ────────────────────────────────────────────────────────────
# Roll back to the pre-task checkpoint and write a failure status.
#
# Usage: _rollback_task <task_n> <task_label> <reason>
_rollback_task() {
    local task_n="$1"
    local task_label="$2"
    local reason="$3"

    log_error "[${task_label}] Rolling back: ${reason}"
    checkpoint_rollback "${task_n}"

    # Write failure to run-status.json if state.sh is available
    if [[ -f "${_SKELETON_ROOT}/scripts/lib/state.sh" ]]; then
        source "${_SKELETON_ROOT}/scripts/lib/state.sh" 2>/dev/null || true
        run_status_write "task_${task_n}" "rollback" "failed" 2>/dev/null || true
        events_append "task_rollback" "{\"task\":${task_n},\"reason\":\"${reason}\"}" 2>/dev/null || true
    fi
}

# ── _check_protected_files ────────────────────────────────────────────────────
# Step 6: verify no protected files were illegally modified.
#
# Usage: _check_protected_files <work_dir> <task_n>
_check_protected_files() {
    local work_dir="$1"
    local task_n="$2"

    source "${_SKELETON_ROOT}/scripts/lib/policy.sh" 2>/dev/null || return 0

    cd "${work_dir}"
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        return 0  # not a git repo — skip check
    fi

    local base_branch="main"
    if ! git rev-parse --verify "${base_branch}" &>/dev/null; then
        return 0  # no main branch yet — skip
    fi

    # Build list of files changed since main
    local changed_files
    mapfile -t changed_files < <(git diff --name-only "${base_branch}" 2>/dev/null || true)

    if [[ ${#changed_files[@]} -eq 0 ]]; then
        return 0
    fi

    check_protected_paths "${changed_files[@]}" 2>/dev/null || return 1
    return 0
}

# ── _run_quality_gates_t1 ─────────────────────────────────────────────────────
# Step 7: run T1 quality gates hook + refactor up to MAX_T1_REFACTOR times.
#
# Usage: _run_quality_gates_t1 <work_dir> <task_label> <log_dir> <model>
_run_quality_gates_t1() {
    local work_dir="$1"
    local task_label="$2"
    local log_dir="$3"
    local model="$4"

    # Run T1 hook
    if run_hook "quality-gates" "false"; then
        log_ok "[${task_label}] T1 quality gates passed"
        return 0
    fi

    # Failed: try refactor up to MAX_T1_REFACTOR times
    local attempt=0
    while (( attempt < MAX_T1_REFACTOR )); do
        (( attempt++ ))
        log_warn "[${task_label}] T1 quality gates failed (refactor ${attempt}/${MAX_T1_REFACTOR})"

        local prompt_file="${work_dir}/.skeleton-dev/TASK_PROMPT.md"
        local log_file="${log_dir}/${task_label}-refactor-t1-${attempt}.log"
        _invoke_driver "refactor" "${work_dir}" "${prompt_file}" "${model}" "${log_file}" || true

        if run_hook "quality-gates" "false"; then
            log_ok "[${task_label}] T1 quality gates passed after refactor ${attempt}"
            return 0
        fi
    done

    log_error "[${task_label}] T1 quality gates failed after ${MAX_T1_REFACTOR} refactor attempts"
    return 1
}

# ── _mark_task_success ────────────────────────────────────────────────────────
# Write completion marker + git commit on successful task.
_mark_task_success() {
    local task_n="$1"
    local plan_index="$2"
    local work_dir="$3"

    # Mark completed in PLAN.md
    local plan_path="${SKELETON_PLAN:-docs/PLAN.md}"
    python3 "${_SKELETON_ROOT}/scripts/plan/plan_parser.py" \
        "${plan_path}" --mark-completed "${task_n}" 2>/dev/null || true

    # Get task name for commit message
    local task_name
    task_name="$(python3 - "${plan_index}" "${task_n}" <<'PYEOF' 2>/dev/null || echo "task ${task_n}"
import json, sys
idx = json.load(open(sys.argv[1]))
task = (idx.get("tasks") or {}).get(str(sys.argv[2]), {})
print(task.get("name", f"task {sys.argv[2]}"))
PYEOF
)"

    # Commit
    cd "${work_dir}"
    git add -A 2>/dev/null || true
    if ! git diff --cached --quiet 2>/dev/null; then
        git commit -m "feat(task-${task_n}): implement ${task_name}" 2>/dev/null || \
            log_warn "Could not create commit for task ${task_n}"
    fi

    # Write success to run-status.json
    if [[ -f "${_SKELETON_ROOT}/scripts/lib/state.sh" ]]; then
        source "${_SKELETON_ROOT}/scripts/lib/state.sh" 2>/dev/null || true
        run_status_write "task_${task_n}" "completed" "completed" 2>/dev/null || true
        events_append "task_complete" "{\"task\":${task_n}}" 2>/dev/null || true
    fi
}

# ── execute_task ──────────────────────────────────────────────────────────────
# Full L2 task loop: prompt → checkpoint → 7-step chain → T1 hook → commit.
# Per spec §8.3 and §8.4.
#
# Usage: execute_task <task_n> [driver] [plan_index] [work_dir]
execute_task() {
    local task_n="${1:?task_n required}"
    local driver="${2:-${SKELETON_DRIVER:-cli_subscription}}"
    local plan_index="${3:-${PROJECT_ROOT}/.skeleton-dev/plan-index.json}"
    local work_dir="${4:-${PROJECT_ROOT}}"
    local task_label="task-${task_n}"
    local model="${SKELETON_MODEL:-claude-sonnet-4-6}"
    local dev_dir="${work_dir}/.skeleton-dev"
    local log_dir="${dev_dir}/logs"
    local prompt_file="${dev_dir}/TASK_PROMPT.md"

    mkdir -p "${log_dir}"

    log_step "════ Executing ${task_label} ════"

    # ── Step 0a: Generate task prompt ────────────────────────────────────────
    log_step "[${task_label}] Generating task prompt"
    generate_task_prompt "${task_n}" "${plan_index}"

    # ── Step 0b: Checkpoint before agent chain ───────────────────────────────
    log_step "[${task_label}] Creating checkpoint: checkpoint-task-${task_n}-pre"
    checkpoint_create "${task_n}"

    # ── Step 1: task-runner ──────────────────────────────────────────────────
    if ! _run_agent_step "task-runner" "${RETRIES_TASK_RUNNER}" "task-runner" \
            "${work_dir}" "${prompt_file}" "${model}" "${log_dir}" "${task_label}"; then
        _rollback_task "${task_n}" "${task_label}" "task-runner exceeded ${RETRIES_TASK_RUNNER} retries"
        return 1
    fi

    # ── Step 2: dto-guardian ─────────────────────────────────────────────────
    if ! _run_agent_step "dto-guardian" "${RETRIES_DTO_GUARDIAN}" "dto-guardian" \
            "${work_dir}" "${prompt_file}" "${model}" "${log_dir}" "${task_label}"; then
        _rollback_task "${task_n}" "${task_label}" "dto-guardian exceeded ${RETRIES_DTO_GUARDIAN} retries"
        return 1
    fi

    # ── Step 3: integration ──────────────────────────────────────────────────
    if ! _run_agent_step "integration" "${RETRIES_INTEGRATION}" "integration" \
            "${work_dir}" "${prompt_file}" "${model}" "${log_dir}" "${task_label}"; then
        _rollback_task "${task_n}" "${task_label}" "integration exceeded ${RETRIES_INTEGRATION} retries"
        return 1
    fi

    # ── Step 4: security-auditor ─────────────────────────────────────────────
    if ! _run_agent_step "security-auditor" "${RETRIES_SECURITY_AUDITOR}" "security-auditor" \
            "${work_dir}" "${prompt_file}" "${model}" "${log_dir}" "${task_label}"; then
        _rollback_task "${task_n}" "${task_label}" "security-auditor exceeded ${RETRIES_SECURITY_AUDITOR} retries"
        return 1
    fi

    # ── Step 5: test-builder ─────────────────────────────────────────────────
    if ! _run_agent_step "test-builder" "${RETRIES_TEST_BUILDER}" "test-builder" \
            "${work_dir}" "${prompt_file}" "${model}" "${log_dir}" "${task_label}"; then
        _rollback_task "${task_n}" "${task_label}" "test-builder exceeded ${RETRIES_TEST_BUILDER} retries"
        return 1
    fi

    # ── Step 6: Protected file check ─────────────────────────────────────────
    log_step "[${task_label}] Protected file check"
    if ! _check_protected_files "${work_dir}" "${task_n}"; then
        _rollback_task "${task_n}" "${task_label}" "protected file policy violation"
        return 1
    fi
    log_ok "[${task_label}] Protected file check passed"

    # ── Step 7: T1 quality gates ─────────────────────────────────────────────
    if ! _run_quality_gates_t1 "${work_dir}" "${task_label}" "${log_dir}" "${model}"; then
        _rollback_task "${task_n}" "${task_label}" "T1 quality gates failed after ${MAX_T1_REFACTOR} attempts"
        return 1
    fi

    # ── Success ───────────────────────────────────────────────────────────────
    log_step "[${task_label}] Marking task complete + committing"
    _mark_task_success "${task_n}" "${plan_index}" "${work_dir}"

    log_ok "════ Task ${task_n} complete ════"
    return 0
}

# ── CLI entry point ───────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    subcommand="${1:-}"
    shift || true

    case "${subcommand}" in
        generate_task_prompt)
            generate_task_prompt "$@"
            ;;
        execute_task)
            execute_task "$@"
            ;;
        *)
            echo "Usage: task_executor.sh <generate_task_prompt|execute_task> <args...>"
            echo ""
            echo "  generate_task_prompt <task_n> <plan_index>"
            echo "  execute_task <task_n> [driver] [plan_index] [work_dir]"
            exit 1
            ;;
    esac
fi
