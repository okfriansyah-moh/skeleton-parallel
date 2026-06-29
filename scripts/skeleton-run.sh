#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/skeleton-run.sh — skeleton run: Main pipeline orchestrator
# ─────────────────────────────────────────────────────────────────────────────
# Wires Stage −1 through Stage [6] per spec §8.5:
#
#   Stage −1  Knowledge sync (ars import/validate/compose-if-stale)
#   RESOLVE   Plan selection · task selection · dep validation · scheduling
#   Stage  0  Per-task executor (L2 loop, 7-step agent chain)
#   Stage [2] Union merge (if ≥2 parallel tracks)
#   Stage [3] Post-merge review
#   Stage [4] Docs sync (advisory)
#   Stage [5a] Quality gates T3
#   Stage [5b] Acceptance gates
#   Stage [5c] Test-builder sufficiency
#   Stage [6]  git push + gh pr create
#
# Usage:
#   skeleton run [flags] [task IDs...]
#   skeleton run --dry-run
#   skeleton run 1 2 3 --parallel
#   skeleton run --tasks 4,5,6 --sequential --force-deps
#
# Flags:
#   --plan PATH           Use a specific PLAN.md (default: manifest.defaults.plan)
#   --tasks CSV           Comma-separated task IDs
#   --driver DRIVER       Override execution driver
#   --parallel            One worktree per task (subject to max_parallel_agents)
#   --sequential          Single branch, strict dep order
#   --no-auto-merge       Skip stages [2]-[6]; deferred to 'skeleton merge'
#   --skip-acceptance     Skip stages [5b]/[5c]
#   --acceptance-only     Run only [5b]/[5c] on current branch
#   --force-deps          Log warning about unsatisfied deps and proceed
#   --strict-deps         Fail if any dep is not completed (default)
#   --dry-run             Print execution plan; no agents invoked; no git changes
#   --full                Explicit alias for all pending tasks
#   --no-interactive      CI mode; fail if plan selection is ambiguous
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_RUN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKELETON_ROOT="$(cd "${_RUN_SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "${_SKELETON_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/config.sh
source "${_SKELETON_ROOT}/scripts/lib/config.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
_plan_path=""
_tasks_csv=""
_mode="hybrid"           # hybrid | parallel | sequential
_no_auto_merge=false
_skip_acceptance=false
_acceptance_only=false
_force_deps=false
_strict_deps=true
_dry_run=false
_select_all=false
_no_interactive="${SKELETON_NO_INTERACTIVE:-false}"
_explicit_tasks=()

# ── _parse_args ───────────────────────────────────────────────────────────────
_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --plan)            _plan_path="$2";  shift 2 ;;
            --plan=*)          _plan_path="${1#*=}"; shift ;;
            --tasks)           _tasks_csv="$2";  shift 2 ;;
            --tasks=*)         _tasks_csv="${1#*=}"; shift ;;
            --driver)          export SKELETON_DRIVER="$2"; shift 2 ;;
            --driver=*)        export SKELETON_DRIVER="${1#*=}"; shift ;;
            --parallel)        _mode="parallel";    shift ;;
            --sequential)      _mode="sequential";  shift ;;
            --no-auto-merge)   _no_auto_merge=true; shift ;;
            --skip-acceptance) _skip_acceptance=true; shift ;;
            --acceptance-only) _acceptance_only=true; shift ;;
            --force-deps)      _force_deps=true;  _strict_deps=false; shift ;;
            --strict-deps)     _strict_deps=true; shift ;;
            --dry-run)         _dry_run=true;  shift ;;
            --full)            _select_all=true; shift ;;
            --no-interactive)  _no_interactive=true; shift ;;
            --dir=*)           PROJECT_ROOT="${1#*=}"; shift ;;
            --dir)             PROJECT_ROOT="$2"; shift 2 ;;
            --)                shift; break ;;
            --*)               log_warn "[run] Unknown flag: $1"; shift ;;
            *)
                # Positional: numeric task IDs
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    _explicit_tasks+=("$1")
                fi
                shift
                ;;
        esac
    done
}

# ── _select_pending_tasks ─────────────────────────────────────────────────────
# Return space-separated list of pending task IDs from plan-index.json.
_select_pending_tasks() {
    local plan_index="$1"
    python3 - "${plan_index}" <<'PYEOF'
import json, sys

idx   = json.load(open(sys.argv[1]))
tasks = idx.get("tasks", {})
pending = [
    tid for tid, task in sorted(tasks.items(), key=lambda x: int(x[0]))
    if task.get("status", "pending") != "completed"
]
print(" ".join(pending))
PYEOF
}

# ── _validate_deps ────────────────────────────────────────────────────────────
# Check that all deps for requested tasks are completed or in the run set.
# strict=true  → die if any dep is not completed in plan-index
# force=true   → log warning and return 0
#
# Returns 0 if OK, 1 if violations found (and not force)
_validate_deps() {
    local tasks_str="$1"
    local plan_index="$2"
    local force_deps="${3:-false}"

    python3 - "${plan_index}" "${tasks_str}" "${force_deps}" <<'PYEOF'
import json, sys

plan_index_path = sys.argv[1]
tasks_str       = sys.argv[2]
force_deps      = sys.argv[3] == "true"

task_ids = [int(t) for t in tasks_str.split() if t.strip().isdigit()]
idx      = json.load(open(plan_index_path))
tasks    = idx.get("tasks", {})
dep_graph = idx.get("dep_graph", {})

violations = []
for tid in task_ids:
    task = tasks.get(str(tid), {})
    raw_deps = dep_graph.get(str(tid), task.get("depends_on", []))
    for dep_id in raw_deps:
        dep   = tasks.get(str(dep_id), {})
        status = dep.get("status", "pending")
        if status != "completed":
            violations.append((tid, dep_id, dep.get("name", f"Task {dep_id}")))

if violations:
    for task_id, dep_id, dep_name in violations:
        print(
            f"[WARN]  Task {task_id} depends on incomplete Task {dep_id} ({dep_name!r})",
            file=sys.stderr,
        )
    if not force_deps:
        print(
            "[ERROR] Unsatisfied deps detected — use --force-deps to override",
            file=sys.stderr,
        )
        sys.exit(1)
    else:
        print(
            f"[WARN]  --force-deps active: proceeding despite {len(violations)} unsatisfied dep(s)",
            file=sys.stderr,
        )
PYEOF
}

# ── _ensure_plan_index ────────────────────────────────────────────────────────
# Ensure plan-index.json is current; regenerate if stale.
_ensure_plan_index() {
    local plan_path="$1"
    local index_path="${PROJECT_ROOT}/.skeleton-dev/plan-index.json"

    mkdir -p "${PROJECT_ROOT}/.skeleton-dev"

    if [[ ! -f "${index_path}" ]] || \
       [[ "${plan_path}" -nt "${index_path}" ]]; then
        log_info "[run] Refreshing plan index from ${plan_path}"
        python3 "${_SKELETON_ROOT}/scripts/plan/plan_parser.py" \
            "${plan_path}" --export "${index_path}" 2>/dev/null || true
    fi

    echo "${index_path}"
}

# ── _print_dry_run_plan ───────────────────────────────────────────────────────
# Print the full execution plan for --dry-run mode.
_print_dry_run_plan() {
    local tasks_str="$1"
    local plan_index="$2"
    local plan_path="$3"
    local mode="$4"

    local driver="${SKELETON_DRIVER:-cli_subscription}"
    local provider="${SKELETON_PROVIDER:-copilot}"

    echo ""
    echo -e "${BOLD}[DRY RUN] skeleton run execution plan${NC}"
    echo -e "${BOLD}════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Plan:     ${plan_path}"
    echo -e "  Tasks:    $(echo "${tasks_str}" | tr ' ' ',')"
    echo -e "  Mode:     ${mode}"
    echo -e "  Driver:   ${driver} (${provider})"
    echo ""

    # Stage -1
    echo -e "  ${CYAN}Stage -1:${NC} Knowledge sync"
    echo -e "            scripts/knowledge/sync.sh --dry-run"
    echo ""

    # Resolve batches
    echo -e "  ${CYAN}Stage  0:${NC} Execute tasks"
    local batches_json
    case "${mode}" in
        parallel)
            batches_json="$(bash "${_SKELETON_ROOT}/scripts/pipeline/modes.sh" \
                parallel "${tasks_str}" 2>/dev/null || echo "[[${tasks_str// /,}]]")"
            ;;
        sequential)
            batches_json="$(bash "${_SKELETON_ROOT}/scripts/pipeline/modes.sh" \
                sequential "${tasks_str}" "${plan_index}" 2>/dev/null || echo "[[${tasks_str// /,}]]")"
            ;;
        *)
            batches_json="$(bash "${_SKELETON_ROOT}/scripts/pipeline/modes.sh" \
                hybrid "${tasks_str}" "${plan_index}" 2>/dev/null || echo "[[${tasks_str// /,}]]")"
            ;;
    esac

    python3 - "${batches_json}" "${plan_index}" <<'PYEOF'
import json, sys

batches    = json.loads(sys.argv[1])
idx        = json.load(open(sys.argv[2]))
tasks      = idx.get("tasks", {})
dep_graph  = idx.get("dep_graph", {})

for i, batch in enumerate(batches, 1):
    task_names = []
    for tid in batch:
        name = tasks.get(str(tid), {}).get("name", f"Task {tid}")
        task_names.append(f"Task {tid} ({name[:30]})")
    parallel = "parallel" if len(batch) > 1 else "single"
    print(f"            Batch {i} [{parallel}]: {', '.join(str(t) for t in batch)}")
PYEOF

    echo ""

    # Stages [2]-[6]
    if [[ "${_no_auto_merge}" == "true" ]]; then
        echo -e "  ${YELLOW}Stage [2]:${NC} SKIPPED (--no-auto-merge; deferred to 'skeleton merge')"
        echo -e "  ${YELLOW}Stage [3]:${NC} SKIPPED"
        echo -e "  ${YELLOW}Stage [4]:${NC} SKIPPED"
        echo -e "  ${YELLOW}Stage [5]:${NC} SKIPPED"
        echo -e "  ${YELLOW}Stage [6]:${NC} SKIPPED"
    else
        # Apply skip matrix
        local num_tasks
        num_tasks="$(echo "${tasks_str}" | wc -w | tr -d ' ')"
        if [[ "${mode}" == "parallel" ]] && (( num_tasks > 1 )); then
            echo -e "  ${CYAN}Stage [2]:${NC} Union merge (${num_tasks} parallel tracks)"
        else
            echo -e "  ${YELLOW}Stage [2]:${NC} SKIPPED (${mode} mode / single track)"
        fi
        echo -e "  ${CYAN}Stage [3]:${NC} Post-merge review"
        echo -e "  ${CYAN}Stage [4]:${NC} Docs sync (advisory)"
        echo -e "  ${CYAN}Stage [5a]:${NC} Quality gates T3"
        if [[ "${_skip_acceptance}" == "true" ]]; then
            echo -e "  ${YELLOW}Stage [5b]:${NC} SKIPPED (--skip-acceptance)"
            echo -e "  ${YELLOW}Stage [5c]:${NC} SKIPPED (--skip-acceptance)"
        else
            echo -e "  ${CYAN}Stage [5b]:${NC} Acceptance gates"
            echo -e "  ${CYAN}Stage [5c]:${NC} Test-builder sufficiency"
        fi
        echo -e "  ${CYAN}Stage [6]:${NC} git push + gh pr create"
    fi

    echo ""
    echo -e "  ${GREEN}[DRY RUN] No agents invoked, no git changes.${NC}"
    echo ""
}

# ── _run_stage_0 ──────────────────────────────────────────────────────────────
# Execute Stage 0: run task batches via task_executor.sh.
# Returns 0 if all batches succeeded, 1 on any failure.
_run_stage_0() {
    local tasks_str="$1"
    local plan_index="$2"
    local mode="$3"
    local work_dir="${PROJECT_ROOT}"

    # Source task executor
    # shellcheck source=scripts/pipeline/task_executor.sh
    source "${_SKELETON_ROOT}/scripts/pipeline/task_executor.sh"
    # shellcheck source=scripts/pipeline/modes.sh
    source "${_SKELETON_ROOT}/scripts/pipeline/modes.sh"

    # Build execution batches
    local batches_json
    case "${mode}" in
        parallel)   batches_json="$(schedule_parallel "${tasks_str}")" ;;
        sequential) batches_json="$(schedule_sequential "${tasks_str}" "${plan_index}")" ;;
        *)          batches_json="$(schedule_hybrid "${tasks_str}" "${plan_index}")" ;;
    esac

    log_step "[Stage 0] Executing task batches (mode: ${mode})"

    local failed_tasks=()
    local all_successful=true

    # Parse batches using Python and run them
    python3 - "${batches_json}" <<'PYEOF' > /tmp/skeleton-run-batches.txt
import json, sys
batches = json.loads(sys.argv[1])
for i, batch in enumerate(batches, 1):
    print(f"BATCH {i}: {' '.join(str(t) for t in batch)}")
PYEOF

    local batch_line
    while IFS= read -r batch_line; do
        if [[ "${batch_line}" =~ ^BATCH\ ([0-9]+):\ (.+)$ ]]; then
            local batch_num="${BASH_REMATCH[1]}"
            local batch_tasks="${BASH_REMATCH[2]}"

            log_step "[Stage 0] Batch ${batch_num}: tasks ${batch_tasks}"

            # Run tasks in this batch (parallel if multiple, sequential if single)
            local batch_task_array=()
            read -ra batch_task_array <<< "${batch_tasks}"
            local batch_pids=()
            local batch_task_pids=()

            if [[ ${#batch_task_array[@]} -gt 1 ]] && [[ "${mode}" != "sequential" ]]; then
                # Parallel execution within batch
                for task_id in "${batch_task_array[@]}"; do
                    (
                        execute_task "${task_id}" "${SKELETON_DRIVER:-cli_subscription}" \
                            "${plan_index}" "${work_dir}"
                    ) &
                    batch_pids+=($!)
                    batch_task_pids+=("${task_id}")
                done

                # Wait for all in this batch
                local bi=0
                for pid in "${batch_pids[@]}"; do
                    if ! wait "${pid}" 2>/dev/null; then
                        failed_tasks+=("${batch_task_pids[$bi]}")
                        all_successful=false
                    fi
                    (( bi++ ))
                done
            else
                # Sequential execution within batch (or forced sequential mode)
                for task_id in "${batch_task_array[@]}"; do
                    if ! execute_task "${task_id}" "${SKELETON_DRIVER:-cli_subscription}" \
                            "${plan_index}" "${work_dir}"; then
                        failed_tasks+=("${task_id}")
                        all_successful=false
                    fi
                done
            fi
        fi
    done < /tmp/skeleton-run-batches.txt
    rm -f /tmp/skeleton-run-batches.txt

    if [[ ${#failed_tasks[@]} -gt 0 ]]; then
        log_error "[Stage 0] Failed tasks: ${failed_tasks[*]}"
        return 1
    fi

    log_ok "[Stage 0] All tasks completed"
    return 0
}

# ── _run_post_merge_stages ────────────────────────────────────────────────────
# Run Stages [2]-[6] based on the skip matrix (spec §8.17).
_run_post_merge_stages() {
    local tasks_str="$1"
    local mode="$2"
    local integration_branch="${3:-integration/run-$(date +%Y%m%d-%H%M%S)}"

    # shellcheck source=scripts/pipeline/integration.sh
    source "${_SKELETON_ROOT}/scripts/pipeline/integration.sh"
    # shellcheck source=scripts/pipeline/global_validation.sh
    source "${_SKELETON_ROOT}/scripts/pipeline/global_validation.sh"
    # shellcheck source=scripts/pipeline/pr.sh
    source "${_SKELETON_ROOT}/scripts/pipeline/pr.sh"

    local num_tasks
    num_tasks="$(echo "${tasks_str}" | wc -w | tr -d ' ')"

    # Stage [2] Skip Matrix (spec §8.17)
    local run_merge=false
    if [[ "${mode}" == "parallel" ]] && (( num_tasks > 1 )); then
        run_merge=true
        log_step "[Stage 2] Union merge (${num_tasks} parallel tracks)"
    else
        log_info "[Stage 2] Skipped (${mode} mode, single track)"
    fi

    if ${run_merge}; then
        # Collect track branches
        local track_branches=()
        for task_id in ${tasks_str}; do
            track_branches+=("track/task-${task_id}")
        done
        run_union_merge "${integration_branch}" "${track_branches[@]}" || {
            log_error "[Stage 2] Union merge failed"
            return 1
        }
    fi

    # Stage [3] Post-merge review
    local review_branch="${integration_branch}"
    if ! ${run_merge}; then
        review_branch="$(git -C "${PROJECT_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
    fi
    run_post_merge_review "${PROJECT_ROOT}" "${review_branch}" || {
        log_error "[Stage 3] Post-merge review failed"
        return 1
    }

    # Stage [4] Docs sync (advisory — non-blocking)
    run_docs_sync "${PROJECT_ROOT}" || true

    # Stage [5a] Quality gates
    if ! run_5a "${PROJECT_ROOT}"; then
        log_error "[Stage 5a] Quality gates failed — blocking PR"
        return 1
    fi

    # Stage [5b]/[5c] Acceptance
    if [[ "${_skip_acceptance}" != "true" ]]; then
        if [[ -f "${_SKELETON_ROOT}/scripts/pipeline/acceptance.sh" ]]; then
            # shellcheck source=scripts/pipeline/acceptance.sh
            source "${_SKELETON_ROOT}/scripts/pipeline/acceptance.sh"
            run_5b "${PROJECT_ROOT}" || {
                log_error "[Stage 5b] Acceptance failed"
                return 1
            }
            run_5c "${PROJECT_ROOT}" || {
                log_error "[Stage 5c] Test sufficiency check failed"
                return 1
            }
        else
            log_info "[Stage 5b/5c] Skipped (acceptance.sh not implemented yet)"
        fi
    else
        log_info "[Stage 5b/5c] Skipped (--skip-acceptance)"
    fi

    # Stage [6] PR
    local pr_title="feat: skeleton run — tasks ${tasks_str// /,}"
    run_pr "${review_branch}" "${pr_title}" || {
        log_warn "[Stage 6] PR creation failed or skipped"
    }

    log_ok "Pipeline complete"
    return 0
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
    _parse_args "$@"

    # ── Load config ─────────────────────────────────────────────────────────
    load_config "${PROJECT_ROOT}" 2>/dev/null || true

    # ── Auto-inject 9router env vars if driver=router_http ───────────────────
    if [[ -z "${ANTHROPIC_BASE_URL:-}" ]] && \
       [[ "${SKELETON_DRIVER:-}" == "router_http" ]]; then
        local _inject="${PROJECT_ROOT}/router/inject-env.sh"
        if [[ -f "${_inject}" ]]; then
            # shellcheck source=/dev/null
            source "${_inject}"
            log_info "[run] Auto-sourced router/inject-env.sh (driver=router_http)"
        else
            log_warn "[run] driver=router_http but router/inject-env.sh not found"
        fi
    fi

    # ── Resolve plan path ────────────────────────────────────────────────────
    if [[ -z "${_plan_path}" ]]; then
        _plan_path="${SKELETON_PLAN:-docs/PLAN.md}"
    fi

    # Handle relative plan path
    if [[ ! "${_plan_path}" == /* ]]; then
        _plan_path="${PROJECT_ROOT}/${_plan_path}"
    fi

    if [[ ! -f "${_plan_path}" ]]; then
        # Try to find PLAN*.md files
        local plan_files=()
        mapfile -t plan_files < <(find "${PROJECT_ROOT}/docs" -name "PLAN*.md" 2>/dev/null | sort)

        if [[ ${#plan_files[@]} -eq 0 ]]; then
            die "[run] No PLAN.md found at ${_plan_path}. Run: skeleton init"
        elif [[ ${#plan_files[@]} -eq 1 ]]; then
            _plan_path="${plan_files[0]}"
        else
            if [[ "${_no_interactive}" == "true" ]]; then
                die "[run] Multiple PLAN*.md found and --no-interactive set. Use --plan PATH"
            fi
            log_info "[run] Multiple PLAN*.md found — using first: ${plan_files[0]}"
            _plan_path="${plan_files[0]}"
        fi
    fi

    log_info "[run] Plan: ${_plan_path}"

    # ── Ensure plan-index is current ─────────────────────────────────────────
    local plan_index
    plan_index="$(_ensure_plan_index "${_plan_path}")"

    # ── Select tasks ──────────────────────────────────────────────────────────
    local tasks_str=""

    if [[ ${#_explicit_tasks[@]} -gt 0 ]]; then
        tasks_str="${_explicit_tasks[*]}"
    elif [[ -n "${_tasks_csv}" ]]; then
        tasks_str="${_tasks_csv//,/ }"
    else
        tasks_str="$(_select_pending_tasks "${plan_index}")"
    fi

    if [[ -z "${tasks_str}" ]]; then
        log_ok "[run] No pending tasks found — nothing to do"
        exit 0
    fi

    log_info "[run] Tasks: ${tasks_str}"
    log_info "[run] Mode:  ${_mode}"

    # ── Dry run ───────────────────────────────────────────────────────────────
    # NOTE: dry-run precedes dep validation to always show the plan
    if [[ "${_dry_run}" == "true" ]]; then
        [[ "${_force_deps}" == "true" ]] && \
            log_warn "[run] --force-deps active: dependency checks relaxed in this run"
        _print_dry_run_plan "${tasks_str}" "${plan_index}" "${_plan_path}" "${_mode}"
        exit 0
    fi

    # ── Dependency validation ─────────────────────────────────────────────────
    if [[ "${_force_deps}" == "true" ]]; then
        log_warn "[run] --force-deps: skipping strict dependency validation"
        _validate_deps "${tasks_str}" "${plan_index}" "true" 2>&1 || true
    elif [[ "${_strict_deps}" == "true" ]]; then
        log_step "[run] Validating task dependencies (--strict-deps)"
        _validate_deps "${tasks_str}" "${plan_index}" "false" || {
            log_error "[run] Dependency validation failed (use --force-deps to override)"
            exit 1
        }
    fi

    # ── Stage −1: Knowledge sync ──────────────────────────────────────────────
    log_step "════ Stage -1: Knowledge sync ════"
    if [[ -f "${_SKELETON_ROOT}/scripts/knowledge/sync.sh" ]]; then
        bash "${_SKELETON_ROOT}/scripts/knowledge/sync.sh" --dry-run 2>/dev/null || true
    else
        log_warn "[Stage -1] sync.sh not found — skipping"
    fi

    # ── Router check ──────────────────────────────────────────────────────────
    if [[ -f "${_SKELETON_ROOT}/scripts/lib/router.sh" ]]; then
        # shellcheck source=scripts/lib/router.sh
        source "${_SKELETON_ROOT}/scripts/lib/router.sh" 2>/dev/null || true
        router_auto_start_if_needed 2>/dev/null || true
    fi

    # ── Stage 0: Execute tasks ────────────────────────────────────────────────
    log_step "════ Stage 0: Execute tasks ════"
    local stage0_rc=0
    _run_stage_0 "${tasks_str}" "${plan_index}" "${_mode}" || stage0_rc=$?

    if [[ ${stage0_rc} -ne 0 ]]; then
        log_error "[run] Stage 0 failed with ${stage0_rc}"
        exit "${stage0_rc}"
    fi

    # ── Post-Stage-0: [2]-[6] ─────────────────────────────────────────────────
    if [[ "${_no_auto_merge}" == "true" ]]; then
        log_info "[run] --no-auto-merge: Stages [2]-[6] deferred to 'skeleton merge'"
        log_ok "[run] Stage 0 complete. Run 'skeleton merge' when ready."
        exit 0
    fi

    if [[ "${_acceptance_only}" == "true" ]]; then
        log_step "════ Stage 5b/5c: Acceptance only ════"
        # Just run acceptance on current branch
        if [[ -f "${_SKELETON_ROOT}/scripts/pipeline/acceptance.sh" ]]; then
            source "${_SKELETON_ROOT}/scripts/pipeline/acceptance.sh"
            run_5b "${PROJECT_ROOT}" || exit 1
            run_5c "${PROJECT_ROOT}" || exit 1
        fi
        exit 0
    fi

    log_step "════ Stages [2]-[6]: Integration pipeline ════"
    _run_post_merge_stages "${tasks_str}" "${_mode}" || exit 1

    exit 0
}

main "$@"
