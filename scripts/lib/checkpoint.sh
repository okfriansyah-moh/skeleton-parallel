#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/lib/checkpoint.sh — Git tag checkpoints for task rollback
# ─────────────────────────────────────────────────────────────────────────────
# Provides checkpoint_create, checkpoint_rollback, and checkpoint_list
# to tag the git state before each task and restore it on retry exhaustion.
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/lib/checkpoint.sh"
#   checkpoint_create 1
#   checkpoint_rollback 1
#   checkpoint_list
# ─────────────────────────────────────────────────────────────────────────────

# Guard: idempotent sourcing
[[ -n "${CHECKPOINT_LOADED:-}" ]] && return 0
CHECKPOINT_LOADED=1

# Depend on common utilities
_CHECKPOINT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_CHECKPOINT_LIB_DIR}/common.sh"

# ── checkpoint_create ─────────────────────────────────────────────────────────
# Create a local git tag capturing the state before task N begins.
# Tag name: checkpoint-task-N-pre
#
# Usage: checkpoint_create <task_n>
checkpoint_create() {
    local task_n="${1:?task_n required}"
    local tag="checkpoint-task-${task_n}-pre"

    if git rev-parse --verify "refs/tags/${tag}" &>/dev/null; then
        log_warn "Checkpoint tag '${tag}' already exists — overwriting"
        git tag -d "${tag}" &>/dev/null
    fi

    git tag "${tag}" -m "pre Task ${task_n}"
    log_ok "Checkpoint created: ${tag}"
}

# ── checkpoint_rollback ───────────────────────────────────────────────────────
# Hard-reset the working tree to the pre-task checkpoint for task N.
# WARNING: discards all uncommitted and committed changes since the tag.
#
# Usage: checkpoint_rollback <task_n>
checkpoint_rollback() {
    local task_n="${1:?task_n required}"
    local tag="checkpoint-task-${task_n}-pre"

    if ! git rev-parse --verify "refs/tags/${tag}" &>/dev/null; then
        die "Checkpoint tag '${tag}' not found — cannot rollback"
    fi

    log_warn "Rolling back to checkpoint: ${tag}"
    git reset --hard "${tag}"
    log_ok "Rollback to '${tag}' complete"
}

# ── checkpoint_list ───────────────────────────────────────────────────────────
# List all local checkpoint tags, sorted by task number.
#
# Usage: checkpoint_list
checkpoint_list() {
    local tags
    tags="$(git tag --list 'checkpoint-task-*-pre' | sort -t- -k3 -n)"
    if [[ -z "${tags}" ]]; then
        log_info "No checkpoint tags found"
    else
        echo "${tags}"
    fi
}
