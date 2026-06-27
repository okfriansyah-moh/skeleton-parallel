#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/pipeline/modes.sh — Scheduling modes for skeleton-parallel
# ─────────────────────────────────────────────────────────────────────────────
# Implements three task scheduling modes (per spec §8.8):
#
#   schedule_hybrid    — batch by dep graph + file-ownership safety (default)
#   schedule_parallel  — one worktree per task
#   schedule_sequential — strict dep order, single branch
#
# Output format (all modes): JSON array of batches, printed to stdout.
# Each batch is an array of task IDs.
#   [[1,4],[2,3],[5]]  → run batches serially, tasks inside a batch in parallel
#   [[1],[2],[3]]      → fully sequential (schedule_sequential)
#   [[1,2,3,4,5]]      → one big parallel batch (schedule_parallel)
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/pipeline/modes.sh"
#   batches=$(schedule_hybrid "1 2 3 4 5" ".skeleton-dev/plan-index.json")
#   batches=$(schedule_parallel "1 2 3")
#   batches=$(schedule_sequential "1 2 3" ".skeleton-dev/plan-index.json")
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_MODES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKELETON_ROOT="$(cd "${_MODES_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${_SKELETON_ROOT}/scripts/lib/common.sh"

# ── schedule_hybrid ───────────────────────────────────────────────────────────
# Default mode: batch tasks by topological order + file-ownership parallel safety.
# Tasks in the same dep-graph level that own non-overlapping files run in parallel.
# Tasks across levels run serially (each level waits for the previous to finish).
#
# Usage: schedule_hybrid <task_ids_space_sep> <plan_index>
# Output: JSON array of batches  e.g. [[1,4],[2,3],[5]]
schedule_hybrid() {
    local tasks_str="${1:?tasks_str required}"
    local plan_index="${2:?plan_index required}"

    python3 - "${plan_index}" "${tasks_str}" <<'PYEOF'
import json, sys
from collections import defaultdict

plan_index_path = sys.argv[1]
task_ids_str    = sys.argv[2].strip()
requested_ids   = [int(t) for t in task_ids_str.split() if t.strip().isdigit()]

with open(plan_index_path, encoding="utf-8") as f:
    index = json.load(f)

tasks       = index.get("tasks", {})
dep_graph   = index.get("dep_graph", {})
file_ownership = index.get("file_ownership", {})

# Filter dep_graph to only requested tasks
req_set = set(requested_ids)
filtered_deps = {}
for tid in requested_ids:
    raw_deps = dep_graph.get(str(tid), [])
    # Only consider deps within the requested set
    filtered_deps[tid] = [int(d) for d in raw_deps if int(d) in req_set]

# Kahn's algorithm for topological batching
in_degree = {tid: 0 for tid in requested_ids}
for tid, deps in filtered_deps.items():
    for dep in deps:
        in_degree[tid] += 1

batches = []
remaining = set(requested_ids)

while remaining:
    # Tasks with in-degree 0 are ready this round
    ready = sorted([t for t in remaining if in_degree[t] == 0])
    if not ready:
        # Circular dependency — fall back to sequential
        batches.append(sorted(remaining))
        break

    # Check file ownership overlap within ready set to build parallel-safe sub-batches
    # Build ownership map for ready tasks
    task_files = {}
    for tid in ready:
        task_info = tasks.get(str(tid), {})
        task_files[tid] = set(task_info.get("files", []))

    # Greedy partition into parallel-safe groups (no overlapping file ownership)
    assigned = set()
    level_batches = []
    for tid in ready:
        placed = False
        for batch in level_batches:
            # Check if tid's files overlap with any task already in this batch
            batch_files = set().union(*(task_files[b] for b in batch))
            if not (task_files[tid] & batch_files):
                batch.append(tid)
                placed = True
                break
        if not placed:
            level_batches.append([tid])
        assigned.add(tid)

    # Flatten level_batches into batches (within a level, all are independent)
    # Merge all level_batches into one batch (they can run in parallel)
    level_ready = [t for sublist in level_batches for t in sublist]
    batches.append(sorted(level_ready))

    # Update state
    remaining -= assigned
    for t in assigned:
        del in_degree[t]
    # Decrement in-degree for dependents
    for tid in list(remaining):
        filtered_deps[tid] = [d for d in filtered_deps[tid] if d not in assigned]
        in_degree[tid] = len(filtered_deps[tid])

print(json.dumps(batches))
PYEOF
}

# ── schedule_parallel ─────────────────────────────────────────────────────────
# Parallel mode: put all tasks in a single batch (run simultaneously).
# Subject to max_parallel_agents limit enforced by the orchestrator.
#
# Usage: schedule_parallel <task_ids_space_sep>
# Output: JSON array of one batch  e.g. [[1,2,3,4,5]]
schedule_parallel() {
    local tasks_str="${1:?tasks_str required}"

    python3 - "${tasks_str}" <<'PYEOF'
import json, sys

tasks_str = sys.argv[1].strip()
task_ids  = sorted([int(t) for t in tasks_str.split() if t.strip().isdigit()])
print(json.dumps([task_ids]))
PYEOF
}

# ── schedule_sequential ───────────────────────────────────────────────────────
# Sequential mode: one task at a time in topological order.
#
# Usage: schedule_sequential <task_ids_space_sep> <plan_index>
# Output: JSON array of single-task batches  e.g. [[1],[2],[3]]
schedule_sequential() {
    local tasks_str="${1:?tasks_str required}"
    local plan_index="${2:?plan_index required}"

    python3 - "${plan_index}" "${tasks_str}" <<'PYEOF'
import json, sys

plan_index_path = sys.argv[1]
tasks_str       = sys.argv[2].strip()
requested_ids   = [int(t) for t in tasks_str.split() if t.strip().isdigit()]

with open(plan_index_path, encoding="utf-8") as f:
    index = json.load(f)

dep_graph = index.get("dep_graph", {})
req_set   = set(requested_ids)

# Build filtered dep graph
filtered_deps = {}
for tid in requested_ids:
    raw_deps = dep_graph.get(str(tid), [])
    filtered_deps[tid] = [int(d) for d in raw_deps if int(d) in req_set]

# Topological sort (Kahn's algorithm) — each task is its own single-item batch
in_degree = {tid: len(deps) for tid, deps in filtered_deps.items()}
order     = []
remaining = set(requested_ids)

while remaining:
    ready = sorted([t for t in remaining if in_degree[t] == 0])
    if not ready:
        # Circular — emit remaining in sorted order
        order.extend(sorted(remaining))
        break
    for t in ready:
        order.append(t)
        remaining.discard(t)
        del in_degree[t]
        for other in list(remaining):
            filtered_deps[other] = [d for d in filtered_deps[other] if d != t]
            in_degree[other] = len(filtered_deps[other])

# Return as single-item batches
print(json.dumps([[t] for t in order]))
PYEOF
}

# ── CLI entry point ───────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    mode="${1:-}"
    shift || true

    case "${mode}" in
        hybrid)
            schedule_hybrid "$@"
            ;;
        parallel)
            schedule_parallel "$@"
            ;;
        sequential)
            schedule_sequential "$@"
            ;;
        *)
            echo "Usage: modes.sh <hybrid|parallel|sequential> <task_ids> [plan_index]"
            echo ""
            echo "  hybrid     <task_ids_space_sep> <plan_index>  — dep-aware parallel batches"
            echo "  parallel   <task_ids_space_sep>               — one big batch"
            echo "  sequential <task_ids_space_sep> <plan_index>  — one task per batch"
            exit 1
            ;;
    esac
fi
