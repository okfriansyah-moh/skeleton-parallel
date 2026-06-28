#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# drivers/cli/codex.sh — Codex CLI subscription driver (Driver B3)
# ─────────────────────────────────────────────────────────────────────────────
# Implements the run_driver() ExecutionDriver contract (spec §8.2) using the
# OpenAI Codex CLI. Non-interactive mode with structured exit codes.
#
# Usage:
#   bash drivers/cli/codex.sh <driver> <stage> <work_dir> <prompt_file> <model> <log_file>
#   source drivers/cli/codex.sh && run_driver cli_subscription task-runner ...
#
# Exit codes (per spec §8.2):
#   0 — success
#   1 — agent error (non-zero CLI exit)
#   2 — quota/rate-limit exhausted (detected in output)
#   3 — fatal (binary not found, missing prompt file)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_CODEX_DRIVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKELETON_ROOT="$(cd "${_CODEX_DRIVER_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${_SKELETON_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/agent.sh
source "${_SKELETON_ROOT}/scripts/lib/agent.sh"

# ── run_driver ────────────────────────────────────────────────────────────────
# Execute a pipeline stage using the Codex CLI subscription driver.
#
# Usage: run_driver <driver> <stage> <work_dir> <prompt_file> <model> <log_file>
run_driver() {
    local driver="${1:?driver required}"
    local stage="${2:?stage required}"
    local work_dir="${3:?work_dir required}"
    local prompt_file="${4:?prompt_file required}"
    local model="${5:?model required}"
    local log_file="${6:?log_file required}"

    # ── Guard: codex binary ───────────────────────────────────────────────────
    if ! command -v codex &>/dev/null; then
        log_error "[${stage}] Codex CLI not found on PATH"
        log_info "  Install options:"
        log_info "    npm:  npm install -g @openai/codex"
        log_info "    brew: brew install codex"
        log_info "  Docs:  https://github.com/openai/codex"
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
        inject_cli_env "codex" 2>/dev/null || true
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
Follow all constraints in AGENTS.md (ARES-composed harness for Codex).
${AGENT_WORKSPACE_CONSTRAINT}"

    log_step "[${stage}] cli_subscription/codex (model: ${model})"

    # ── Codex CLI invocation — non-interactive mode ───────────────────────────
    # Codex CLI flags (OpenAI-compatible):
    #   -a auto     Auto-approve all actions (non-interactive)
    #   -m MODEL    Model identifier
    #   -p TEXT     Prompt to execute (if supported); fallback to stdin
    (
        cd "${work_dir}"
        # Codex accepts the prompt via -p flag or stdin
        # -a auto: automatically approve all actions (non-interactive)
        # -m MODEL: model selection
        # --full-auto: equivalent to -a auto for some versions
        if codex --help 2>&1 | grep -q -- '-p'; then
            # Modern codex: supports -p flag
            codex \
                -a auto \
                -m "${model}" \
                -p "${full_prompt}" \
                2>&1 | tee "${log_file}"
        else
            # Fallback: pass via stdin
            printf '%s' "${full_prompt}" | codex \
                -a auto \
                -m "${model}" \
                2>&1 | tee "${log_file}"
        fi
    )
    local exit_code=${PIPESTATUS[0]}

    # ── Exit code mapping (spec §8.2) ─────────────────────────────────────────
    if grep -qi "quota\|rate.limit\|429\|rate_limit_error\|insufficient_quota\|billing" \
            "${log_file}" 2>/dev/null; then
        log_warn "[${stage}] Quota/rate-limit pattern detected — exit 2 for quota_retry"
        return 2
    fi

    if [[ ${exit_code} -ne 0 ]]; then
        log_error "[${stage}] Codex CLI failed (exit ${exit_code}). Log: ${log_file}"
        return 1
    fi

    log_ok "[${stage}] codex completed successfully"
    return 0
}

# ── Standalone entry point ────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_driver "$@"
fi
