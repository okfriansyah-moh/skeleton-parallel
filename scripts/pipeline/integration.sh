#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/pipeline/integration.sh — Union merge [2], post-merge review [3],
#                                   and docs-sync [4]
# ─────────────────────────────────────────────────────────────────────────────
# Extracted from run_parallel.sh cmd_merge(), run_post_merge_review(), and
# run_docs_sync(). Max 5 retries on merge and post-merge review; rollback on
# exceed. Docs-sync is always advisory (non-blocking).
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/pipeline/integration.sh"
#   run_union_merge "${INTEGRATION_BRANCH}" "${BRANCH_1}" "${BRANCH_2}"
#   run_post_merge_review "${PROJECT_ROOT}" "${INTEGRATION_BRANCH}"
#   run_docs_sync "${PROJECT_ROOT}"
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_INTEGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_INTEGRATION_DIR}/../lib/common.sh"
# shellcheck source=scripts/lib/agent.sh
source "${_INTEGRATION_DIR}/../lib/agent.sh"

# Per-stage retry limits (can be overridden by environment or config.sh)
MAX_RETRIES_MERGE="${MAX_RETRIES_MERGE:-5}"
MAX_RETRIES_REVIEW="${MAX_RETRIES_REVIEW:-5}"

# ── run_union_merge ───────────────────────────────────────────────────────────
# Stage [2]: merge all parallel track branches into a single integration branch.
# For each conflict, the conflict-resolver agent is invoked (up to
# MAX_RETRIES_MERGE attempts). Exits non-zero if any branch cannot be resolved.
#
# Usage: run_union_merge <integration_branch> <branch1> [branch2 ...]
run_union_merge() {
    local integration_branch="${1:?integration_branch required}"
    shift
    local branches=("$@")

    if [[ ${#branches[@]} -eq 0 ]]; then
        log_warn "[2] No branches to merge — skipping union merge"
        return 0
    fi

    log_step "[2] Union merge → ${integration_branch}"
    cd "${PROJECT_ROOT}"

    git checkout main
    git branch -D "${integration_branch}" 2>/dev/null || true
    git checkout -b "${integration_branch}"

    local merge_failures=0

    for branch in "${branches[@]}"; do
        log_info "[2] Merging ${branch}..."

        if git merge "${branch}" --no-edit 2>/dev/null; then
            log_ok "[2] Merged ${branch}"
            continue
        fi

        log_warn "[2] Conflict in ${branch} — invoking conflict-resolver"

        local resolved=false
        local attempt=0

        while (( attempt < MAX_RETRIES_MERGE )); do
            (( attempt++ ))
            log_info "[2] conflict-resolver attempt ${attempt}/${MAX_RETRIES_MERGE} for ${branch}"

            local conflict_log="${PROJECT_ROOT}/.skeleton-dev/logs/merge-conflict-${branch//\//-}-${attempt}.log"
            mkdir -p "$(dirname "${conflict_log}")"

            local model="${SKELETON_MODEL:-claude-sonnet-4-6}"
            local prompt_file
            prompt_file="$(mktemp)"

            cat > "${prompt_file}" <<PROMPT
Merge conflict detected when merging branch ${branch} (attempt ${attempt}/${MAX_RETRIES_MERGE}).
Resolve ALL conflicts using the union strategy — preserve ALL code from both sides, nothing is discarded.
Use skills: conflict-resolution, dto, pipeline, modularity.
Resolution rules:
  (1) contracts/ — combine all DTO definitions, keep all DTOs (additive only)
  (2) app/modules/ — each module owns its directory, keep both implementations
  (3) tests/ — combine all test files from all phases
  (4) app/orchestrator/ — later phase wiring changes win for stage registration
Stage all resolved files (git add -A) and commit.
PROMPT

            invoke_agent "merge" "conflict-resolver" "${PROJECT_ROOT}" \
                "${prompt_file}" "${model}" "${conflict_log}"
            local rc=$?
            rm -f "${prompt_file}"

            if [[ ${rc} -eq 0 ]] && ! git diff --name-only --diff-filter=U 2>/dev/null | grep -q .; then
                git add -A 2>/dev/null || true
                if ! git diff --cached --quiet 2>/dev/null; then
                    git commit --no-edit \
                        -m "merge: resolve conflicts from ${branch} (attempt ${attempt})" 2>/dev/null
                fi
                resolved=true
                log_ok "[2] Conflict resolved for ${branch} on attempt ${attempt}"
                break
            fi

            if (( attempt >= MAX_RETRIES_MERGE )); then
                git merge --abort 2>/dev/null || true
            fi
        done

        if ! ${resolved}; then
            log_error "[2] Could not resolve ${branch} after ${MAX_RETRIES_MERGE} attempts"
            (( merge_failures++ )) || true
        fi
    done

    if (( merge_failures > 0 )); then
        die "[2] Union merge failed: ${merge_failures} branch(es) had unresolvable conflicts"
    fi

    log_ok "[2] Union merge complete → ${integration_branch}"
}

# ── run_post_merge_review ─────────────────────────────────────────────────────
# Stage [3]: validate the integrated branch using the merge-reviewer agent.
# Up to MAX_RETRIES_REVIEW attempts. Returns 1 on exhaustion.
#
# Usage: run_post_merge_review <work_dir> <pr_branch>
run_post_merge_review() {
    local work_dir="${1:?work_dir required}"
    local pr_branch="${2:?pr_branch required}"

    log_step "[3] Post-merge review of ${pr_branch}"

    local attempt=0
    while (( attempt < MAX_RETRIES_REVIEW )); do
        (( attempt++ ))

        local model="${SKELETON_MODEL:-claude-sonnet-4-6}"
        local log_file="${work_dir}/.skeleton-dev/logs/post-merge-review-${attempt}.log"
        mkdir -p "$(dirname "${log_file}")"

        local prompt_file
        prompt_file="$(mktemp)"

        cat > "${prompt_file}" <<PROMPT
Post-merge review of integration branch '${pr_branch}' (attempt ${attempt}/${MAX_RETRIES_REVIEW}).
Validate the combined codebase:
  (1) DTO flow integrity — every stage's output DTO matches the next stage's input DTO
  (2) Module boundary enforcement — no cross-module imports, no DB driver in app/modules/
  (3) Orchestrator authority — modules called only by the orchestrator, never by each other
  (4) No quality gate regressions — syntax clean, imports valid, no print statements
Use skills: dto, pipeline, modularity, idempotency, code-quality, docs-sync.
MANDATORY: Use ONLY skills as primary knowledge source.
Report violations and commit fixes.
PROMPT

        log_info "[3] Post-merge review attempt ${attempt}/${MAX_RETRIES_REVIEW} (model: ${model})"

        invoke_agent "post-merge-review" "merge-reviewer" "${work_dir}" \
            "${prompt_file}" "${model}" "${log_file}"
        local rc=$?
        rm -f "${prompt_file}"

        if [[ ${rc} -eq 0 ]]; then
            log_ok "[3] Post-merge review passed"
            return 0
        fi

        log_warn "[3] Post-merge review attempt ${attempt} failed"
    done

    log_error "[3] Post-merge review failed after ${MAX_RETRIES_REVIEW} attempts"
    return 1
}

# ── run_docs_sync ─────────────────────────────────────────────────────────────
# Stage [4]: advisory docs-sync. Skipped silently if PROGRESS_REPORT.md absent.
# Always returns 0 (non-blocking). Logs to .skeleton-dev/logs/docs-sync.log.
#
# Usage: run_docs_sync [work_dir]
run_docs_sync() {
    local work_dir="${1:-${PROJECT_ROOT}}"

    if [[ ! -f "${work_dir}/docs/PROGRESS_REPORT.md" ]]; then
        log_info "[4] docs/PROGRESS_REPORT.md absent — skipping docs-sync"
        return 0
    fi

    log_step "[4] Docs sync (advisory)"

    local model="${SKELETON_MODEL:-claude-sonnet-4-6}"
    local log_file="${work_dir}/.skeleton-dev/logs/docs-sync.log"
    mkdir -p "$(dirname "${log_file}")"

    local prompt_file
    prompt_file="$(mktemp)"

    cat > "${prompt_file}" <<PROMPT
Documentation sync check: verify that the implementation matches the specifications in docs/.
Check for drift between docs/architecture.md, docs/dto_contracts.md, docs/orchestrator_spec.md
and actual code in app/.
Use skill: docs-sync.
MANDATORY: docs/ is read-only — never modify documentation.
If code drifts from specs, fix the code to match.
Report findings and commit any code fixes.
PROMPT

    invoke_agent "docs-sync" "merge-reviewer" "${work_dir}" \
        "${prompt_file}" "${model}" "${log_file}" || true
    rm -f "${prompt_file}"

    log_info "[4] Docs sync complete (advisory — see ${log_file})"
    return 0  # always non-fatal
}
