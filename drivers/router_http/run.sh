#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# drivers/router_http/run.sh — HTTP harness driver (Driver A) for skeleton-parallel
# ─────────────────────────────────────────────────────────────────────────────
# Implements the run_driver() ExecutionDriver contract per spec §8.2.
#
# Assembles a system prompt from 4 components per §8.2:
#   1. SKELETON_ROOT/framework/ instructions (*.md files)
#   2. Framework skills CSV (all 28)
#   3. Project .ai/skills/ content (domain/custom skills)
#   4. TASK_PROMPT.md content + stage template variable substitution
#
# Then calls 9router's OpenAI-compatible /v1/chat/completions via curl.
#
# Usage:
#   bash drivers/router_http/run.sh [--print-prompt] \
#       <driver> <stage> <work_dir> <prompt_file> <model> <log_file>
#
# Flags:
#   --print-prompt   Assemble and print system prompt JSON; skip HTTP call
#
# Exit codes (per spec §8.2):
#   0 — success
#   1 — agent error (non-200 response, content error)
#   2 — quota/429 exhausted → caller applies quota_retry policy
#   3 — fatal (missing dependency, bad config, curl not found)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_DRIVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKELETON_ROOT="$(cd "${_DRIVER_DIR}/../.." && pwd)"

# Source shared utilities
# shellcheck source=scripts/lib/common.sh
source "${_SKELETON_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/agent.sh
source "${_SKELETON_ROOT}/scripts/lib/agent.sh"
# shellcheck source=scripts/lib/config.sh
source "${_SKELETON_ROOT}/scripts/lib/config.sh"

# ── Router defaults (overridable via env / config) ────────────────────────────
_ROUTER_DEFAULT_ENDPOINT="http://localhost:20128/v1/chat/completions"
_ROUTER_TIMEOUT="${NINE_ROUTER_TIMEOUT:-300}"

# ── _assemble_system_prompt ───────────────────────────────────────────────────
# Build the 4-component system prompt per §8.2.
# Writes result to stdout.
#
# Components:
#   1. framework/*.md instructions
#   2. Framework skills CSV
#   3. Project .ai/skills/ SKILL.md files
#   4. Stage context + workspace constraint
#
# Usage: system_prompt=$(_assemble_system_prompt <stage> <work_dir> [extra_skills])
_assemble_system_prompt() {
    local stage="$1"
    local work_dir="$2"
    local extra_skills="${3:-}"

    local parts=()

    # ── Component 1: Framework instructions ───────────────────────────────────
    local framework_dir="${_SKELETON_ROOT}/framework"
    if [[ -d "${framework_dir}" ]]; then
        local md_content=""
        while IFS= read -r -d '' md_file; do
            local content
            content="$(cat "${md_file}" 2>/dev/null || true)"
            [[ -n "${content}" ]] && md_content+="${content}"$'\n'
        done < <(find "${framework_dir}" -maxdepth 1 -name "*.md" -print0 2>/dev/null | sort -z)
        [[ -n "${md_content}" ]] && parts+=("## Framework Instructions"$'\n'"${md_content}")
    fi

    # ── Component 2: Framework skills CSV ────────────────────────────────────
    local skills_csv
    skills_csv="$(build_skills_csv "${extra_skills}")"
    parts+=("## Skills"$'\n'"MANDATORY: Use the following skills as primary knowledge sources:"$'\n'"${skills_csv}")

    # ── Component 3: Project .ai/skills/ content ──────────────────────────────
    local ai_skills_dir="${work_dir}/.ai/skills"
    if [[ -d "${ai_skills_dir}" ]]; then
        local skill_content=""
        while IFS= read -r -d '' skill_file; do
            local content
            content="$(cat "${skill_file}" 2>/dev/null || true)"
            [[ -n "${content}" ]] && skill_content+="${content}"$'\n---\n'
        done < <(find "${ai_skills_dir}" -name "SKILL.md" -print0 2>/dev/null | sort -z)
        if [[ -n "${skill_content}" ]]; then
            parts+=("## Project Skills"$'\n'"${skill_content}")
        fi
    fi

    # ── Component 4: Stage context + workspace constraint ────────────────────
    parts+=(
        "## Stage Context"
        "Stage: ${stage}"
        "${AGENT_WORKSPACE_CONSTRAINT}"
        "Follow constraints in the ARES-composed harness file for the configured provider (see .ai/manifest.yaml)."
    )

    # Print all parts joined with newlines
    local IFS=$'\n'
    printf '%s\n' "${parts[@]}"
}

# ── run_driver ────────────────────────────────────────────────────────────────
# Main driver entry point implementing the ExecutionDriver contract (spec §8.2).
#
# Usage: run_driver <driver> <stage> <work_dir> <prompt_file> <model> <log_file>
run_driver() {
    local driver="${1:?driver required}"
    local stage="${2:?stage required}"
    local work_dir="${3:?work_dir required}"
    local prompt_file="${4:?prompt_file required}"
    local model="${5:?model required}"
    local log_file="${6:?log_file required}"

    # ── Guard: required dependencies ──────────────────────────────────────────
    if [[ ! -f "${prompt_file}" ]]; then
        log_error "[${stage}] Prompt file not found: ${prompt_file}"
        return 3
    fi
    if ! command -v curl &>/dev/null; then
        log_error "[${stage}] curl is required for driver=router_http but not installed"
        log_info "  Install curl: brew install curl  or  apt-get install curl"
        return 3
    fi
    if ! command -v python3 &>/dev/null; then
        log_error "[${stage}] python3 is required for driver=router_http but not installed"
        return 3
    fi

    mkdir -p "$(dirname "${log_file}")"

    # ── Read router config ────────────────────────────────────────────────────
    local endpoint="${NINE_ROUTER_ENDPOINT:-${_ROUTER_DEFAULT_ENDPOINT}}"
    local token="${NINE_ROUTER_TOKEN:-}"

    local skeleton_yaml="${work_dir}/config/skeleton.yaml"
    if [[ -f "${skeleton_yaml}" ]]; then
        local _ep; _ep="$(_config_yaml_get "${skeleton_yaml}" "router.endpoint")"
        if [[ -n "${_ep}" ]]; then
            # Ensure endpoint has /chat/completions path
            endpoint="${_ep%/}/chat/completions"
        fi
    fi

    # ── Template variable substitution in prompt file ─────────────────────────
    local task_number="${SKELETON_TASK_NUMBER:-0}"
    local plan_path="${SKELETON_PLAN:-docs/PLAN.md}"
    local skills_csv; skills_csv="$(build_skills_csv)"
    local workspace_constraint="${AGENT_WORKSPACE_CONSTRAINT}"

    local task_prompt
    task_prompt="$(cat "${prompt_file}")"

    # Substitute {{TEMPLATE_VARS}} in the user prompt
    task_prompt="${task_prompt//\{\{TASK_NUMBER\}\}/${task_number}}"
    task_prompt="${task_prompt//\{\{PLAN_PATH\}\}/${plan_path}}"
    task_prompt="${task_prompt//\{\{SKILLS_CSV\}\}/${skills_csv}}"
    task_prompt="${task_prompt//\{\{WORKSPACE_CONSTRAINT\}\}/${workspace_constraint}}"
    task_prompt="${task_prompt//\{\{STAGE_NAME\}\}/${stage}}"

    # ── Assemble system prompt (4 components) ─────────────────────────────────
    local system_prompt
    system_prompt="$(_assemble_system_prompt "${stage}" "${work_dir}")"

    # ── Build JSON body via Python (safe multi-line handling) ─────────────────
    local sys_tmp usr_tmp body_tmp
    sys_tmp="$(mktemp)"
    usr_tmp="$(mktemp)"
    body_tmp="$(mktemp)"

    printf '%s' "${system_prompt}" > "${sys_tmp}"
    printf '%s' "${task_prompt}"   > "${usr_tmp}"

    python3 - "${model}" "${sys_tmp}" "${usr_tmp}" > "${body_tmp}" <<'PYEOF'
import sys, json, os

model        = sys.argv[1]
sys_file     = sys.argv[2]
usr_file     = sys.argv[3]

with open(sys_file, encoding="utf-8") as f:
    system_content = f.read()
with open(usr_file, encoding="utf-8") as f:
    user_content = f.read()

os.unlink(sys_file)
os.unlink(usr_file)

body = {
    "model":    model,
    "messages": [
        {"role": "system", "content": system_content},
        {"role": "user",   "content": user_content},
    ],
    "stream":     True,
    "max_tokens": 16384,
}
print(json.dumps(body, ensure_ascii=False))
PYEOF

    log_step "[${stage}] router_http → ${endpoint} (model: ${model})"

    # ── HTTP request ──────────────────────────────────────────────────────────
    local http_status_tmp
    http_status_tmp="$(mktemp)"
    local curl_exit=0

    local curl_args=(
        --silent
        --no-buffer
        --write-out "%{http_code}"
        --output "${log_file}"
        --max-time "${_ROUTER_TIMEOUT}"
        -H "Content-Type: application/json"
        -d "@${body_tmp}"
    )
    [[ -n "${token}" ]] && curl_args+=(-H "Authorization: Bearer ${token}")
    curl_args+=("${endpoint}")

    curl "${curl_args[@]}" > "${http_status_tmp}" 2>&1 || curl_exit=$?

    local http_status
    http_status="$(cat "${http_status_tmp}" 2>/dev/null | tr -d '[:space:]' || echo "000")"
    rm -f "${body_tmp}" "${http_status_tmp}"

    # ── Handle curl failure ───────────────────────────────────────────────────
    if [[ ${curl_exit} -ne 0 ]]; then
        log_error "[${stage}] curl failed (exit ${curl_exit}) — network/connection error"
        printf '[%s] curl_exit=%s endpoint=%s\n' "${stage}" "${curl_exit}" "${endpoint}" >> "${log_file}"
        return 3
    fi

    # ── Check response body for quota/rate-limit patterns ────────────────────
    # Some APIs embed 429-type errors inside a 200 streaming response
    if grep -qi "rate.limit\|quota.exceeded\|token.limit\|billing_hard_limit\|insufficient_quota" \
            "${log_file}" 2>/dev/null; then
        log_warn "[${stage}] Quota/rate-limit pattern in response body — exit 2"
        return 2
    fi

    # ── Parse HTTP status ─────────────────────────────────────────────────────
    case "${http_status}" in
        200|201)
            log_ok "[${stage}] router_http completed (HTTP ${http_status})"
            return 0
            ;;
        429)
            log_warn "[${stage}] HTTP 429 rate-limited — exit 2 for quota_retry"
            return 2
            ;;
        401|403)
            log_error "[${stage}] HTTP ${http_status} authorization error — check NINE_ROUTER_TOKEN"
            return 1
            ;;
        400)
            log_error "[${stage}] HTTP 400 bad request — check prompt or model name"
            return 1
            ;;
        5*)
            log_error "[${stage}] HTTP ${http_status} server error"
            return 1
            ;;
        000)
            log_error "[${stage}] No HTTP response — is 9router running?"
            log_info "  Start: skeleton router start"
            return 3
            ;;
        *)
            log_error "[${stage}] Unexpected HTTP status: ${http_status}"
            return 1
            ;;
    esac
}

# ── Main entry point ──────────────────────────────────────────────────────────
main() {
    # Handle --print-prompt flag: assemble system prompt without HTTP call
    # Used by the prompt assembly unit test.
    if [[ "${1:-}" == "--print-prompt" ]]; then
        shift
        local _driver="${1:-router_http}"
        local _stage="${2:-task-runner}"
        local _work_dir="${3:-$(pwd)}"
        local _prompt_file="${4:-}"
        local _model="${5:-claude-sonnet-4.6}"

        log_info "[${_stage}] --print-prompt: assembling system prompt (no HTTP call)"

        local _system_prompt
        _system_prompt="$(_assemble_system_prompt "${_stage}" "${_work_dir}")"
        echo "=== SYSTEM PROMPT ==="
        echo "${_system_prompt}"
        echo "=== END SYSTEM PROMPT ==="

        if [[ -n "${_prompt_file}" && -f "${_prompt_file}" ]]; then
            echo "=== TASK PROMPT (from ${_prompt_file}) ==="
            cat "${_prompt_file}"
            echo "=== END TASK PROMPT ==="
        fi
        return 0
    fi

    run_driver "$@"
}

# Only execute main when run directly (not when sourced as a library)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
