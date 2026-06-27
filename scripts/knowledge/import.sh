#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/knowledge/import.sh — ars import wrapper for skeleton-parallel
# ─────────────────────────────────────────────────────────────────────────────
# Wraps `ars import <source_type> --merge` with:
#   - Actionable error if ars CLI is not installed
#   - Additive-only guard: never overwrites existing .ai/ files unless --force
#
# Usage (as library):
#   source "${SKELETON_ROOT}/scripts/knowledge/import.sh"
#   ars_import "github"
#   ars_import "claude" --force
#
# Usage (standalone):
#   bash scripts/knowledge/import.sh github
#   bash scripts/knowledge/import.sh claude --force
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_IMPORT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_IMPORT_SCRIPT_DIR}/../lib/common.sh"

_ARS_NOT_FOUND_MSG="ars CLI not found — run skeleton integrate"

# ── ars_import ────────────────────────────────────────────────────────────────
# Import a provider's knowledge files into .ai/ using ars.
# Uses --merge strategy: adds missing items, never overwrites existing files.
# Pass --force to allow overwriting existing .ai/ content.
#
# Usage: ars_import <source_type> [--force]
ars_import() {
    local source_type="${1:?source_type required}"
    local force=false

    if [[ "${2:-}" == "--force" ]]; then
        force=true
    fi

    # Guard: ars must be installed
    if ! command -v ars &>/dev/null; then
        die "${_ARS_NOT_FOUND_MSG}"
    fi

    local ai_dir="${PROJECT_ROOT}/.ai"

    # Additive-only guard: warn if .ai/ already has content and --force is not set
    if [[ -d "${ai_dir}" ]] && [[ "${force}" != "true" ]]; then
        local file_count
        file_count="$(find "${ai_dir}" -maxdepth 3 -type f 2>/dev/null | wc -l | tr -d ' ')"
        if [[ "${file_count}" -gt 0 ]]; then
            log_info "[import] .ai/ has ${file_count} file(s) — using --merge (additive only)"
        fi
    fi

    log_step "[import] ars import ${source_type} --merge"

    if [[ "${force}" == "true" ]]; then
        ars import "${source_type}" --merge --force
    else
        ars import "${source_type}" --merge
    fi

    log_ok "[import] Imported: ${source_type}"
}

# ── Standalone entrypoint ─────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    source_type="${1:-}"
    force_flag="${2:-}"

    if [[ -z "${source_type}" ]]; then
        die "Usage: import.sh <source_type> [--force]"
    fi

    ars_import "${source_type}" "${force_flag}"
fi
