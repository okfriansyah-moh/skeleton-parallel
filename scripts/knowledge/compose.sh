#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/knowledge/compose.sh — ars compose wrapper with stamp guard
# ─────────────────────────────────────────────────────────────────────────────
# Wraps `ars compose --target <provider>` with:
#   - Compose stamp write on success
#   - Legacy fallback: if compose fails but stamp exists, use last good output
#     and set SKELETON_COMPOSED_DEGRADED=true
#
# Usage (as library):
#   source "${SKELETON_ROOT}/scripts/knowledge/compose.sh"
#   ars_compose "copilot"
#   ars_compose "claude" "${ai_dir}" "${stamp_path}"
#
# Usage (standalone):
#   bash scripts/knowledge/compose.sh copilot
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_COMPOSE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_COMPOSE_SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=scripts/lib/state.sh
source "${_COMPOSE_SCRIPT_DIR}/../lib/state.sh"

# ── ars_compose ───────────────────────────────────────────────────────────────
# Compose .ai/ into provider-specific artifacts using ars.
# Writes the compose stamp on success.
# On failure: falls back to last good composed output if stamp exists,
#             otherwise exits non-zero.
#
# Usage: ars_compose <provider> [ai_dir] [stamp_path]
ars_compose() {
    local provider="${1:?provider required}"
    local ai_dir="${2:-${PROJECT_ROOT}/.ai}"
    local stamp_path="${3:-${PROJECT_ROOT}/${SKELETON_DEV_DIR}/compose.stamp}"

    log_step "[compose] ars compose --target ${provider}"

    if ! command -v ars &>/dev/null; then
        # ── Legacy fallback: ars not found ────────────────────────────────────
        if [[ -f "${stamp_path}" ]]; then
            log_warn "[compose] ars not installed — using last good composed artifacts"
            log_warn "[compose] SKELETON_COMPOSED_DEGRADED=true"
            export SKELETON_COMPOSED_DEGRADED=true
            return 0
        fi
        log_error "[compose] ars not installed and no previous stamp — cannot compose"
        log_info "  Install ars: https://github.com/okfriansyah-moh/ares"
        log_info "  Or run: skeleton integrate"
        return 1
    fi

    local compose_exit=0
    ars compose --target "${provider}" || compose_exit=$?

    if [[ ${compose_exit} -ne 0 ]]; then
        # ── Legacy fallback: compose failed ───────────────────────────────────
        if [[ -f "${stamp_path}" ]]; then
            log_warn "[compose] ars compose failed (exit ${compose_exit}) — falling back to last good artifacts"
            log_warn "[compose] SKELETON_COMPOSED_DEGRADED=true"
            export SKELETON_COMPOSED_DEGRADED=true
            return 0
        fi
        log_error "[compose] ars compose failed (exit ${compose_exit}) and no previous stamp"
        return ${compose_exit}
    fi

    # ── Write compose stamp on success ────────────────────────────────────────
    mkdir -p "$(dirname "${stamp_path}")"
    compose_stamp_write "${ai_dir}"
    log_ok "[compose] Composed for provider: ${provider}"
    return 0
}

# ── Standalone entrypoint ─────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    provider="${1:-}"
    [[ -z "${provider}" ]] && die "Usage: compose.sh <provider> [ai_dir] [stamp_path]"
    ars_compose "${provider}" "${2:-}" "${3:-}"
fi
