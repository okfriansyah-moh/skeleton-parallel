#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/lib/agent.sh — Agent invocation helpers for skeleton-parallel
# ─────────────────────────────────────────────────────────────────────────────
# Provides invoke_agent() and build_skills_csv() used by every pipeline stage.
# Extracts the Copilot invocation pattern from run_parallel.sh verbatim.
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/lib/agent.sh"
#   invoke_agent "task-runner" "task-runner" "${WORK_DIR}" "${PROMPT_FILE}" \
#                "${MODEL}" "${LOG_FILE}"
# ─────────────────────────────────────────────────────────────────────────────

# Guard: idempotent sourcing
[[ -n "${AGENT_LOADED:-}" ]] && return 0
AGENT_LOADED=1

# Depend on common utilities
_AGENT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_AGENT_LIB_DIR}/common.sh"

# ── Framework skills (all 28) ─────────────────────────────────────────────────
# Injected into every agent prompt so agents always have full knowledge access.
FRAMEWORK_SKILLS="dto, pipeline, modularity, determinism, idempotency, failure, config-validation, code-quality, coding-standards, database-portability, docs-sync, conflict-resolution, token-optimization, running-prompt, security-audit, test-generation, vertical-slice, api-design, project-scaffold, dependency-analysis, migration-management, performance-optimization, caveman, brainstorming, plan-management, subagent-driven-development, test-driven-development, rtk"

# Workspace confinement rule — injected into every agent prompt
AGENT_WORKSPACE_CONSTRAINT="WORKSPACE CONSTRAINT: NEVER write any files, scripts, summaries, or reports to /tmp, /var, /private, or any path outside this project directory. Write ALL output files inside the project — use .skeleton-dev/ for temporary artifacts and output/ for generated files."

# ── build_skills_csv ──────────────────────────────────────────────────────────
# Assemble the final skills CSV from three layers:
#   1. FRAMEWORK_SKILLS (always present)
#   2. SKELETON_SKILLS_ALWAYS from manifest.skills.always (loaded by config.sh)
#   3. extra_skills (per-task or per-stage override)
#
# Usage: build_skills_csv [extra_skills_csv]
build_skills_csv() {
    local extra="${1:-}"
    local skills="${FRAMEWORK_SKILLS}"

    # Layer 2: manifest.skills.always (exported by config.sh as SKELETON_SKILLS_ALWAYS)
    if [[ -n "${SKELETON_SKILLS_ALWAYS:-}" ]]; then
        skills="${skills}, ${SKELETON_SKILLS_ALWAYS}"
    fi

    # Layer 3: per-task/stage overrides
    if [[ -n "${extra}" ]]; then
        skills="${skills}, ${extra}"
    fi

    echo "${skills}"
}

# ── invoke_agent ──────────────────────────────────────────────────────────────
# Invoke an agent via the Copilot CLI (cli_subscription pattern).
# Matches the ExecutionDriver interface from spec §8.2 (Stage prompt + exit codes).
#
# Usage: invoke_agent <stage> <agent> <work_dir> <prompt_file> <model> <log_file>
#   stage       — pipeline stage name (e.g., task-runner, dto-guardian)
#   agent       — Copilot agent name to invoke
#   work_dir    — directory to cd into before running the agent
#   prompt_file — path to .skeleton-dev/TASK_PROMPT.md or equivalent
#   model       — model/combo alias to pass to --model flag
#   log_file    — path to write combined stdout+stderr log
#
# Exit codes (per spec §8.2):
#   0 — success
#   1 — agent error
#   2 — quota/rate-limit exhausted
#   3 — fatal (CLI not found, missing prompt file)
invoke_agent() {
    local stage="${1:?stage required}"
    local agent="${2:?agent required}"
    local work_dir="${3:?work_dir required}"
    local prompt_file="${4:?prompt_file required}"
    local model="${5:?model required}"
    local log_file="${6:?log_file required}"

    if [[ ! -f "${prompt_file}" ]]; then
        log_error "[${stage}] Prompt file not found: ${prompt_file}"
        return 3
    fi

    if ! command -v copilot &>/dev/null; then
        log_error "[${stage}] Copilot CLI not found. Install: npm install -g @githubnext/github-copilot-cli"
        return 3
    fi

    local skills_csv
    skills_csv="$(build_skills_csv)"

    local stage_prompt
    stage_prompt="$(cat "${prompt_file}")"

    # Build full prompt: task content + mandatory skill injection + workspace constraint
    local full_prompt
    full_prompt="${stage_prompt}

STAGE: ${stage}
MANDATORY: Use skills as primary knowledge source (${skills_csv}).
Follow the project's AI constraints as defined in .ai/ (ARES canonical source) and the provider harness file.
${AGENT_WORKSPACE_CONSTRAINT}"

    mkdir -p "$(dirname "${log_file}")"
    log_step "[${stage}] Invoking agent: ${BOLD}${agent}${NC} (model: ${model})"

    # Copilot invocation pattern — extracted from run_parallel.sh verbatim
    (
        cd "${work_dir}"
        copilot \
            -p "${full_prompt}" \
            --agent="${agent}" \
            --model="${model}" \
            --no-ask-user \
            --allow-all-tools \
            --autopilot \
            2>&1 | tee "${log_file}"
    )
    local exit_code=${PIPESTATUS[0]}

    # Map quota/rate-limit patterns to exit code 2 (spec §8.2)
    if grep -qi "quota\|rate.limit\|429\|token limit exceeded\|billing" "${log_file}" 2>/dev/null; then
        log_warn "[${stage}] Quota/rate-limit detected in output — returning exit 2"
        return 2
    fi

    if [[ ${exit_code} -ne 0 ]]; then
        log_error "[${stage}] Agent ${agent} failed (exit ${exit_code}). Log: ${log_file}"
        return 1
    fi

    log_ok "[${stage}] Agent ${agent} completed successfully"
    return 0
}
