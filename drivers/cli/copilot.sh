#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# drivers/cli/copilot.sh — Copilot CLI subscription driver (Driver B1)
# ─────────────────────────────────────────────────────────────────────────────
# Implements the run_driver() ExecutionDriver contract (spec §8.2) using the
# GitHub Copilot CLI. Extracted verbatim from run_parallel.sh invocation pattern.
#
# Usage:
#   bash drivers/cli/copilot.sh <driver> <stage> <work_dir> <prompt_file> <model> <log_file>
#   source drivers/cli/copilot.sh && run_driver cli_subscription task-runner ...
#
# Exit codes (per spec §8.2):
#   0 — success
#   1 — agent error (non-zero CLI exit)
#   2 — quota/rate-limit exhausted (detected in stderr/stdout)
#   3 — fatal (binary not found, missing prompt file)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_COPILOT_DRIVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKELETON_ROOT="$(cd "${_COPILOT_DRIVER_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${_SKELETON_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/agent.sh
source "${_SKELETON_ROOT}/scripts/lib/agent.sh"

# ── run_driver ────────────────────────────────────────────────────────────────
# Execute a pipeline stage using the Copilot CLI subscription driver.
#
# Usage: run_driver <driver> <stage> <work_dir> <prompt_file> <model> <log_file>
run_driver() {
    local driver="${1:?driver required}"
    local stage="${2:?stage required}"
    local work_dir="${3:?work_dir required}"
    local prompt_file="${4:?prompt_file required}"
    local model="${5:?model required}"
    local log_file="${6:?log_file required}"

    # ── Guard: copilot binary ─────────────────────────────────────────────────
    if ! command -v copilot &>/dev/null; then
        log_error "[${stage}] Copilot CLI not found on PATH"
        log_info "  Install options:"
        log_info "    npm:  npm install -g @githubnext/github-copilot-cli"
        log_info "    brew: brew install gh  (then: gh extension install github/gh-copilot)"
        log_info "  Docs:  https://githubnext.com/projects/copilot-cli"
        return 3
    fi

    if [[ ! -f "${prompt_file}" ]]; then
        log_error "[${stage}] Prompt file not found: ${prompt_file}"
        return 3
    fi

    mkdir -p "$(dirname "${log_file}")"

    # ── Optionally inject router env vars ─────────────────────────────────────
    # Sources router/inject-env.sh when router.inject=true in config
    if [[ -f "${_SKELETON_ROOT}/scripts/lib/router.sh" ]]; then
        # shellcheck source=scripts/lib/router.sh
        source "${_SKELETON_ROOT}/scripts/lib/router.sh" 2>/dev/null || true
        inject_cli_env "copilot" 2>/dev/null || true
    fi

    # ── Build full prompt ──────────────────────────────────────────────────────
    local skills_csv
    skills_csv="$(build_skills_csv)"

    local stage_prompt
    stage_prompt="$(cat "${prompt_file}")"

    # Full prompt: task content + mandatory skill injection + workspace constraint
    # Pattern extracted verbatim from run_parallel.sh
    local full_prompt
    full_prompt="${stage_prompt}

STAGE: ${stage}
MANDATORY: Use skills as primary knowledge source (${skills_csv}).
Follow all constraints in .github/copilot-instructions.md.
${AGENT_WORKSPACE_CONSTRAINT}"

    # ── Resolve agent name ────────────────────────────────────────────────────
    # Agent name is the stage name by default; override via SKELETON_AGENT env
    local agent_name="${SKELETON_AGENT:-${stage}}"

    log_step "[${stage}] cli_subscription/copilot → agent: ${agent_name} (model: ${model})"

    # ── Copilot CLI invocation — extracted verbatim from run_parallel.sh ──────
    (
        cd "${work_dir}"
        copilot \
            -p "${full_prompt}" \
            --agent="${agent_name}" \
            --model="${model}" \
            --no-ask-user \
            --allow-all-tools \
            --autopilot \
            2>&1 | tee "${log_file}"
    )
    local exit_code=${PIPESTATUS[0]}

    # ── Exit code mapping (spec §8.2) ─────────────────────────────────────────
    # Quota/rate-limit patterns in output → exit 2 (quota_retry class)
    if grep -qi "quota\|rate.limit\|429\|token limit exceeded\|billing\|capacity" \
            "${log_file}" 2>/dev/null; then
        log_warn "[${stage}] Quota/rate-limit pattern detected — exit 2 for quota_retry"
        return 2
    fi

    if [[ ${exit_code} -ne 0 ]]; then
        log_error "[${stage}] Copilot CLI failed (exit ${exit_code}). Log: ${log_file}"
        return 1
    fi

    log_ok "[${stage}] copilot completed successfully"
    return 0
}

# ── Standalone entry point ────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_driver "$@"
fi
