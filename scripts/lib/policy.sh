#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/lib/policy.sh — Protected path enforcement for skeleton-parallel
# ─────────────────────────────────────────────────────────────────────────────
# Defines PROTECTED_PATHS and check_protected_paths() to prevent agents from
# modifying files they do not own.
#
# Protection rules:
#   contracts/  — additive-only: new files allowed; modifying existing = error
#   database/   — read-only during non-infrastructure phases
#   docs/       — read-only; exception: docs/PLAN.md task completion markers
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/lib/policy.sh"
#   check_protected_paths "contracts/foo.go" "app/modules/bar.go"
# ─────────────────────────────────────────────────────────────────────────────

# Guard: idempotent sourcing
[[ -n "${POLICY_LOADED:-}" ]] && return 0
POLICY_LOADED=1

# Depend on common utilities
_POLICY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_POLICY_LIB_DIR}/common.sh"

# ── Protected path list ───────────────────────────────────────────────────────
# Paths are relative to PROJECT_ROOT. Trailing slash = directory prefix match.
PROTECTED_PATHS=(
    "contracts/"
    "database/"
    "docs/"
)
export PROTECTED_PATHS

# ── _is_safe_rel_path ─────────────────────────────────────────────────────────
# Returns 0 if the relative path stays within PROJECT_ROOT (no traversal).
# Portable: does not rely on `realpath -m` (unsupported on macOS BSD realpath).
_is_safe_rel_path() {
    local rel_path="$1"
    # Reject absolute paths and any path containing '..' traversal components.
    [[ "${rel_path}" != /* ]] && [[ "${rel_path}" != *..* ]]
}

# ── _is_existing_file ─────────────────────────────────────────────────────────
# Returns 0 if the path exists as a tracked file in the git index or worktree.
_is_existing_file() {
    local rel_path="$1"
    # Guard: reject paths that escape PROJECT_ROOT via traversal.
    if ! _is_safe_rel_path "${rel_path}"; then
        return 1
    fi
    # Use -- to prevent rel_path values starting with '-' being parsed as flags.
    [[ -f "${PROJECT_ROOT}/${rel_path}" ]] || git -C "${PROJECT_ROOT}" ls-files --error-unmatch -- "${rel_path}" &>/dev/null
}

# ── check_protected_paths ─────────────────────────────────────────────────────
# Validate a list of relative file paths against the protection policy.
# Exits non-zero (via die) on any violation.
#
# Rules applied per path:
#   1. contracts/  — new files accepted; modifying an existing file = violation
#   2. database/   — any write = violation (infrastructure-phase only)
#   3. docs/       — any write = violation EXCEPT docs/PLAN.md (completion markers allowed)
#   4. All other protected prefixes — violation
#
# Usage: check_protected_paths [file …]
check_protected_paths() {
    local violations=()
    local path

    for path in "$@"; do
        # Normalize: strip leading ./
        path="${path#./}"

        # ── Path traversal guard ─────────────────────────────────────────────
        if ! _is_safe_rel_path "${path}"; then
            violations+=("VIOLATION: path '${path}' escapes PROJECT_ROOT — rejected")
            continue
        fi

        # ── contracts/ — additive-only ──────────────────────────────────────
        if [[ "${path}" == contracts/* ]]; then
            if _is_existing_file "${path}"; then
                violations+=("VIOLATION: modifying existing contracts file '${path}' is forbidden (additive-only)")
            fi
            # New file → allowed; skip remaining checks for this path
            continue
        fi

        # ── docs/ — read-only with PLAN.md completion-marker exception ──────
        if [[ "${path}" == docs/* ]]; then
            if [[ "${path}" == "docs/PLAN.md" ]]; then
                # Only the completion marker write pattern is allowed.
                # Policy check passes; runtime write must use mark_completed().
                continue
            fi
            violations+=("VIOLATION: writing to docs path '${path}' is forbidden (docs/ is read-only)")
            continue
        fi

        # ── database/ — write forbidden ─────────────────────────────────────
        if [[ "${path}" == database/* ]]; then
            violations+=("VIOLATION: writing to database path '${path}' is forbidden outside infrastructure phase")
            continue
        fi
    done

    if [[ ${#violations[@]} -gt 0 ]]; then
        log_error "Protected path policy violations detected:"
        local v
        for v in "${violations[@]}"; do
            log_error "  ${v}"
        done
        die "Aborting due to ${#violations[@]} protected path violation(s)"
    fi

    return 0
}
