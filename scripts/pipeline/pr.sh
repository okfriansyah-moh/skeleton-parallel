#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/pipeline/pr.sh — Stage [6]: git push + gh pr create
# ─────────────────────────────────────────────────────────────────────────────
# Provides run_pr() which pushes the integration branch and creates a GitHub
# pull request via the gh CLI. Respects SKELETON_PR_MODE config:
#   per_run       — push + create PR on every successful run (default)
#   manual        — print instructions only; do not push or create PR
#   single_branch — push only; PR is managed externally
#
# Extracted from run_parallel.sh create_pr().
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/pipeline/pr.sh"
#   run_pr "${BRANCH}" "feat: implement tasks 1-3" "Optional PR body"
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_PR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_PR_DIR}/../lib/common.sh"

# ── run_pr ────────────────────────────────────────────────────────────────────
# Stage [6]: push branch to origin and create a GitHub pull request.
#
# Usage: run_pr <branch> <title> [body]
#
# Respects SKELETON_PR_MODE env/config:
#   per_run       — push + gh pr create (default)
#   manual        — print manual instructions; skip push
#   single_branch — push only; skip PR creation
#
# Returns: 0 on success (or when manual/degraded), 1 on hard push failure
run_pr() {
    local branch="${1:?branch required}"
    local title="${2:?title required}"
    local body="${3:-Automated integration — skeleton-parallel}"
    local pr_mode="${SKELETON_PR_MODE:-per_run}"

    log_step "[6] Publishing ${branch} (mode: ${pr_mode})"

    # ── Manual mode: print instructions only ────────────────────────────────
    if [[ "${pr_mode}" == "manual" ]]; then
        log_info "[6] PR mode=manual — skipping automated PR creation"
        log_info "  Push: git push origin ${branch}"
        log_info "  PR:   gh pr create --title '${title}' --base main --head ${branch}"
        return 0
    fi

    cd "${PROJECT_ROOT}"

    # ── Push branch ──────────────────────────────────────────────────────────
    log_info "[6] Pushing ${branch}..."
    if ! git push --set-upstream origin "${branch}" 2>&1; then
        log_error "[6] Push failed — proceed manually:"
        log_info "  git push origin ${branch}"
        log_info "  gh pr create --title '${title}' --base main --head ${branch}"
        return 1
    fi
    log_ok "[6] Branch pushed: ${branch}"

    # ── single_branch mode: push only ───────────────────────────────────────
    if [[ "${pr_mode}" == "single_branch" ]]; then
        log_info "[6] PR mode=single_branch — push complete; PR managed externally"
        return 0
    fi

    # ── per_run mode: create PR via gh CLI ──────────────────────────────────
    if ! command -v gh &>/dev/null; then
        log_warn "[6] GitHub CLI (gh) not found — PR not created"
        log_info "  Install: https://cli.github.com"
        log_info "  Manual:  gh pr create --title '${title}' --base main --head ${branch}"
        return 0
    fi

    if ! gh auth status &>/dev/null 2>&1; then
        log_warn "[6] GitHub CLI not authenticated — run: gh auth login"
        log_info "  Manual:  gh pr create --title '${title}' --base main --head ${branch}"
        return 0
    fi

    log_info "[6] Creating pull request..."
    local pr_url
    if pr_url=$(gh pr create \
            --title "${title}" \
            --base main \
            --head "${branch}" \
            --body "${body}" \
            2>&1); then
        log_ok "[6] Pull request created: ${pr_url}"
        return 0
    else
        log_warn "[6] PR creation failed: ${pr_url}"
        log_info "  Manual:  gh pr create --title '${title}' --base main --head ${branch}"
        return 0  # non-fatal: push succeeded; PR can be created manually
    fi
}
