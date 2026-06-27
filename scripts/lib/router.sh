#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/lib/router.sh — 9router integration helpers for skeleton-parallel
# ─────────────────────────────────────────────────────────────────────────────
# Provides:
#   router_check_required()        — reads driver + router config; returns
#                                    require|optional|none
#   router_auto_start_if_needed()  — starts 9router if require + auto_start
#   inject_cli_env(provider)       — sources router/inject-env.sh for CLI drivers
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/lib/router.sh"
#   mode=$(router_check_required)   # require|optional|none
#   router_auto_start_if_needed
#   inject_cli_env "copilot"
# ─────────────────────────────────────────────────────────────────────────────

# Guard: idempotent sourcing
[[ -n "${ROUTER_LOADED:-}" ]] && return 0
ROUTER_LOADED=1

# Depend on common + config utilities
_ROUTER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_ROUTER_LIB_DIR}/common.sh"
# shellcheck source=scripts/lib/config.sh
source "${_ROUTER_LIB_DIR}/config.sh"

# ── router_check_required ─────────────────────────────────────────────────────
# Determine whether 9router is required, optional, or not needed.
# Reads SKELETON_DRIVER (from env) and router.enabled/router.inject from config.
#
# Driver selection rules (per §8.12):
#   router_http       → require  (driver sends all requests via 9router)
#   cli_subscription  → optional if router.inject=true; none if router.enabled=false
#   sdk_cursor        → none     (Cursor SDK does not use 9router)
#
# Output (echoed to stdout): require | optional | none
# Usage: mode=$(router_check_required)
router_check_required() {
    local driver="${SKELETON_DRIVER:-}"
    local skeleton_yaml="${PROJECT_ROOT}/config/skeleton.yaml"

    # Load driver from config if not in env
    if [[ -z "${driver}" ]] && [[ -f "${skeleton_yaml}" ]]; then
        driver="$(_config_yaml_get "${skeleton_yaml}" "execution.driver")"
    fi

    # Fallback: default driver
    driver="${driver:-cli_subscription}"

    # sdk_cursor never uses 9router
    if [[ "${driver}" == "sdk_cursor" ]]; then
        echo "none"
        return 0
    fi

    # Read router config
    local router_enabled="true"   # default
    local router_inject="true"    # default

    if [[ -f "${skeleton_yaml}" ]]; then
        local _re; _re="$(_config_yaml_get "${skeleton_yaml}" "router.enabled")"
        [[ -n "${_re}" ]] && router_enabled="${_re}"
        local _ri; _ri="$(_config_yaml_get "${skeleton_yaml}" "router.inject")"
        [[ -n "${_ri}" ]] && router_inject="${_ri}"
    fi

    # router_http always requires 9router
    if [[ "${driver}" == "router_http" ]]; then
        if [[ "${router_enabled}" == "false" ]]; then
            log_warn "[router] driver=router_http but router.enabled=false — this may fail"
        fi
        echo "require"
        return 0
    fi

    # cli_subscription: requires router.enabled=true to be useful
    if [[ "${driver}" == "cli_subscription" ]]; then
        if [[ "${router_enabled}" == "false" ]]; then
            echo "none"
            return 0
        fi
        if [[ "${router_inject}" == "true" ]]; then
            echo "optional"
        else
            echo "none"
        fi
        return 0
    fi

    # Unknown driver — assume none
    echo "none"
}

# ── router_auto_start_if_needed ───────────────────────────────────────────────
# Auto-start 9router daemon if:
#   - router_check_required() returns "require"
#   - router.auto_start=true in config
#   - daemon is not already running
#
# Does nothing if daemon is already running or auto_start=false.
#
# Usage: router_auto_start_if_needed
router_auto_start_if_needed() {
    local mode
    mode="$(router_check_required)"

    if [[ "${mode}" == "none" ]]; then
        return 0
    fi

    # Check auto_start config
    local skeleton_yaml="${PROJECT_ROOT}/config/skeleton.yaml"
    local auto_start="true"  # default
    if [[ -f "${skeleton_yaml}" ]]; then
        local _as; _as="$(_config_yaml_get "${skeleton_yaml}" "router.auto_start")"
        [[ -n "${_as}" ]] && auto_start="${_as}"
    fi

    if [[ "${auto_start}" != "true" ]]; then
        if [[ "${mode}" == "require" ]]; then
            log_warn "[router] driver=router_http but router.auto_start=false"
            log_info "  Start manually: skeleton router start"
        fi
        return 0
    fi

    # Check if daemon is already running (via wrap.sh check)
    local wrap_sh="${SKELETON_ROOT}/router/wrap.sh"
    if [[ -f "${wrap_sh}" ]]; then
        if bash "${wrap_sh}" check &>/dev/null; then
            log_info "[router] 9router already running"
            return 0
        fi

        log_step "[router] Auto-starting 9router (auto_start=true)..."
        bash "${wrap_sh}" start || {
            if [[ "${mode}" == "require" ]]; then
                die "[router] Failed to auto-start 9router (required for driver=router_http)"
            else
                log_warn "[router] Failed to auto-start 9router — continuing without it"
            fi
        }
    else
        log_warn "[router] wrap.sh not found at ${wrap_sh} — skipping auto-start"
    fi
}

# ── inject_cli_env ────────────────────────────────────────────────────────────
# Inject provider-specific env vars for CLI driver invocations.
# Sources router/inject-env.sh (generated by: skeleton router install + oauth).
#
# inject-env.sh sets vars like:
#   COPILOT_PROXY_URL, ANTHROPIC_BASE_URL, OPENAI_BASE_URL, etc.
#
# Usage: inject_cli_env <provider>
#   provider — copilot | claude | codex
inject_cli_env() {
    local provider="${1:-}"

    # Only inject when router.inject=true
    local skeleton_yaml="${PROJECT_ROOT}/config/skeleton.yaml"
    local router_inject="true"
    if [[ -f "${skeleton_yaml}" ]]; then
        local _ri; _ri="$(_config_yaml_get "${skeleton_yaml}" "router.inject")"
        [[ -n "${_ri}" ]] && router_inject="${_ri}"
    fi

    if [[ "${router_inject}" != "true" ]]; then
        return 0
    fi

    local inject_file="${SKELETON_ROOT}/router/inject-env.sh"
    if [[ ! -f "${inject_file}" ]]; then
        log_warn "[router] inject-env.sh not found — run: skeleton router oauth"
        return 0
    fi

    log_info "[router] Injecting ${provider} env vars from inject-env.sh"
    # shellcheck source=router/inject-env.sh
    source "${inject_file}"
}
