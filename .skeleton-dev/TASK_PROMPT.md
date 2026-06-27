# Task 1 — Repository Scaffold + `lib/` Extraction

**Status:** completed
**Complexity:** Low
**Depends on:** none

## Goal

Create the new directory skeleton and extract cross-cutting utilities from `run_parallel.sh` into focused `scripts/lib/` modules that every pipeline script will source.

## Files to create

- `scripts/lib/common.sh`
- `scripts/lib/checkpoint.sh`
- `checkpoint_create`
- `checkpoint_rollback`
- `scripts/lib/policy.sh`
- `docs/PLAN.md`

## Validation

- `bash -n scripts/lib/common.sh`: zero syntax errors
- `bash -n scripts/lib/checkpoint.sh`: zero syntax errors
- `bash -n scripts/lib/policy.sh`: zero syntax errors
- `source scripts/lib/common.sh && log_info "test"`: outputs `[INFO] test`
- All `.gitkeep` directories present: `find . -name .gitkeep | wc -l` ≥ 14

---

## Full task section (from docs/PLAN.md)

### Task 1 — Repository Scaffold + `lib/` Extraction

**Goal:** Create the new directory skeleton and extract cross-cutting utilities from `run_parallel.sh` into focused `scripts/lib/` modules that every pipeline script will source.

**Files to create:**

- `scripts/lib/common.sh` — logging (`log_info`, `log_ok`, `log_warn`, `log_error`, `log_step`, `die`), color constants, bash 4+ check, `SKELETON_ROOT` / `PROJECT_ROOT` resolution helpers
  - Migrate all logging/color helpers verbatim from current `bin/skeleton` and `run_parallel.sh`
  - Must be idempotent when sourced multiple times (guard `COMMON_LOADED`)
- `scripts/lib/checkpoint.sh` — `checkpoint_create(task_n)`, `checkpoint_rollback(task_n)`, `checkpoint_list()`
  - `checkpoint_create`: `git tag checkpoint-task-N-pre -m "pre Task N"`
  - `checkpoint_rollback`: `git reset --hard checkpoint-task-N-pre`
  - Never calls `git push` — local tags only
- `scripts/lib/policy.sh` — `check_protected_paths(files_list)`, `PROTECTED_PATHS` array (`contracts/`, `database/`, `docs/`)
  - Additive-only check for `contracts/`: new files OK, existing file modification = error
  - `docs/PLAN.md` exception: `<!-- ✅ Task N completed -->` marker writes are allowed
- Directory stubs (`.gitkeep`): `framework/agents/`, `framework/skills/`, `router/`, `drivers/router_http/`, `drivers/cli/`, `drivers/cursor-sdk/`, `templates/hooks/go/`, `templates/hooks/python/`, `templates/hooks/typescript/`, `templates/hooks/fullstack/`, `templates/docs/`, `templates/ai/`, `scripts/knowledge/`, `scripts/plan/`, `scripts/pipeline/`

**Validation:**

- `bash -n scripts/lib/common.sh`: zero syntax errors
- `bash -n scripts/lib/checkpoint.sh`: zero syntax errors
- `bash -n scripts/lib/policy.sh`: zero syntax errors
- `source scripts/lib/common.sh && log_info "test"`: outputs `[INFO] test`
- All `.gitkeep` directories present: `find . -name .gitkeep | wc -l` ≥ 14

**Prompt context needed:** Spec §18.1 (target layout), §8.7 (Stage 0 agent chain), §17 (protected paths policy)

<!-- ✅ Task 1 completed -->

---


