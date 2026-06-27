#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/lib/hooks.sh — Hook discovery and invocation for skeleton-parallel
# ─────────────────────────────────────────────────────────────────────────────
# Provides discover_hooks() and run_hook() for language-agnostic delegation
# to project-specific scripts/hooks/<name>.sh files.
#
# Hook resolution order:
#   1. ${PROJECT_ROOT}/scripts/hooks/<hook_name>.sh
#   2. If absent → warn and skip (non-blocking by default)
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/lib/hooks.sh"
#   run_hook "quality-gates"           # soft: returns exit code
#   run_hook "quality-gates" "true"    # hard: die on non-zero
# ─────────────────────────────────────────────────────────────────────────────

# Guard: idempotent sourcing
[[ -n "${HOOKS_LOADED:-}" ]] && return 0
HOOKS_LOADED=1

# Depend on common utilities
_HOOKS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_HOOKS_LIB_DIR}/common.sh"

# ── discover_hooks ────────────────────────────────────────────────────────────
# List all available hook scripts in a project's scripts/hooks/ directory.
# Output: sorted list of absolute paths, one per line.
#
# Usage: discover_hooks [project_root]
discover_hooks() {
    local project_root="${1:-${PROJECT_ROOT}}"
    local hooks_dir="${project_root}/scripts/hooks"

    if [[ ! -d "${hooks_dir}" ]]; then
        log_warn "Hooks directory not found: ${hooks_dir}"
        return 0
    fi

    find "${hooks_dir}" -maxdepth 1 -name '*.sh' -type f | sort
}

# ── run_hook ──────────────────────────────────────────────────────────────────
# Execute a named hook script from scripts/hooks/<hook_name>.sh.
# A missing hook is a warning, not an error (allows projects without hooks).
#
# Usage: run_hook <hook_name> [exit_on_fail] [extra_args...]
#   hook_name    — script name without .sh (e.g., "quality-gates")
#   exit_on_fail — "true" to die on non-zero exit; default "false"
#   extra_args   — forwarded to the hook script
#
# Returns: hook exit code (or 0 when hook is absent)
run_hook() {
    local hook_name="${1:?hook_name required}"
    local exit_on_fail="${2:-false}"
    shift 2 || true  # remaining args forwarded to hook

    local hook_path="${PROJECT_ROOT}/scripts/hooks/${hook_name}.sh"

    if [[ ! -f "${hook_path}" ]]; then
        log_warn "Hook not found: scripts/hooks/${hook_name}.sh — skipping"
        return 0
    fi

    log_info "Running hook: scripts/hooks/${hook_name}.sh"

    ( cd "${PROJECT_ROOT}" && bash "${hook_path}" "$@" )
    local exit_code=$?

    if [[ ${exit_code} -ne 0 ]]; then
        if [[ "${exit_on_fail}" == "true" ]]; then
            die "Hook '${hook_name}' failed (exit ${exit_code})"
        else
            log_warn "Hook '${hook_name}' exited ${exit_code}"
        fi
    fi

    return ${exit_code}
}
