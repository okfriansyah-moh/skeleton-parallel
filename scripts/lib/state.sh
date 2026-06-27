#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/lib/state.sh — .skeleton-dev/ state management for skeleton-parallel
# ─────────────────────────────────────────────────────────────────────────────
# Provides primitives for:
#   - Directory init + one-release migration from .parallel-dev/
#   - run-status.json row read/write (per-stage pipeline state)
#   - events.jsonl append (structured observability log)
#   - compose.stamp read/write (Stage -1 staleness detection)
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/lib/state.sh"
#   state_init "${PROJECT_ROOT}"
#   run_status_write "task_1" "task_runner" "completed"
#   events_append "task_start" '{"task":1}'
# ─────────────────────────────────────────────────────────────────────────────

# Guard: idempotent sourcing
[[ -n "${STATE_LOADED:-}" ]] && return 0
STATE_LOADED=1

# Depend on common utilities
_STATE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_STATE_LIB_DIR}/common.sh"

# ── Directory names (overridable for testing) ─────────────────────────────────
SKELETON_DEV_DIR="${SKELETON_DEV_DIR:-.skeleton-dev}"
PARALLEL_DEV_DIR="${PARALLEL_DEV_DIR:-.parallel-dev}"

# ── state_init ────────────────────────────────────────────────────────────────
# Create .skeleton-dev/ and sub-directories. Idempotent.
# Migration shim: copy .parallel-dev/state.json if .skeleton-dev/run-status.json
# is absent (one-release backwards compatibility).
#
# Usage: state_init [project_root]
state_init() {
    local project_root="${1:-${PROJECT_ROOT}}"
    local dev_dir="${project_root}/${SKELETON_DEV_DIR}"

    mkdir -p "${dev_dir}/logs"

    # ── One-release migration: .parallel-dev/ → .skeleton-dev/ ───────────────
    local old_state="${project_root}/${PARALLEL_DEV_DIR}/state.json"
    local new_status="${dev_dir}/run-status.json"

    if [[ ! -f "${new_status}" ]] && [[ -f "${old_state}" ]]; then
        log_info "[state] Migrating state from ${PARALLEL_DEV_DIR}/ → ${SKELETON_DEV_DIR}/"
        cp "${old_state}" "${new_status}" 2>/dev/null || true
    fi

    # ── Initialize run-status.json if absent ─────────────────────────────────
    if [[ ! -f "${new_status}" ]]; then
        echo '{}' > "${new_status}"
    fi

    # ── Initialize events.jsonl if absent ────────────────────────────────────
    local events_file="${dev_dir}/events.jsonl"
    [[ -f "${events_file}" ]] || touch "${events_file}"

    log_ok "[state] Initialized ${dev_dir}/"
}

# ── run_status_write ──────────────────────────────────────────────────────────
# Write or update a row in .skeleton-dev/run-status.json.
# Rows are keyed by: task_N, post-merge-review, docs-sync,
#   global-validation-5a, global-validation-5b, global-validation-5c,
#   remediation, pr-create
#
# Usage: run_status_write <key> <stage> <status>
#   key    — e.g., "task_1", "global-validation-5a"
#   stage  — e.g., "task_runner", "dto_guardian", "completed"
#   status — e.g., "running", "completed", "failed", "FAILED"
run_status_write() {
    local key="${1:?key required}"
    local stage="${2:?stage required}"
    local status_val="${3:?status required}"

    local dev_dir="${PROJECT_ROOT}/${SKELETON_DEV_DIR}"
    local status_file="${dev_dir}/run-status.json"

    mkdir -p "${dev_dir}"
    [[ -f "${status_file}" ]] || echo '{}' > "${status_file}"

    python3 - "${status_file}" "${key}" "${stage}" "${status_val}" <<'PYEOF'
import sys, json, time, os

path, key, stage, status = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError, OSError):
    data = {}

data[key] = {
    "key":        key,
    "stage":      stage,
    "status":     status,
    "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PYEOF
}

# ── run_status_read ───────────────────────────────────────────────────────────
# Read a single row from run-status.json as a JSON object string.
# Returns '{}' if the key is not present or file is missing.
#
# Usage: entry=$(run_status_read "task_1")
run_status_read() {
    local key="${1:?key required}"
    local status_file="${PROJECT_ROOT}/${SKELETON_DEV_DIR}/run-status.json"

    [[ -f "${status_file}" ]] || { echo "{}"; return 0; }

    python3 - "${status_file}" "${key}" <<'PYEOF'
import sys, json

path, key = sys.argv[1], sys.argv[2]

try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    print(json.dumps(data.get(key, {})))
except Exception:
    print("{}")
PYEOF
}

# ── events_append ─────────────────────────────────────────────────────────────
# Append a JSONL event to .skeleton-dev/events.jsonl.
# Each line is a JSON object with type + timestamp + payload fields.
#
# Usage: events_append <type> <payload_json>
#   type         — e.g., "task_start", "task_complete", "stage_failed"
#   payload_json — valid JSON object string (default: '{}')
#
# Output format (per §16.3):
#   {"type":"task_start","timestamp":"2026-06-27T00:00:00Z","task":1}
events_append() {
    local event_type="${1:?event_type required}"
    local payload="${2:-{\}}"

    local dev_dir="${PROJECT_ROOT}/${SKELETON_DEV_DIR}"
    local events_file="${dev_dir}/events.jsonl"

    mkdir -p "${dev_dir}"

    python3 - "${events_file}" "${event_type}" "${payload}" <<'PYEOF'
import sys, json, time

events_file, event_type, payload_str = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    payload = json.loads(payload_str)
    if not isinstance(payload, dict):
        payload = {"value": payload}
except json.JSONDecodeError:
    payload = {"raw": payload_str}

event = {
    "type":      event_type,
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
event.update(payload)

with open(events_file, "a", encoding="utf-8") as f:
    f.write(json.dumps(event, ensure_ascii=False) + "\n")
PYEOF
}

# ── compose_stamp_write ───────────────────────────────────────────────────────
# Compute sha256 of all files under ai_dir and write to compose.stamp.
# Deterministic: walks directory tree in sorted order.
#
# Usage: compose_stamp_write <ai_dir>
compose_stamp_write() {
    local ai_dir="${1:?ai_dir required}"
    local stamp_file="${PROJECT_ROOT}/${SKELETON_DEV_DIR}/compose.stamp"

    mkdir -p "$(dirname "${stamp_file}")"

    python3 - "${ai_dir}" "${stamp_file}" <<'PYEOF'
import sys, hashlib, os

ai_dir, stamp_path = sys.argv[1], sys.argv[2]
h = hashlib.sha256()

if os.path.isdir(ai_dir):
    for root, dirs, files in os.walk(ai_dir):
        dirs.sort()  # deterministic tree traversal
        for fname in sorted(files):
            fpath = os.path.join(root, fname)
            rel   = os.path.relpath(fpath, ai_dir)
            h.update(rel.encode("utf-8"))
            try:
                with open(fpath, "rb") as f:
                    h.update(f.read())
            except OSError:
                pass

digest = h.hexdigest()
with open(stamp_path, "w", encoding="utf-8") as f:
    f.write(digest + "\n")
print(digest)
PYEOF
}

# ── compose_stamp_valid ───────────────────────────────────────────────────────
# Check whether the compose stamp matches the current .ai/ content.
# Returns 0 (exit success) if STALE (compose needed).
# Returns 1 (exit failure) if VALID (no recompose needed).
#
# Callers:
#   if compose_stamp_valid "${ai_dir}"; then ars_compose ...; fi
#
# Usage: compose_stamp_valid <ai_dir>
compose_stamp_valid() {
    local ai_dir="${1:?ai_dir required}"
    local stamp_file="${PROJECT_ROOT}/${SKELETON_DEV_DIR}/compose.stamp"

    # No stamp → always stale
    [[ -f "${stamp_file}" ]] || return 0

    local stored_hash
    stored_hash="$(tr -d '[:space:]' < "${stamp_file}")"

    local current_hash
    current_hash="$(python3 - "${ai_dir}" <<'PYEOF'
import sys, hashlib, os

ai_dir = sys.argv[1]
h = hashlib.sha256()

if os.path.isdir(ai_dir):
    for root, dirs, files in os.walk(ai_dir):
        dirs.sort()
        for fname in sorted(files):
            fpath = os.path.join(root, fname)
            rel   = os.path.relpath(fpath, ai_dir)
            h.update(rel.encode("utf-8"))
            try:
                with open(fpath, "rb") as f:
                    h.update(f.read())
            except OSError:
                pass

print(h.hexdigest())
PYEOF
)"

    # Return 0 if stale (hashes differ), 1 if valid (hashes match)
    [[ "${current_hash}" != "${stored_hash}" ]]
}
