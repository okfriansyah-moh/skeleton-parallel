#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/lib/common.sh — Cross-cutting utilities for skeleton-parallel
# ─────────────────────────────────────────────────────────────────────────────
# Provides logging, color constants, bash version check, and root path helpers.
# Source this file from any pipeline script. Safe to source multiple times.
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/lib/common.sh"
# ─────────────────────────────────────────────────────────────────────────────

# Guard: idempotent sourcing
[[ -n "${COMMON_LOADED:-}" ]] && return 0
COMMON_LOADED=1

# ── Bash 4+ check ─────────────────────────────────────────────────────────────
if (( BASH_VERSINFO[0] < 4 )); then
    # Attempt to re-exec under a modern bash (Homebrew paths)
    _BREW_BASH_PATHS=("/opt/homebrew/bin/bash" "/usr/local/bin/bash")
    _find_modern_bash() {
        local _p
        for _p in "${_BREW_BASH_PATHS[@]}"; do
            if [[ -x "$_p" ]] && "$_p" -c '(( BASH_VERSINFO[0] >= 4 ))' 2>/dev/null; then
                echo "$_p"
                return 0
            fi
        done
        return 1
    }
    _modern_bash="$(_find_modern_bash || true)"
    if [[ -n "${_modern_bash}" ]]; then
        exec "${_modern_bash}" "$0" "$@"
    else
        echo "ERROR: bash 4+ required. Install via: brew install bash" >&2
        exit 1
    fi
fi

# ── Root path resolution ───────────────────────────────────────────────────────
# SKELETON_ROOT: directory containing the skeleton-parallel framework itself
# PROJECT_ROOT:  directory of the project being operated on (may differ from SKELETON_ROOT)
#
# Callers may override PROJECT_ROOT before sourcing this file.

if [[ -z "${SKELETON_ROOT:-}" ]]; then
    # Resolve relative to this file: scripts/lib/common.sh → two levels up
    SKELETON_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="${PWD}"
fi

export SKELETON_ROOT
export PROJECT_ROOT

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

export RED GREEN YELLOW BLUE CYAN MAGENTA BOLD NC

# ── Logging ───────────────────────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

# Print a fatal error and exit non-zero
die() { log_error "$@"; exit 1; }
