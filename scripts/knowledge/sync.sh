#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/knowledge/sync.sh — Stage −1: Knowledge sync (ARES integration)
# ─────────────────────────────────────────────────────────────────────────────
# Implements the full Stage −1 algorithm per spec §5.3.4:
#
#   1. Resolve PROJECT_ROOT
#   2. Load .ai/manifest.yaml (detect provider + import_policy)
#   3. IMPORT if combination policy triggers → ars import * --merge
#   4. ars validate → abort on failure
#   5. COMPOSE if stale → ars compose --target manifest.defaults.provider
#   6. Legacy fallback if compose fails (stamp exists)
#   7. Abort if .ai/ still missing after import attempt
#   8. Write .skeleton-dev/compose.stamp
#
# Flags:
#   --dry-run   Print planned steps without writing or invoking ars
#   --import    Force-trigger import regardless of policy
#   --integrate Scaffold mode: also bootstrap .ai/manifest.yaml from template
#
# Exit codes:
#   0 — sync complete (or dry-run)
#   1 — ars not installed (when needed), ars validate failed, or .ai/ missing
#
# Usage:
#   bash scripts/knowledge/sync.sh
#   bash scripts/knowledge/sync.sh --dry-run
#   bash scripts/knowledge/sync.sh --import
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_SYNC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_SYNC_SCRIPT_DIR}/../lib/common.sh"

_ARS_NOT_FOUND_MSG="ars CLI not found — run skeleton integrate"

# ── _require_ars ─────────────────────────────────────────────────────────────
_require_ars() {
    if ! command -v ars &>/dev/null; then
        die "${_ARS_NOT_FOUND_MSG}"
    fi
}

# ── _read_manifest_field ──────────────────────────────────────────────────────
# Read a single key from .ai/manifest.yaml using Python stdlib.
# Returns empty string if file/key not found.
_read_manifest_field() {
    local manifest_path="$1"
    local key="$2"
    [[ -f "${manifest_path}" ]] || { echo ""; return 0; }
    python3 - "${manifest_path}" "${key}" <<'PYEOF'
import sys, re

path, target_key = sys.argv[1], sys.argv[2]
# Simple flat key extraction — no full YAML parser needed for single fields
try:
    with open(path) as f:
        for line in f:
            m = re.match(r'^\s*' + re.escape(target_key) + r':\s*(\S+)', line)
            if m:
                val = m.group(1).strip().strip('"\'')
                # Strip inline comments
                val = re.sub(r'\s+#.*$', '', val).strip()
                print(val)
                sys.exit(0)
except Exception:
    pass
print("")
PYEOF
}

# ── _should_import ────────────────────────────────────────────────────────────
# Determine whether the import step should be triggered.
# Returns 0 (true) or 1 (false).
_should_import() {
    local ai_dir="$1"
    local import_policy="$2"
    local force_import="$3"
    local integrate_mode="$4"

    # Explicit flags
    [[ "${force_import}" == "true" ]] && return 0
    [[ "${integrate_mode}" == "true" ]] && return 0

    # .ai/ directory is missing
    [[ ! -d "${ai_dir}" ]] && return 0

    # import_policy=always
    [[ "${import_policy}" == "always" ]] && return 0

    # import_policy=on_missing — only import when .ai/ is absent (already checked)
    [[ "${import_policy}" == "on_missing" ]] && return 1

    # import_policy=merge_on_stale — check legacy file mtimes vs .ai/ mtime
    if [[ "${import_policy}" == "merge_on_stale" ]]; then
        python3 - "${PROJECT_ROOT}" "${ai_dir}" <<'PYEOF'
import sys, os

project_root, ai_dir = sys.argv[1], sys.argv[2]

# Known legacy paths to check
legacy_candidates = [
    ".github/copilot-instructions.md",
    ".github/agents",
    ".github/skills",
    "CLAUDE.md",
    ".claude",
    "AGENTS.md",
]

legacy_paths = [
    os.path.join(project_root, p)
    for p in legacy_candidates
    if os.path.exists(os.path.join(project_root, p))
]

if not legacy_paths:
    sys.exit(1)  # no legacy sources → no import needed

try:
    ai_files = [
        os.path.join(ai_dir, f)
        for f in os.listdir(ai_dir)
        if os.path.isfile(os.path.join(ai_dir, f))
    ]
    ai_mtime = min(os.path.getmtime(f) for f in ai_files) if ai_files else 0
    legacy_mtime = max(os.path.getmtime(p) for p in legacy_paths)
    # Import if any legacy file is newer than the oldest .ai/ file
    sys.exit(0 if legacy_mtime > ai_mtime else 1)
except Exception:
    sys.exit(1)
PYEOF
        return $?
    fi

    return 1
}

# ── sync_knowledge ────────────────────────────────────────────────────────────
# Main Stage -1 entry point.
sync_knowledge() {
    local dry_run=false
    local force_import=false
    local integrate_mode=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)   dry_run=true;    shift ;;
            --import)    force_import=true; shift ;;
            --integrate) integrate_mode=true; shift ;;
            --dir=*)     PROJECT_ROOT="${1#*=}"; shift ;;
            --dir)       PROJECT_ROOT="${2}"; shift 2 ;;
            *)           shift ;;
        esac
    done

    # ── Step 1: Resolve PROJECT_ROOT ─────────────────────────────────────────
    PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
    export PROJECT_ROOT

    log_step "[Stage -1] Knowledge sync — PROJECT_ROOT: ${PROJECT_ROOT}"

    if [[ "${dry_run}" == "true" ]]; then
        log_info "[Stage -1] DRY RUN — no files will be written, no ars calls"
        echo ""
    fi

    local ai_dir="${PROJECT_ROOT}/.ai"
    local manifest_yaml="${ai_dir}/manifest.yaml"
    local stamp_path="${PROJECT_ROOT}/.skeleton-dev/compose.stamp"

    # ── Guard: ars required for non-dry-run ──────────────────────────────────
    if [[ "${dry_run}" != "true" ]]; then
        _require_ars
    fi

    # ── Step 2: Load .ai/manifest.yaml ───────────────────────────────────────
    local provider="copilot"
    local import_policy="merge_on_stale"

    if [[ -f "${manifest_yaml}" ]]; then
        log_info "[Stage -1] Loading manifest: ${manifest_yaml}"
        local _p; _p="$(_read_manifest_field "${manifest_yaml}" "provider")"
        [[ -n "${_p}" ]] && provider="${_p}"
        local _ip; _ip="$(_read_manifest_field "${manifest_yaml}" "import_policy")"
        [[ -n "${_ip}" ]] && import_policy="${_ip}"
    elif [[ "${integrate_mode}" == "true" ]]; then
        log_info "[Stage -1] No manifest — scaffold mode (integrate)"
    else
        log_warn "[Stage -1] No .ai/manifest.yaml — using defaults (provider=${provider}, import_policy=${import_policy})"
    fi

    log_info "[Stage -1] provider=${provider}, import_policy=${import_policy}"

    # ── Step 3: IMPORT if policy triggers ────────────────────────────────────
    if _should_import "${ai_dir}" "${import_policy}" "${force_import}" "${integrate_mode}"; then
        local detected
        detected="$(python3 "${_SYNC_SCRIPT_DIR}/detect_legacy.py" "${PROJECT_ROOT}" 2>/dev/null || echo "[]")"
        log_info "[Stage -1] Import triggered"
        log_info "[Stage -1] Legacy sources: $(echo "${detected}" | python3 -c 'import sys,json; srcs=json.load(sys.stdin); print(", ".join(s["source"] for s in srcs) or "none")'  2>/dev/null || echo "${detected}")"

        if [[ "${dry_run}" == "true" ]]; then
            log_info "[Stage -1] [DRY RUN] Would run: ars import '*' --merge"
        else
            log_step "[Stage -1] Running: ars import '*' --merge"
            ars import '*' --merge || log_warn "[Stage -1] ars import returned non-zero — continuing"
        fi
    else
        log_info "[Stage -1] Import skipped — .ai/ is healthy (policy: ${import_policy})"
    fi

    # ── Step 4: ars validate ──────────────────────────────────────────────────
    if [[ "${dry_run}" == "true" ]]; then
        log_info "[Stage -1] [DRY RUN] Would run: ars validate"
    elif [[ -d "${ai_dir}" ]]; then
        log_step "[Stage -1] Running: ars validate"
        if ! ars validate; then
            log_error "[Stage -1] ars validate failed — run 'skeleton doctor' for details"
            exit 1
        fi
        log_ok "[Stage -1] ars validate passed"
    else
        log_info "[Stage -1] ars validate skipped — .ai/ not present"
    fi

    # ── Step 5: COMPOSE if stale ──────────────────────────────────────────────
    if [[ "${dry_run}" == "true" ]]; then
        log_info "[Stage -1] [DRY RUN] Would check: sha256(.ai/**) vs .skeleton-dev/compose.stamp"
        log_info "[Stage -1] [DRY RUN] Would run if stale: ars compose --target ${provider}"
    elif [[ -d "${ai_dir}" ]]; then
        # Source state.sh for compose_stamp_valid / compose_stamp_write
        # shellcheck source=scripts/lib/state.sh
        source "${_SYNC_SCRIPT_DIR}/../lib/state.sh"

        if compose_stamp_valid "${ai_dir}"; then
            log_step "[Stage -1] .ai/ changed — running: ars compose --target ${provider}"

            local compose_exit=0
            ars compose --target "${provider}" || compose_exit=$?

            if [[ ${compose_exit} -ne 0 ]]; then
                # ── Step 6: Legacy fallback ───────────────────────────────────
                if [[ -f "${stamp_path}" ]]; then
                    log_warn "[Stage -1] ars compose failed — using last good composed artifacts"
                    log_warn "[Stage -1] SKELETON_COMPOSED_DEGRADED=true"
                    export SKELETON_COMPOSED_DEGRADED=true
                else
                    log_error "[Stage -1] ars compose failed and no previous stamp exists"
                    exit 1
                fi
            fi
        else
            log_info "[Stage -1] Compose skipped — stamp is current"
        fi
    else
        log_info "[Stage -1] Compose skipped — .ai/ not present"
    fi

    # ── Step 7: Abort if .ai/ still missing after import ─────────────────────
    if [[ ! -d "${ai_dir}" ]] && [[ "${dry_run}" != "true" ]]; then
        log_error "[Stage -1] .ai/ directory not found after sync"
        log_info "  Run: skeleton integrate   (to set up ARES for the first time)"
        log_info "  Or:  skeleton run --import (to force import from legacy sources)"
        exit 1
    fi

    # ── Step 8: Update compose stamp ─────────────────────────────────────────
    if [[ "${dry_run}" == "true" ]]; then
        log_info "[Stage -1] [DRY RUN] Would write: .skeleton-dev/compose.stamp"
        echo ""
        log_ok "[Stage -1] DRY RUN complete — no files written"
    elif [[ -d "${ai_dir}" ]]; then
        # Always refresh stamp after sync (import may have mutated .ai/)
        compose_stamp_write "${ai_dir}" >/dev/null || true
        log_ok "[Stage -1] Knowledge sync complete"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
sync_knowledge "$@"
