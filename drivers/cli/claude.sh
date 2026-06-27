#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# drivers/cli/claude.sh — Claude Code CLI subscription driver (Driver B2)
# ─────────────────────────────────────────────────────────────────────────────
# Implements the run_driver() ExecutionDriver contract (spec §8.2) using the
# Anthropic Claude Code CLI. Non-interactive mode with structured exit codes.
#
# Usage:
#   bash drivers/cli/claude.sh <driver> <stage> <work_dir> <prompt_file> <model> <log_file>
#   source drivers/cli/claude.sh && run_driver cli_subscription task-runner ...
#
# Exit codes (per spec §8.2):
#   0 — success
#   1 — agent error (non-zero CLI exit)
#   2 — quota/rate-limit exhausted (detected in output)
#   3 — fatal (binary not found, missing prompt file)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_CLAUDE_DRIVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKELETON_ROOT="$(cd "${_CLAUDE_DRIVER_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${_SKELETON_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/agent.sh
source "${_SKELETON_ROOT}/scripts/lib/agent.sh"

# ── run_driver ────────────────────────────────────────────────────────────────
# Execute a pipeline stage using the Claude Code CLI subscription driver.
#
# Usage: run_driver <driver> <stage> <work_dir> <prompt_file> <model> <log_file>
run_driver() {
    local driver="${1:?driver required}"
    local stage="${2:?stage required}"
    local work_dir="${3:?work_dir required}"
    local prompt_file="${4:?prompt_file required}"
    local model="${5:?model required}"
    local log_file="${6:?log_file required}"

    # ── Guard: claude binary ──────────────────────────────────────────────────
    if ! command -v claude &>/dev/null; then
        log_error "[${stage}] Claude Code CLI not found on PATH"
        log_info "  Install options:"
        log_info "    npm:  npm install -g @anthropic-ai/claude-code"
        log_info "    brew: brew install claude-code"
        log_info "  Docs:  https://docs.anthropic.com/en/docs/claude-code"
        return 3
    fi

    if [[ ! -f "${prompt_file}" ]]; then
        log_error "[${stage}] Prompt file not found: ${prompt_file}"
        return 3
    fi

    mkdir -p "$(dirname "${log_file}")"

    # ── Optionally inject router env vars ─────────────────────────────────────
    if [[ -f "${_SKELETON_ROOT}/scripts/lib/router.sh" ]]; then
        # shellcheck source=scripts/lib/router.sh
        source "${_SKELETON_ROOT}/scripts/lib/router.sh" 2>/dev/null || true
        inject_cli_env "claude" 2>/dev/null || true
    fi

    # ── Build full prompt ──────────────────────────────────────────────────────
    local skills_csv
    skills_csv="$(build_skills_csv)"

    local stage_prompt
    stage_prompt="$(cat "${prompt_file}")"

    local full_prompt
    full_prompt="${stage_prompt}

STAGE: ${stage}
MANDATORY: Use skills as primary knowledge source (${skills_csv}).
Follow all constraints in .github/copilot-instructions.md.
${AGENT_WORKSPACE_CONSTRAINT}"

    log_step "[${stage}] cli_subscription/claude (model: ${model})"

    # ── Claude Code CLI invocation — non-interactive mode ─────────────────────
    # Claude Code CLI flags:
    #   --non-interactive   Disable interactive prompts (CI/automation mode)
    #   -p TEXT             Task/prompt to execute
    #   --model MODEL       Model identifier
    #   --allowedTools all  Allow all tools (equivalent to --allow-all-tools)
    (
        cd "${work_dir}"
        claude \
            --non-interactive \
            -p "${full_prompt}" \
            --model="${model}" \
            --allowedTools "all" \
            2>&1 | tee "${log_file}"
    )
    local exit_code=${PIPESTATUS[0]}

    # ── Exit code mapping (spec §8.2) ─────────────────────────────────────────
    if grep -qi "quota\|rate.limit\|429\|overloaded\|rate_limit\|billing\|capacity" \
            "${log_file}" 2>/dev/null; then
        log_warn "[${stage}] Quota/rate-limit pattern detected — exit 2 for quota_retry"
        return 2
    fi

    if [[ ${exit_code} -ne 0 ]]; then
        log_error "[${stage}] Claude Code CLI failed (exit ${exit_code}). Log: ${log_file}"
        return 1
    fi

    log_ok "[${stage}] claude completed successfully"
    return 0
}

# ── Standalone entry point ────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_driver "$@"
fi
