# PLAN.md — Agentic Loop CLI (skeleton-parallel v1.0) Implementation Plan

> **Version:** 1.0
> **Date:** 2026-06-27
> **Author:** skeleton-parallel design session
> **Status:** Ready for Implementation
> **Source of Truth:** `docs/specs/2026-06-27-agentic-loop-cli-design.md`

---

## 1. Goal

Evolve skeleton-parallel from a **phase-based parallel development script** (`run_parallel.sh` + `config/phases.yaml`) into a **provider-agnostic agentic loop CLI** (`skeleton run`) that executes tasks from `docs/PLAN.md`, runs nested agentic loops (turn → task → plan → optional goal), and preserves the full six-stage integration pipeline. The system separates knowledge (ARES `.ai/`), routing (skeleton-wrapped 9router), and execution (three pluggable drivers: `router_http`, `cli_subscription`, `sdk_cursor`) into clean, independently replaceable planes.

**Why:** Teams cannot switch LLM providers without re-engineering the orchestration. The agentic loop CLI removes that coupling and makes provider choice a config-file decision.

---

## 2. Architecture Overview

```
Human / CI
    │
    ▼
skeleton run [--plan] [tasks] [--driver] [--parallel|--sequential]
    │
    ├─► Stage −1: .ai/ sync → composed artifacts (CLAUDE.md, .github/, etc.)
    │             detect_legacy → ars import → ars validate → compose-if-stale
    ├─► router check/start (if driver requires 9router)
    ├─► plan_parser: index tasks, deps, file-ownership, completion markers
    ├─► Stage 0: for each task/track → ExecutionDriver → 7-step agent chain
    │             T1 hook after each task
    ├─► [2] union merge (if ≥2 parallel tracks)
    ├─► [3] post-merge review (merge-reviewer)
    ├─► [4] docs-sync → PROGRESS_REPORT.md (advisory)
    ├─► [5a] quality-gates.sh (T3 full suite)
    ├─► [5b] acceptance-gates.sh → feedback router
    ├─► [5c] test-builder sufficiency
    └─► [6] git push + gh pr create

Five planes:
  PLANE 1 KNOWLEDGE  .ai/manifest.yaml · instructions · agents · skills
  PLANE 2 ROUTING    skeleton-wrapped 9router (OAuth, combos, fallback)
  PLANE 3 EXECUTION  router_http | cli_subscription | sdk_cursor
  PLANE 4 ORCH       skeleton CLI · stages · agentic loops
  PLANE 5 PROJECT    PLAN.md · hooks · PROGRESS_REPORT.md
```

**Key architectural decisions (non-negotiable):**

| Decision                                   | Rationale                                                                           |
| ------------------------------------------ | ----------------------------------------------------------------------------------- |
| PLAN.md is the work contract               | Replaces `config/phases.yaml` as primary task authority                             |
| `.ai/manifest.yaml` = identity             | Provider, domain, skills, plan path — not in skeleton.yaml                          |
| `config/skeleton.yaml` = runtime only      | Driver, router, retries, acceptance — no identity fields                            |
| Three drivers from v1.0                    | `router_http`, `cli_subscription` (copilot/claude/codex), `sdk_cursor`              |
| Cursor SDK ≠ 9router                       | Cursor SDK talks to Cursor agent runtime; 9router routes subscription traffic       |
| Compose-if-stale only                      | Stage −1 imports only when combination policy triggers; not on every `skeleton run` |
| Stage 0 agent chain unchanged              | task-runner → dto-guardian → integration → security-auditor → test-builder          |
| `.skeleton-dev/` replaces `.parallel-dev/` | Shim reads old path for one release                                                 |
| Hybrid is default mode                     | Batch by dep graph; parallel within batch; serial across batches                    |

---

## 3. Tech Stack

**Orchestration:**

```
bash 4+                    Primary scripting language for all pipeline scripts
Python 3.10+               plan_parser.py, plan_validate.py, detect_legacy.py
Node.js ≥ 22.13            sdk_cursor driver only
```

**Execution drivers:**

```
@cursor/sdk                Cursor agent runtime (Driver C — pinned version)
```

**External tools (not installed by skeleton):**

```
ars (ARES CLI)             https://github.com/okfriansyah-moh/ares
9router                    https://github.com/decolua/9router (wrapped)
copilot / claude / codex   Vendor CLIs (Driver B — user must install)
gh                         GitHub CLI — Stage [6] PR creation
git                        Git operations throughout
```

**Configuration:**

```
YAML                       .ai/manifest.yaml, config/skeleton.yaml
JSON                       .skeleton-dev/plan-index.json, run-status.json
JSONL                      .skeleton-dev/events.jsonl
```

---

## 4. Project Structure

```
skeleton-parallel/
  bin/skeleton                      # Single CLI entry point (refactored)
  framework/
    agents/                         # Framework pipeline agents (task-runner, etc.)
    skills/                         # Framework skills (all 28)
  router/
    9router-pin.json                # Locked npm/docker version
    docker-compose.yml              # Optional dev stack
    wrap.sh                         # start | stop | health
    oauth-guide.md                  # Copied to project docs on integrate
  drivers/
    registry.yaml                   # Driver registry (name → entrypoint)
    router_http/
      run.sh                        # Driver A: harness → 9router /v1
    cli/
      copilot.sh                    # Driver B1: Copilot CLI adapter
      claude.sh                     # Driver B2: Claude Code CLI adapter
      codex.sh                      # Driver B3: Codex CLI adapter
    cursor-sdk/
      package.json                  # Pinned @cursor/sdk
      run.mjs                       # Driver C: @cursor/sdk wrapper
  templates/
    hooks/
      go/                           # quality-gates.sh, acceptance-gates.sh
      python/
      typescript/
      fullstack/
    docs/
      PLAN.md.stub                  # Stub for new projects
    ai/
      manifest.yaml.template        # .ai/manifest.yaml template
  scripts/
    skeleton-run.sh                 # Main run orchestrator (new)
    run_parallel.sh                 # DEPRECATED shim → exec skeleton run "$@"
    knowledge/
      sync.sh                       # Stage −1 orchestration
      detect_legacy.py              # Detect .github/, CLAUDE.md, etc.
      import.sh                     # ars import wrapper
      compose.sh                    # ars compose wrapper + stamp guard
    plan/
      plan_parser.py                # Index tasks, deps, file-ownership
      plan_validate.py              # Schema validation
    pipeline/
      agent_pipeline.sh             # 7-step per-task agent chain
      modes.sh                      # Hybrid/parallel/sequential scheduling
      task_executor.sh              # L2 task loop: invoke → validate → fix
      integration.sh                # [2] union merge + [3] post-merge
      global_validation.sh          # [5a] quality-gates T3
      acceptance.sh                 # [5b] acceptance + feedback router
      pr.sh                         # [6] git push + gh pr create
    lib/
      common.sh                     # Logging, colors, utilities
      checkpoint.sh                 # Git tag checkpoint/rollback
      state.sh                      # .skeleton-dev/ read/write helpers
      router.sh                     # router_check, auto_start, inject_env
      agent.sh                      # Agent invocation helpers
      hooks.sh                      # Hook discovery + invocation
      policy.sh                     # Protected path enforcement
      config.sh                     # Load/validate manifest + skeleton.yaml
  config/
    phases.yaml                     # DEPRECATED — adapter shim reads this
    skeleton.yaml.template          # Runtime config template
  docs/
    specs/
      2026-06-27-agentic-loop-cli-design.md
    PLAN.md                         # This file
```

---

## 5. Implementation Tasks

### Dependency Graph

```
Task 1 (Scaffold + lib/ extraction) ─────────────────────────────────────────┐
    │                                                                           │
    ▼                                                                           │
Task 2 (Pipeline script extraction) ─────────────┐                            │
    │                                              │                            │
    ▼                                              │                            │
Task 3 (bin/skeleton subcommand dispatcher) ─────┤                            │
    │                                              │                            │
    ▼                                              ▼                            │
Task 4 (Config split: manifest + skeleton.yaml)  Task 5 (PLAN.md parser)      │
    │                                              │                            │
    └──────────────────┬────────────────────────── ┘                           │
                       ▼                                                        │
               Task 6 (.skeleton-dev/ state + observability)                   │
                       │                                                        │
                       ├─────────────────────────────────────────────────────── ┘
                       │
                       ▼
               Task 7 (Knowledge plane: Stage −1 / ARES)
                       │
                       ▼
               Task 8 (Router wrapper: skeleton-wrapped 9router)
                       │
                       ├──────────────────────────────────────────────┐
                       ▼                                               ▼
               Task 9 (Driver: router_http)           Task 10 (Driver: cli_subscription)
                       │                                               │
                       ▼                                               ▼
               Task 11 (Driver: sdk_cursor)           Task 12 (Stage 0: per-task executor)
                       │                                               │
                       └────────────────────┬──────────────────────── ┘
                                            ▼
                                    Task 13 (skeleton run orchestrator)
                                            │
                                            ▼
                                    Task 14 (Lifecycle: init, integrate, doctor, autoskills)
                                            │
                                            ▼
                                    Task 15 (Hook templates + T1/T3 infrastructure)
                                            │
                                            ▼
                                    Task 16 (acceptance.sh + feedback router)
                                            │
                                            ▼
                                    Task 17 (Migration shim + final integration test + docs)
```

---

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

### Task 2 — Pipeline Script Extraction

**Goal:** Decompose the monolithic `run_parallel.sh` into focused pipeline modules under `scripts/pipeline/` and `scripts/lib/`, keeping all existing behavior intact.

**Files to create:**

- `scripts/lib/agent.sh` — `invoke_agent(stage, agent, work_dir, prompt_file, model, log_file)`, `build_skills_csv()`, workspace constraint injection
  - Extract Copilot invocation pattern from `run_parallel.sh` verbatim
  - Skills CSV assembled from `FRAMEWORK_SKILLS` + `manifest.skills.always` + per-task overrides
- `scripts/lib/hooks.sh` — `discover_hooks(project_root)`, `run_hook(hook_name, exit_on_fail)`, hook path resolution from `config/skeleton.yaml`
- `scripts/pipeline/integration.sh` — `run_union_merge()`, `run_post_merge_review()`
  - Extract from `run_parallel.sh` merge + post-merge-review sections
  - Max 5 retries each; rollback on exceed
- `scripts/pipeline/global_validation.sh` — `run_5a(project_root)`, `run_refactor(work_dir)`
  - Calls `scripts/hooks/quality-gates.sh`; refactor up to 5 cycles; blocks PR on failure
- `scripts/pipeline/pr.sh` — `run_pr(branch, title, body)` — `git push` + `gh pr create`
  - `integration.pr_mode` from config: `per_run` | `manual` | `single_branch`

**Validation:**

- `bash -n scripts/lib/agent.sh`: zero syntax errors
- `bash -n scripts/pipeline/integration.sh`: zero syntax errors
- `bash -n scripts/pipeline/global_validation.sh`: zero syntax errors
- `bash -n scripts/pipeline/pr.sh`: zero syntax errors
- Source all lib files from a test script without error: `source scripts/lib/common.sh && source scripts/lib/agent.sh && echo OK`

**Prompt context needed:** Spec §8.7 (Stage 0 chain), §8.8 (Stages [2]-[6] detail), §19 (ExecutionDriver interface)

---

### Task 3 — `bin/skeleton` Subcommand Dispatcher Refactor

**Goal:** Refactor `bin/skeleton` from a monolith into a thin dispatcher that delegates each subcommand to its dedicated script, and add all new v1.0 subcommands as stubs.

**Files to modify / create:**

- `bin/skeleton` (modify) — replace the large function body with a subcommand router:

  ```bash
  case "$1" in
    run)       exec "${SKELETON_ROOT}/scripts/skeleton-run.sh" "${@:2}" ;;
    router)    exec "${SKELETON_ROOT}/router/wrap.sh" "${@:2}" ;;
    plan)      exec "${SKELETON_ROOT}/scripts/plan/plan_parser.py" "${@:2}" ;;
    init|upgrade|integrate|doctor|autoskills|sync|add|list|context|
    knowledge|hooks|status|cleanup|gates|merge|goal|version|help)
                 source "${SKELETON_ROOT}/scripts/lib/common.sh"
                 run_subcommand "$@" ;;
    *) die "Unknown subcommand: $1. Run 'skeleton help'" ;;
  esac
  ```

  - Keep all existing `init`, `upgrade`, `doctor`, `add`, `list`, `sync`, `version`, `help` implementations as `run_subcommand` delegations
  - New stubs: `status`, `cleanup`, `gates`, `merge`, `goal`, `integrate`, `autoskills`, `context`, `knowledge`, `hooks`
  - `--dir PATH` global flag parsed before subcommand dispatch; sets `PROJECT_ROOT`
  - `--no-interactive` flag: CI mode; fail if PLAN ambiguous

- `scripts/run_parallel.sh` (modify) — convert to deprecation shim: print `WARN: use 'skeleton run' instead` to stderr, then `exec skeleton run "$@"` with mode flag mapping (`--mode=1` → `--parallel`, `--mode=2` → `--sequential`)

**Validation:**

- `bash -n bin/skeleton`: zero syntax errors
- `./bin/skeleton --help`: prints usage with all new subcommands listed
- `./bin/skeleton version`: prints version string
- `./scripts/run_parallel.sh start --mode=1 1 2` (dry path): prints deprecation warning and shows translated `skeleton run --parallel 1 2` command

**Prompt context needed:** Spec §14 (CLI reference), §21 (migration from run_parallel.sh), §25 (lifecycle commands)

---

### Task 4 — Configuration Split: `.ai/manifest.yaml` + `config/skeleton.yaml`

**Goal:** Implement the canonical identity/runtime config split, with a loader/validator that enforces the rules and a template for new projects.

**Files to create:**

- `config/skeleton.yaml.template` — full runtime config template per spec §13.2; every key documented inline; no identity fields (`name`, `domain`, `provider`, `plan`, `skills.always`)
- `templates/ai/manifest.yaml.template` — identity config template per spec §13.1; all required keys with inline docs; `import_policy: merge_on_stale` default
- `scripts/lib/config.sh` — `load_config(project_root)`, `validate_config()`, `get_driver()`, `get_manifest_provider()`
  - Load both files; manifest wins on any identity conflict
  - Validate `execution.driver` is one of `router_http | cli_subscription | sdk_cursor`
  - Guard: `driver=cli_subscription` + `cli.provider=cursor` → `die` with fix hint
  - Guard: `driver=sdk_cursor` → check Node.js ≥ 22.13 (defer check to Task 11)
  - Export env vars: `SKELETON_DRIVER`, `SKELETON_PROVIDER`, `SKELETON_PLAN`, `SKELETON_SKILLS_ALWAYS`

**Validation:**

- `bash -n scripts/lib/config.sh`: zero syntax errors
- Valid config loads without error: `source scripts/lib/config.sh && load_config . && echo "$SKELETON_DRIVER"`
- Invalid driver `cli_subscription` + `cursor` → exits non-zero with message containing `doctor`
- Missing `execution.driver` key → exits non-zero with descriptive message

**Prompt context needed:** Spec §5.2 (single source of truth split), §13.1 (manifest.yaml schema), §13.2 (skeleton.yaml schema), §7.5 (driver selection rules)

---

### Task 5 — PLAN.md Parser

**Goal:** Build the Python PLAN.md parser that produces a `.skeleton-dev/plan-index.json` file consumed by all shell orchestration scripts, with O(1) section loading for large files.

**Files to create:**

- `scripts/plan/plan_parser.py` — line-offset indexed parser:
  - `index_tasks(plan_path)` → `{task_n: {line_start, line_end, name, goal, files, depends_on, validation, complexity, status}}`
  - `parse_dep_graph(tasks)` → dependency edges from §5 ASCII graph or §6 table `Depends On` column
  - `extract_file_ownership(task)` → list of `Files to create:` paths per task
  - `check_parallel_safety(task_a, task_b)` → false if overlapping file ownership
  - `is_completed(task)` → detects `<!-- ✅ Task N completed -->` marker
  - `mark_completed(plan_path, task_n)` → writes marker in-place (only mutation allowed)
  - Export: `.skeleton-dev/plan-index.json` (see §8.10 for schema)
  - Performance: never load full file into memory; use `mmap` / line offset seek
- `scripts/plan/plan_validate.py` — `validate_plan(index_path)`:
  - All `Depends On` tasks exist in index
  - No circular deps in dep graph
  - All tasks have non-empty `Validation` section
  - Report: list of errors; exit non-zero if any

**Validation:**

- `python3 -m py_compile scripts/plan/plan_parser.py`: zero errors
- `python3 -m py_compile scripts/plan/plan_validate.py`: zero errors
- `python3 scripts/plan/plan_parser.py docs/PLAN.md --export .skeleton-dev/plan-index.json`: produces valid JSON with all 17 tasks indexed
- `python3 scripts/plan/plan_validate.py .skeleton-dev/plan-index.json`: exits 0 on valid plan
- Large-file test: parser handles 100k-line file without loading it whole (verify via `resource.getrusage`)

**Prompt context needed:** Spec §10.3 (task section schema), §10.4 (PLAN parser requirements), §8.10 (deep knowledge plan-index schema)

---

### Task 6 — `.skeleton-dev/` State + Observability

**Goal:** Implement all state management and observability primitives that every pipeline stage reads and writes.

**Files to create:**

- `scripts/lib/state.sh` — `.skeleton-dev/` init, read/write helpers:
  - `state_init(project_root)` — create `.skeleton-dev/` if absent; shim: copy `.parallel-dev/state.json` if `.skeleton-dev/state.json` absent (one-release migration)
  - `run_status_write(task_n, stage, status)` — append/update row in `run-status.json`; rows: `task_N`, `post-merge-review`, `docs-sync`, `global-validation-5a`, `global-validation-5b`, `global-validation-5c`, `remediation`, `pr-create`
  - `run_status_read(key)` — read single row from `run-status.json`
  - `events_append(type, payload_json)` — append JSONL event per spec §16.3 schema
  - `compose_stamp_write(ai_dir)` — write `sha256` of `.ai/**` to `.skeleton-dev/compose.stamp`
  - `compose_stamp_valid(ai_dir)` — compare current hash vs stamp; returns 0 if stale
- `bin/skeleton status` (implement stub from Task 3) — reads `run-status.json`, prints table of task + pipeline substates
- `bin/skeleton cleanup` (implement stub from Task 3) — removes worktrees, branches, clears `.skeleton-dev/` state (prompts confirmation unless `--force`)

**Validation:**

- `bash -n scripts/lib/state.sh`: zero syntax errors
- `source scripts/lib/state.sh && state_init . && ls .skeleton-dev/`: directory exists
- `run_status_write 1 task_runner completed` → `.skeleton-dev/run-status.json` contains task 1 row
- `events_append task_start '{"task":1}'` → `.skeleton-dev/events.jsonl` contains valid JSONL line
- `skeleton status` on initialized state: prints readable table; exits 0

**Prompt context needed:** Spec §16 (state, logs, observability), §16.2 (run-status.json rows), §16.3 (events.jsonl schema)

---

### Task 7 — Knowledge Plane: Stage −1 (ARES Integration)

**Goal:** Implement the full Stage −1 knowledge sync algorithm — import combination policy, compose-if-stale, and legacy fallback — that runs automatically before every `skeleton run`.

**Files to create:**

- `scripts/knowledge/detect_legacy.py` — scan project root for legacy provider files:
  - `.github/copilot-instructions.md` / `.github/agents/` / `.github/skills/` → `github`
  - `CLAUDE.md` / `.claude/` → `claude`
  - `AGENTS.md` → `codex`
  - `.cursor/rules/` → `cursor`
  - `.antigravity/` → `antigravity`
  - Output: JSON list of `{source, type, files}` — or empty list if nothing detected
- `scripts/knowledge/import.sh` — `ars_import(source_type)`:
  - Calls `ars import <source_type> --merge`; exits with actionable error if `ars` not installed
  - Never overwrites existing `.ai/` files unless `--force` passed
- `scripts/knowledge/compose.sh` — `ars_compose(provider, ai_dir, stamp_path)`:
  - Calls `ars compose --target <provider>`; writes compose stamp on success
  - Legacy fallback: if compose fails but stamp exists → log WARN + set `SKELETON_COMPOSED_DEGRADED=true`
- `scripts/knowledge/sync.sh` — Stage −1 algorithm per spec §5.3.4:
  1. Resolve `PROJECT_ROOT`
  2. Load `.ai/manifest.yaml` (scaffold if `skeleton integrate` mode)
  3. Import if combination policy triggers
  4. `ars validate` — abort with doctor report on failure
  5. Compose if stale (stamp comparison)
  6. Legacy fallback if compose fails
  7. Write compose stamp

**Validation:**

- `bash -n scripts/knowledge/sync.sh`: zero syntax errors
- `python3 -m py_compile scripts/knowledge/detect_legacy.py`: zero errors
- `python3 scripts/knowledge/detect_legacy.py .` on this repo: detects `github` source (`.github/` exists)
- `bash scripts/knowledge/sync.sh --dry-run`: prints planned steps without writing
- `ars` not installed: `sync.sh` exits with message `ars CLI not found — run skeleton integrate`

**Prompt context needed:** Spec §5 (knowledge plane), §5.3 (Stage −1 algorithm), §5.3.1 (import triggers), §5.3.3 (compose triggers)

---

### Task 8 — Router Wrapper (skeleton-wrapped 9router)

**Goal:** Implement the 9router daemon management layer so `skeleton` can install, start, stop, and health-check 9router, and inject env vars into CLI drivers when `router.inject: true`.

**Files to create:**

- `router/9router-pin.json` — `{"version": "latest", "npm": "@9router/server", "docker": "9router/server:latest"}` — pinned version; updated only by skeleton maintainers
- `router/wrap.sh` — `router_install()`, `router_start()`, `router_stop()`, `router_status()`, `router_health()`:
  - `router_install`: npm global install or docker pull per pin file
  - `router_start`: start daemon on port 20128; write PID to `.skeleton-dev/router.pid`
  - `router_stop`: kill PID from `.skeleton-dev/router.pid`
  - `router_health`: HTTP GET `http://localhost:20128/health` → exit 0/1
- `scripts/lib/router.sh` — `router_check_required()`, `router_auto_start_if_needed()`, `inject_cli_env(cli_provider)`:
  - `router_check_required()`: reads `execution.driver` + `router.enabled`; returns `require|optional|none`
  - `router_auto_start_if_needed()`: if required + `router.auto_start: true` + not running → `router_start`
  - `inject_cli_env(copilot|claude|codex)`: sets provider-specific env vars per `router/inject-env.sh` (generated at router install time)
- `router/oauth-guide.md` — step-by-step OAuth connection instructions for Copilot/Claude/Codex

**Validation:**

- `bash -n router/wrap.sh`: zero syntax errors
- `bash -n scripts/lib/router.sh`: zero syntax errors
- `skeleton router status`: prints running/stopped state (even if daemon not installed)
- `skeleton router check`: exits 0 if daemon up, 1 if down — no crash on missing daemon
- `router.enabled: false` in config + `driver: cli_subscription` → `router_check_required` returns `none`

**Prompt context needed:** Spec §6 (routing plane), §6.3 (router CLI), §6.4 (when 9router required), §6.5 (CLI env injection), §8.12 (driver selection rules)

---

### Task 9 — Execution Driver: `router_http` (Model 1)

**Goal:** Implement the HTTP harness driver that assembles prompts and calls 9router's OpenAI-compatible `/v1/chat/completions` endpoint, including quota/429 handling and streaming log output.

**Files to create:**

- `drivers/router_http/run.sh` — implements `run_driver()` contract (spec §19.1):
  - Args: `driver, stage, work_dir, prompt_file, model, log_file`
  - Prompt assembly (see §8.2 for variable substitution): system prompt = `SKELETON_ROOT/framework/` instructions + framework skills + project `.ai/skills/` + `TASK_PROMPT.md` + stage template
  - Calls 9router `/v1/chat/completions` via `curl` with JSON body; streams response to `log_file`
  - Exit codes: 0 = success, 1 = agent error, 2 = quota/429, 3 = fatal
  - On exit code 2: caller (`task_executor.sh`) applies `quota_retry` policy
  - Stage template substitution: `{{TASK_NUMBER}}`, `{{PLAN_PATH}}`, `{{SKILLS_CSV}}`, `{{WORKSPACE_CONSTRAINT}}`, `{{STAGE_NAME}}`
- `drivers/registry.yaml` — maps `driver_name → entrypoint`:
  ```yaml
  router_http: drivers/router_http/run.sh
  cli_copilot: drivers/cli/copilot.sh
  cli_claude: drivers/cli/claude.sh
  cli_codex: drivers/cli/codex.sh
  sdk_cursor: drivers/cursor-sdk/run.mjs
  ```

**Validation:**

- `bash -n drivers/router_http/run.sh`: zero syntax errors
- Prompt assembly unit test: mock `TASK_PROMPT.md` + skills dir → verify system prompt contains all four components
- Exit code 2 on 429: `curl` mock returning HTTP 429 → driver exits 2
- `drivers/registry.yaml`: valid YAML; all five entries reference existing paths (`.gitkeep` acceptable for unimplemented drivers)

**Prompt context needed:** Spec §7.2 (Driver A description), §19 (ExecutionDriver interface), §7.7 (skills resolution), §8.12 (driver selection rules), §8.13 (skills resolution algorithm — deep knowledge)

---

### Task 10 — Execution Driver: `cli_subscription` (copilot / claude / codex)

**Goal:** Implement the three vendor CLI driver adapters for the `cli_subscription` execution model, each running non-interactively with optional 9router env injection.

**Files to create:**

- `drivers/cli/copilot.sh` — Copilot CLI adapter:
  - Non-interactive invocation pattern (exact match current `run_parallel.sh` copilot call):
    ```bash
    copilot \
      -p "${STAGE_PROMPT}" \
      --agent="${AGENT_NAME}" \
      --model="${MODEL_OR_COMBO_ALIAS}" \
      --no-ask-user \
      --allow-all-tools \
      --autopilot
    ```
  - Checks `copilot` binary on `PATH`; dies with install hint if absent
  - Exit code mapping: non-zero Copilot exit → exit 1; quota error string in stderr → exit 2
- `drivers/cli/claude.sh` — Claude Code CLI adapter:
  - Non-interactive flags per Claude Code docs (`--no-interactive` or equivalent)
  - Same exit code convention as copilot.sh
- `drivers/cli/codex.sh` — Codex CLI adapter:
  - OpenAI-compatible non-interactive flags
  - Same exit code convention
- Guard (in `scripts/lib/config.sh` from Task 4): `execution.driver=cli_subscription` + `execution.cli.provider=cursor` → `die "Cursor requires driver: sdk_cursor — see skeleton doctor"`

**Validation:**

- `bash -n drivers/cli/copilot.sh`: zero syntax errors
- `bash -n drivers/cli/claude.sh`: zero syntax errors
- `bash -n drivers/cli/codex.sh`: zero syntax errors
- `copilot` not on PATH → driver exits with message containing `brew install` or install URL
- Config guard: `cli.provider: cursor` → `load_config` exits non-zero with fix hint
- All three drivers use identical exit code convention (0/1/2/3)

**Prompt context needed:** Spec §7.3 (Driver B), §7.5 (driver selection rules), §6.5 (CLI env injection)

---

### Task 11 — Execution Driver: `sdk_cursor` (Model 2 — Cursor)

**Goal:** Implement the Node.js Cursor SDK driver wrapper that invokes `@cursor/sdk` Agent for local runtime, with rate-limit error classification and streaming log output.

**Files to create:**

- `drivers/cursor-sdk/package.json` — `{"name": "skeleton-cursor-driver", "type": "module", "dependencies": {"@cursor/sdk": "^<pinned-version>"}}` — version pinned in `router/9router-pin.json` companion field
- `drivers/cursor-sdk/run.mjs` — `Agent.create()` wrapper:

  ```javascript
  import { Agent } from "@cursor/sdk";
  const agent = await Agent.create({
    apiKey: process.env.CURSOR_API_KEY,
    model: { id: process.env.CURSOR_MODEL },
    local: { cwd: process.env.PROJECT_ROOT },
  });
  const run = await agent.send(stagePrompt);
  for await (const event of run.stream) {
    writeToLog(event);
  }
  const result = await run.result;
  process.exit(result.ok ? 0 : 1);
  ```

  - Rate-limit errors → exit 2 (quota retry class); other errors → exit 1
  - `CURSOR_API_KEY` read from env; never log value; die if absent
  - `PROJECT_ROOT` workspace confinement enforced via `local.cwd`

- Node.js version check (in `scripts/lib/config.sh`) — `driver: sdk_cursor` → verify `node --version` ≥ 22.13; die with upgrade hint if below

**Validation:**

- `node --check drivers/cursor-sdk/run.mjs`: zero syntax errors
- `CURSOR_API_KEY` absent → driver exits 1 with message `CURSOR_API_KEY not set`
- Node.js < 22.13 + `driver: sdk_cursor` → `load_config` exits non-zero with version hint
- Rate-limit mock (inject string `"rate_limit"` to stderr) → driver exits 2
- `cd drivers/cursor-sdk && npm install`: installs without error (requires Node.js ≥ 22.13)

**Prompt context needed:** Spec §7.4 (Driver C), §7.5 (driver selection rules), §19 (ExecutionDriver interface), §20.2 (quota exhaustion Cursor SDK)

---

### Task 12 — Stage 0: Per-Task Executor + Agentic Loop L2

<!-- ✅ Task 12 completed -->

**Goal:** Implement the per-task execution loop (L2) that wraps the 7-step agent chain, generates `TASK_PROMPT.md` from the plan index, manages git checkpoints, and writes PLAN completion markers.

**Files to create:**

- `scripts/pipeline/task_executor.sh` — L2 task loop:
  - `execute_task(task_n, driver, plan_index, work_dir)`:
    1. Generate `.skeleton-dev/TASK_PROMPT.md` from plan index (task section + referenced §8 subsections + `.ai/prompts/implement-and-review-task.md` template)
    2. `checkpoint_create task_n`
    3. For each step in 7-step chain (see §8.3): call `run_driver()` via `scripts/lib/agent.sh`
    4. Run T1 hook (`scripts/hooks/quality-gates.sh`)
    5. On success: `plan_parser.py mark_completed task_n`; git commit `feat(task-N): implement <name>`
    6. On step failure: retry up to `retries.<agent_name>` limit; on exceed: `checkpoint_rollback task_n`; exit 1
  - `generate_task_prompt(task_n, plan_index)` — load only the task's section + referenced §8 keys; never load full PLAN file
- `scripts/pipeline/modes.sh` — scheduling modes:
  - `schedule_hybrid(tasks, plan_index)` → batches by dep graph + file-ownership safety; returns batch list
  - `schedule_parallel(tasks)` → one worktree per task (subject to `max_parallel_agents`)
  - `schedule_sequential(tasks)` → strict dependency order, single branch

**Validation:**

- `bash -n scripts/pipeline/task_executor.sh`: zero syntax errors
- `bash -n scripts/pipeline/modes.sh`: zero syntax errors
- `generate_task_prompt 1 .skeleton-dev/plan-index.json` → creates `.skeleton-dev/TASK_PROMPT.md` containing task 1 content
- Checkpoint tag created before agent chain: `git tag | grep checkpoint-task-1-pre`
- Completion marker written on success: `grep '<!-- ✅ Task 1 completed -->' docs/PLAN.md`
- Retry exceed → rollback: mock agent returning exit 1 five times → `git log` shows reset to checkpoint

**Prompt context needed:** Spec §8.7 (Stage 0 agent chain), §9 (agentic loop layers), §10.3 (task section schema), §11 (testing T1), §20.3 (checkpoint rollback)

---

### Task 13 — `skeleton run` Main Orchestrator

<!-- ✅ Task 13 completed -->

**Goal:** Implement `scripts/skeleton-run.sh` — the full pipeline orchestrator that wires Stage −1 through Stage [6] together, with task selection, dependency validation, and scheduling mode dispatch.

**Files to create:**

- `scripts/skeleton-run.sh` — main run entry point:
  - Parse args: `[--plan PATH] [task IDs…] [--tasks CSV] [--driver DRIVER] [--parallel|--sequential] [--no-auto-merge] [--skip-acceptance] [--acceptance-only] [--force-deps] [--dry-run]`
  - Stage −1: `scripts/knowledge/sync.sh`
  - Router check: `router_check_required()` → start if `auto_start: true`
  - Plan selection: `--plan PATH` → explicit; default → `manifest.defaults.plan`; multiple `docs/PLAN*.md` → interactive picker (or fail if `--no-interactive`)
  - Task selection: all pending | listed IDs | `--tasks CSV`
  - Dep validation: `--strict-deps` default; `--force-deps` logs warn, proceeds
  - Scheduling: `schedule_hybrid/parallel/sequential` per flag
  - Stage 0: run task batches; collect exit codes
  - Stage [2] skip matrix (see §8.17): single task in-place → skip [2]; multi-track → run [2]
  - Stages [3]-[6]: `integration.sh`, `global_validation.sh`, `acceptance.sh`, `pr.sh`
  - `--dry-run`: print execution plan; no agents invoked; no git changes

**Validation:**

- `bash -n scripts/skeleton-run.sh`: zero syntax errors
- `skeleton run --dry-run`: prints stage execution plan for all pending tasks; exits 0; no git changes
- `skeleton run 1 2` with task 2 depending on task 1 (incomplete) + `--strict-deps` → exits non-zero before any agent runs
- `skeleton run 1 2 --force-deps` → logs warning containing `force-deps`; proceeds
- `skeleton run --plan docs/PLAN.md 1 --no-auto-merge` → Stage 0 completes; Stage [2] skipped; pipeline stops

**Prompt context needed:** Spec §8 (orchestration pipeline), §8.1 (scheduling modes), §8.2 (task selection), §8.3 (dep validation), §8.5 (full pipeline diagram), §8.6 (Stage [2] skip matrix — see §8.17 deep knowledge)

---

### Task 14 — Lifecycle Commands: `init`, `integrate`, `doctor`, `autoskills`

<!-- ✅ Task 14 completed -->

**Goal:** Implement the four core lifecycle commands that scaffold and validate projects, including the brownfield `skeleton integrate` flow (Appendix A checklist) and the `skeleton autoskills` stack-detection agent.

**Files to create:**

- `bin/skeleton init` (implement stub from Task 3):
  - `skeleton init <lang> --name=<name> [--dir=DIR]`
  - Copy language template from `templates/<lang>/`
  - Write `.ai/manifest.yaml` from `templates/ai/manifest.yaml.template` with project name/domain
  - Write `config/skeleton.yaml` from `config/skeleton.yaml.template`
  - Create `docs/PLAN.md` stub from `templates/docs/PLAN.md.stub`
  - Create `scripts/hooks/` from `templates/hooks/<lang>/`
  - Optional Copilot agent validation (skip with `--no-agent` or `SKIP_AGENT=true`)
- `bin/skeleton integrate` (implement stub):
  - Runs Appendix A checklist in order (see §8.11 deep knowledge)
  - Idempotent: re-running integrate on already-integrated project is safe
- `bin/skeleton doctor` (enhance existing):
  - Add new checks: `.ai/manifest.yaml` exists + valid, `config/skeleton.yaml` valid, `ars` CLI on PATH, router health (if required), driver binary on PATH, Node.js version (if `sdk_cursor`), PLAN.md presence
  - Output: pass/warn/fail per check; exit non-zero if any fail
- `bin/skeleton autoskills` (implement stub):
  - Detect language from repo (file extensions, `go.mod`, `pyproject.toml`, `package.json`, `Cargo.toml`, `pom.xml`)
  - Output recommended domain skills to `.ai/skills/<name>/SKILL.md`
  - Trigger Stage −1 compose refresh
- `templates/docs/PLAN.md.stub` — minimal PLAN.md template with all 8 required sections as H2 stubs

**Validation:**

- `skeleton init go --name=test-svc --dir=/tmp/test-svc`: creates valid project structure with `.ai/manifest.yaml`, `config/skeleton.yaml`, `docs/PLAN.md`
- `skeleton doctor` on fresh `init` output: all checks pass; exits 0
- `skeleton integrate` on this repo (has `.github/copilot-instructions.md`): writes `.ai/manifest.yaml`; `skeleton doctor` passes after
- `skeleton autoskills` on Go repo: writes at least one skill under `.ai/skills/`

**Prompt context needed:** Spec §25 (lifecycle commands), Appendix A (integrate checklist), §22.1 (Must list), §15 (multi-project model)

---

### Task 15 — Hook Templates + T1/T3 Testing Infrastructure <!-- ✅ Task 15 completed -->

**Goal:** Create quality-gate and acceptance hook templates for all four supported stacks, implement `skeleton hooks regenerate`, and wire T1 (per-task) and T3 (post-integration) hook calls into the pipeline.

**Files to create:**

- `templates/hooks/go/quality-gates.sh` — `go build ./...`, `go vet ./...`, `go test ./...`; exit non-zero on first failure
- `templates/hooks/python/quality-gates.sh` — `ruff check .`, `mypy .`, `pytest`; configurable via env
- `templates/hooks/typescript/quality-gates.sh` — `tsc --noEmit`, `eslint .`, `vitest run` or `jest`
- `templates/hooks/fullstack/quality-gates.sh` — detects backend + frontend sub-dirs; calls both
- `templates/hooks/{go,python,typescript,fullstack}/acceptance-gates.sh` — stub with `TODO: add project-specific E2E tests`; exits 0 by default
- `bin/skeleton hooks regenerate` (implement stub from Task 3):
  - `detect_stack(project_root)` → `go|python|typescript|fullstack|unknown`
  - Copy matching template to `scripts/hooks/quality-gates.sh` and `scripts/hooks/acceptance-gates.sh`
  - Print which stack was detected
- T2 optional smoke: `testing.t2_enabled: true` in config → run `scripts/hooks/quality-gates.sh` on changed files after Stage 0 batch (before [2] merge)

**Validation:**

- `bash -n templates/hooks/go/quality-gates.sh`: zero syntax errors
- `bash -n templates/hooks/python/quality-gates.sh`: zero syntax errors
- `bash -n templates/hooks/typescript/quality-gates.sh`: zero syntax errors
- `skeleton hooks regenerate` on this repo (has `.github/`): detects stack; writes `scripts/hooks/quality-gates.sh`; exits 0
- T1 hook path: `task_executor.sh` calls `scripts/hooks/quality-gates.sh` after each task (mock hook exits 1 → task marked failed)

**Prompt context needed:** Spec §11 (testing strategy T1/T2/T3), §13.2 (hooks config keys), §25.2 (greenfield workflow)

---

### Task 16 — Acceptance Pipeline: `acceptance.sh` + Feedback Router (5b/5c) + Docs Sync [4] <!-- ✅ Task 16 completed -->

**Goal:** Implement Stage [5b] acceptance, Stage [5c] test-sufficiency, Stage [4] docs-sync, and the feedback router that re-routes failures back to the appropriate earlier stage.

**Files to create:**

- `scripts/pipeline/acceptance.sh`:
  - `run_5b(project_root)` — hard gates: `scripts/hooks/acceptance-gates.sh`; optional soft LLM evaluation when `acceptance.llm_evaluator: true`
  - `run_5c(project_root)` — test-builder sufficiency: invoke `test-builder` agent with "assess sufficiency" role; expect `VERDICT: SUFFICIENT | NEEDS_TESTS | NEEDS_FIX`
  - `feedback_router(failure_class, task_n)` — routes failure to correct fix path:
    - `lint_build_unit` → refactor → retry 5a
    - `wrong_behavior` → refactor → 5a → 5b
    - `missing_tests` → test-builder → 5a → 5c
    - `wrong_feature` → task-runner on Task N → Stage 0 for N → re-enter [2]-[6]
  - `acceptance.max_retries` cap (default 5) → on exceed: write `run-status.json` `acceptance: FAILED`; no PR; exit 1
  - `--skip-acceptance` flag sets `acceptance.skip: true` at runtime
  - `--acceptance-only` flag: run [5b]/[5c] on current branch without running Stage 0
- `scripts/pipeline/integration.sh` (extend Task 2):
  - Add `run_docs_sync()` — Stage [4]: if `docs/PROGRESS_REPORT.md` exists → invoke `merge-reviewer` with `docs-sync` skill; advisory (non-blocking); log to `.skeleton-dev/logs/docs-sync.log`

**Validation:**

- `bash -n scripts/pipeline/acceptance.sh`: zero syntax errors
- `acceptance.skip: true` → `run_5b` exits 0 immediately without calling hook
- Feedback router: `failure_class=missing_tests` → routes to `test-builder`; `failure_class=wrong_feature` with `task_n=3` → routes back to `execute_task 3`
- `acceptance.max_retries` exceeded → `run-status.json` shows `global-validation-5b: FAILED`; no `gh pr create` called
- `run_docs_sync` with absent `docs/PROGRESS_REPORT.md` → skips silently (no error)

**Prompt context needed:** Spec §12 (global validation and acceptance), §12.1 (Stage 5 flow), §12.3 (feedback router), §8.6 (deep knowledge feedback router table)

---

### Task 17 — Migration Shim + Final Integration Test + Documentation <!-- ✅ Task 17 completed -->

**Goal:** Complete the `phases.yaml` → PLAN.md migration adapter, validate the full end-to-end pipeline, and update all project documentation to reflect the v1.0 architecture.

**Files to create / modify:**

- `config/phases.yaml` (add deprecation adapter): read `phases.yaml`, emit deprecation warning, translate phase N → Task N PLAN.md format for one release compatibility
- `scripts/run_parallel.sh` (finalize shim from Task 3): ensure all env var mappings from spec §21.2 are translated (`MODEL_HEAVY` → `router.combos.heavy`, `COPILOT_MODEL` → `execution.cli.model`, etc.)
- `README.md` (update): add v1.0 architecture diagram (`bin/skeleton` five-plane overview), new `skeleton run` quick-start, deprecation notice for `run_parallel.sh`, prerequisite table (ars, 9router, driver CLIs, gh, Node.js)
- `docs/PARALLEL_DEV.md` (update): add migration guide section pointing to `skeleton run`; mark phase-based sections as deprecated
- Integration test script `tests/integration/test_skeleton_run.sh`:
  - Setup: `skeleton init go --name=e2e-test --dir=/tmp/e2e-test`
  - Populate minimal `docs/PLAN.md` with 2 tasks (task 2 depends on task 1)
  - `skeleton run --dry-run`: verify execution plan
  - `skeleton run 1` with mock driver: verify checkpoint tag, PLAN marker, T1 hook called
  - `skeleton run --force-deps 2` with mock driver: verify warning logged
  - `skeleton doctor` post-run: all checks pass
  - Cleanup: `skeleton cleanup --force`

**Final Validation Checklist (v1.0 Must items from §22.1):**

- [ ] `skeleton run` executes PLAN tasks with full/partial selection
- [ ] Hybrid mode is default; `--parallel` and `--sequential` flags work
- [ ] Stage 0 agent pipeline (7 steps, task-named) runs correctly
- [ ] Stages [2]–[6] preserved from existing `run_parallel.sh` behavior
- [ ] T1 runs after each task; T3 runs at 5a
- [ ] Stage −1 compose-if-stale (not full import on every run)
- [ ] `.ai/manifest.yaml` identity + `config/skeleton.yaml` runtime split enforced
- [ ] `skeleton router install/start/check/oauth` all functional
- [ ] `router_http` driver assembles prompt + calls 9router + classifies 429
- [ ] `cli_subscription` driver: copilot adapter functional; claude/codex stubs with correct flags
- [ ] `sdk_cursor` driver: local runtime functional with `CURSOR_API_KEY`
- [ ] `skeleton integrate` runs full Appendix A checklist
- [ ] `scripts/run_parallel.sh` deprecation shim passes all calls to `skeleton run`
- [ ] `docs/PROGRESS_REPORT.md` updated in Stage [4] when present
- [ ] `bash -n` passes on all shell scripts
- [ ] `python3 -m py_compile` passes on all Python files
- [ ] `node --check` passes on all `.mjs` files
- [ ] `tests/integration/test_skeleton_run.sh` exits 0

**Prompt context needed:** Spec §21 (migration), §22.1 (Must list), §18.2 (migration phases), §10.5 (phase → task map)

---

## 6. Task Summary

| Task | Name                                           | Key Files                                                                                              | Depends On               | Est. Complexity |
| ---- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------ | --------------- |
| 1    | Repository Scaffold + lib/ Extraction          | `scripts/lib/common.sh`, `checkpoint.sh`, `policy.sh`, dir stubs                                       | —                        | Low             |
| 2    | Pipeline Script Extraction                     | `scripts/lib/agent.sh`, `hooks.sh`, `scripts/pipeline/integration.sh`, `global_validation.sh`, `pr.sh` | Task 1                   | Medium          |
| 3    | `bin/skeleton` Subcommand Dispatcher           | `bin/skeleton`, `scripts/run_parallel.sh` (shim)                                                       | Task 1                   | Medium          |
| 4    | Config Split: manifest + skeleton.yaml         | `config/skeleton.yaml.template`, `templates/ai/manifest.yaml.template`, `scripts/lib/config.sh`        | Task 1                   | Medium          |
| 5    | PLAN.md Parser                                 | `scripts/plan/plan_parser.py`, `plan_validate.py`                                                      | Task 1                   | High            |
| 6    | `.skeleton-dev/` State + Observability         | `scripts/lib/state.sh`, `skeleton status`, `skeleton cleanup`                                          | Tasks 3, 4, 5            | Medium          |
| 7    | Knowledge Plane: Stage −1 (ARES)               | `scripts/knowledge/sync.sh`, `detect_legacy.py`, `import.sh`, `compose.sh`                             | Tasks 4, 6               | High            |
| 8    | Router Wrapper (9router)                       | `router/wrap.sh`, `router/9router-pin.json`, `scripts/lib/router.sh`                                   | Tasks 3, 4               | Medium          |
| 9    | Driver: `router_http`                          | `drivers/router_http/run.sh`, `drivers/registry.yaml`                                                  | Tasks 4, 8               | High            |
| 10   | Driver: `cli_subscription`                     | `drivers/cli/copilot.sh`, `claude.sh`, `codex.sh`                                                      | Tasks 4, 8               | Medium          |
| 11   | Driver: `sdk_cursor`                           | `drivers/cursor-sdk/run.mjs`, `package.json`                                                           | Task 4                   | Medium          |
| 12   | Stage 0: Per-Task Executor                     | `scripts/pipeline/task_executor.sh`, `modes.sh`                                                        | Tasks 2, 5, 6, 9, 10, 11 | High            |
| 13   | `skeleton run` Orchestrator                    | `scripts/skeleton-run.sh`                                                                              | Tasks 7, 8, 12           | High            |
| 14   | Lifecycle: init, integrate, doctor, autoskills | `bin/skeleton init/integrate/doctor/autoskills`                                                        | Tasks 4, 7, 8            | High            |
| 15   | Hook Templates + T1/T3 Infrastructure          | `templates/hooks/*/quality-gates.sh`, `acceptance-gates.sh`, `skeleton hooks regenerate`               | Tasks 2, 12              | Medium          |
| 16   | Acceptance Pipeline + Feedback Router          | `scripts/pipeline/acceptance.sh`, docs-sync extension                                                  | Tasks 13, 15             | High            |
| 17   | Migration Shim + Final Integration Test + Docs | `tests/integration/test_skeleton_run.sh`, `README.md`, `PARALLEL_DEV.md`                               | All                      | Medium          |

---

## 7. How to Use This Plan

1. **Start each task in a fresh chat session** — share this PLAN.md + the spec sections listed under "Prompt context needed"
2. **Validate after each task** — run `bash -n <script>` (shell), `python3 -m py_compile <file>` (Python), `node --check <file>` (Node.js) before moving to the next task
3. **Update this plan** as you learn new constraints during implementation
4. **One task at a time** — do not attempt multiple tasks in a single session to avoid context overflow
5. **Migration phases matter**: Tasks 1–3 are Phase 1 (low risk, preserve behavior). Tasks 4–6 are Phase 2. Tasks 7–17 are Phase 3. Never start Phase 3 tasks until Phase 1 passes all existing parallel dev workflows.
6. **Source of truth** — always refer to `docs/specs/2026-06-27-agentic-loop-cli-design.md` for exact design decisions. This PLAN.md is the breakdown strategy; the spec is the specification.

---

## 8. Deep Knowledge Reference

This section contains complete schemas, algorithms, and rules extracted from `docs/specs/2026-06-27-agentic-loop-cli-design.md`. Include the relevant subsection(s) in every task session.

---

### 8.1 Stage −1 Algorithm (spec §5.3.4)

```
1. Resolve PROJECT_ROOT (cwd or --dir)
2. Load .ai/manifest.yaml (required after integrate; scaffold if integrate-only)
3. IMPORT if combination policy triggers → ars import * --merge
   Triggers: .ai/ missing | skeleton integrate flag | skeleton sync --import |
             import_policy:always | import_policy:merge_on_stale AND legacy mtime > .ai/ mtime
   Default on normal skeleton run: NO import if .ai/ healthy
4. ars validate → on failure: abort with doctor report (non-zero exit)
5. COMPOSE if stale → ars compose --target manifest.defaults.provider
   Trigger: sha256(.ai/**) ≠ .skeleton-dev/compose.stamp
   Default on normal skeleton run: compose ONLY if stale
6. Legacy fallback: if compose fails but previous composed artifacts exist
   → log WARN, use last good output, set SKELETON_COMPOSED_DEGRADED=true
7. If no .ai/ and import failed → abort with fix instructions
8. Write .skeleton-dev/compose.stamp = sha256(.ai/**)
```

---

### 8.2 ExecutionDriver Interface (spec §19)

**Shell contract:**

```bash
run_driver() {
  local driver="$1"       # router_http | cli_subscription | sdk_cursor
  local stage="$2"        # task-runner | dto-guardian | integration | security-auditor | test-builder
  local work_dir="$3"
  local prompt_file="$4"  # path to .skeleton-dev/TASK_PROMPT.md
  local model="$5"        # combo alias or model id
  local log_file="$6"
  # returns: 0=success, 1=agent_error, 2=quota_exhausted, 3=fatal
}
```

**Stage prompt template variables:**

| Variable                   | Source                                                |
| -------------------------- | ----------------------------------------------------- |
| `{{TASK_NUMBER}}`          | Current task N from plan index                        |
| `{{PLAN_PATH}}`            | Active plan file path                                 |
| `{{SKILLS_CSV}}`           | Resolved skill list (§8.13)                           |
| `{{WORKSPACE_CONSTRAINT}}` | Fixed policy string: never write outside PROJECT_ROOT |
| `{{STAGE_NAME}}`           | Pipeline stage name                                   |

**Required capabilities (all drivers):**

| Capability                                | router_http | cli_subscription | sdk_cursor |
| ----------------------------------------- | ----------- | ---------------- | ---------- |
| Non-interactive                           | Yes         | Yes              | Yes        |
| Workspace confined to PROJECT_ROOT        | Yes         | Yes              | Yes        |
| Structured exit codes                     | Yes         | Yes              | Yes        |
| Token/quota error classification → exit 2 | Yes         | Yes              | Yes        |
| Streaming log                             | Yes         | Yes              | Yes        |

---

### 8.3 Stage 0 — 7-Step Agent Chain (spec §8.7)

Checkpoint: `checkpoint-task-N-pre` (git tag before chain).

| Step | Agent                 | Max retries | On exceed                  |
| ---- | --------------------- | ----------- | -------------------------- |
| 1    | task-runner           | 5           | rollback                   |
| 2    | dto-guardian          | 5           | rollback                   |
| 3    | integration           | 5           | rollback                   |
| 4    | security-auditor      | 3           | rollback                   |
| 5    | test-builder          | 3           | rollback                   |
| 6    | protected file check  | —           | rollback                   |
| 7    | quality-gates.sh (T1) | —           | refactor ≤3, then rollback |

**On success:**

- Mark `<!-- ✅ Task N completed -->` in PLAN.md (only allowed PLAN mutation in Stage 0)
- Commit: `feat(task-N): implement <name>`

---

### 8.4 Agentic Loop Layers (spec §9)

| Layer  | Name      | Mechanism                                       | Stop condition                           |
| ------ | --------- | ----------------------------------------------- | ---------------------------------------- |
| **L1** | Turn loop | Inside ExecutionDriver (tool calls)             | No more tool calls / stage complete      |
| **L2** | Task loop | task-runner → validate → fix → repeat           | Task `Validation` section exits 0        |
| **L3** | Plan loop | Scheduler runs task batches until PLAN complete | All tasks `<!-- ✅ -->`                  |
| **L4** | Goal loop | Optional `--until` + `--max-turns`              | Shell expr pass + optional LLM evaluator |

**Budget caps (L4, all layers):** `max_turns`, `max_tokens`, wall-clock timeout — always enforced in `config/skeleton.yaml`.

---

### 8.5 Full Pipeline Diagram (spec §8.5)

```
skeleton run [--plan PATH] [task IDs…] [--driver …] [--parallel|--sequential]
        │
        ▼
╔══════════════════════════════════════════════════════════╗
║  STAGE −1  Knowledge sync + router check/start           ║
╚══════════════════════════════╤═══════════════════════════╝
                               ▼
╔══════════════════════════════════════════════════════════╗
║  RESOLVE  plan · tasks · deps · parallel-safe file sets  ║
╚══════════════════════════════╤═══════════════════════════╝
                               ▼
╔══════════════════════════════════════════════════════════╗
║  STAGE 0  Per task / per parallel track                  ║
║  7-step agent chain · T1 hook · checkpoint/rollback      ║
╚══════════════════════════════╤═══════════════════════════╝
                               ▼
╔══════════════════════════════════════════════════════════╗
║  [2] Union merge (if ≥2 tracks)  — 5 retries            ║
║  [3] Post-merge review           — 5 retries            ║
║  [4] Docs sync (advisory)        — 1 attempt            ║
║  [5a] quality-gates.sh (T3)      — 5 cycles             ║
║  [5b] acceptance-gates.sh + LLM  — 5 retries            ║
║  [5c] test-builder sufficiency   — 5 retries            ║
║  [6] git push + gh pr create                            ║
╚══════════════════════════════════════════════════════════╝
```

---

### 8.6 Global Validation Flow (spec §12.1)

```
[5a] quality-gates.sh — full repo T3
  │  fail → refactor (≤5) → retry 5a
  ▼
[5b] acceptance-gates.sh — hard: PLAN criteria, E2E
     optional soft: LLM evaluator (acceptance.llm_evaluator: true)
  │  fail → feedback router (§8.7)
  ▼
[5c] test-builder extended — SUFFICIENT | NEEDS_TESTS | NEEDS_FIX
  │  fail → feedback router
  ▼
PASS → [6] PR
```

**Note:** Soft LLM layers in [5b]/[5c] are **intentionally non-deterministic**. Orchestration determinism applies to scheduling, script gate results, retry bounds, and state transitions only.

---

### 8.7 Feedback Router (spec §12.3)

| Failure class          | Route to                         | Then                             |
| ---------------------- | -------------------------------- | -------------------------------- |
| `lint_build_unit`      | refactor                         | 5a                               |
| `wrong_behavior_small` | refactor                         | 5a → 5b                          |
| `missing_tests`        | test-builder                     | 5a → 5c                          |
| `wrong_feature`        | task-runner on Task N            | Stage 0 for N → re-enter [2]–[6] |
| `frontend_broken`      | task-runner on owning task + E2E | same                             |

**Max cycles:** `acceptance.max_retries` (default 5) → run FAILED, no PR.

---

### 8.8 Scheduling Modes (spec §8.1, §8.2)

| Mode           | Flag           | Behavior                                                                                       |
| -------------- | -------------- | ---------------------------------------------------------------------------------------------- |
| **Hybrid**     | (default)      | Batch tasks by dep graph + file-ownership safety; parallel inside batch, serial across batches |
| **Parallel**   | `--parallel`   | One worktree per task (subject to `max_parallel_agents`)                                       |
| **Sequential** | `--sequential` | Single branch/session; strict dependency order                                                 |

**Task selection:**

| Invocation                   | Task set                              |
| ---------------------------- | ------------------------------------- |
| `skeleton run`               | All pending (not `<!-- ✅ -->`) tasks |
| `skeleton run --full`        | Explicit alias for all pending        |
| `skeleton run 1 2 3`         | Tasks 1, 2, 3 only                    |
| `skeleton run --tasks 1,2,3` | Same                                  |

---

### 8.9 Configuration Schemas (spec §13)

**`.ai/manifest.yaml` (identity — canonical):**

```yaml
version: "2.0"
project:
  name: <project-name>
  domain: <domain>
  description: <one-line description>
defaults:
  provider: copilot # ars compose --target value
  agent: task-runner
  plan: docs/PLAN.md
skills:
  always:
    - plan-management
    - <domain-skill>
knowledge:
  import_policy: merge_on_stale # never | on_missing | merge_on_stale | always
```

**`config/skeleton.yaml` (runtime — NO identity fields):**

```yaml
version: "1"
execution:
  driver: cli_subscription # router_http | cli_subscription | sdk_cursor
  cli:
    provider: copilot # copilot | claude | codex — NOT cursor
  cursor:
    runtime: local # local | cloud
    model: composer-2.5
  mode: hybrid
  max_parallel_agents: 3
router:
  driver: nine_router # nine_router | openai_compatible | mock
  enabled: true
  auto_start: true
  endpoint: http://localhost:20128/v1
  combo: project-default
  inject: true
  quota_retry:
    enabled: true
    interval: 1h
    max_total_wait: 24h
    on_exhausted: sleep_and_retry
retries:
  task_runner: 5
  dto_guardian: 5
  integration: 5
  security_auditor: 3
  test_builder: 3
  refactor: 3
  merge: 5
  global_validation: 5
  acceptance: 5
acceptance:
  llm_evaluator: true
  skip: false
testing:
  t2_enabled: false
  strict_deps: true
hooks:
  quality: scripts/hooks/quality-gates.sh
  acceptance: scripts/hooks/acceptance-gates.sh
logging:
  dir: .skeleton-dev/logs
```

**Invalid config guard:** `execution.driver=cli_subscription` + `execution.cli.provider=cursor` → doctor error with fix hint.

---

### 8.10 `plan-index.json` Schema (spec §10.4)

```json
{
  "plan_path": "docs/PLAN.md",
  "generated_at": "2026-06-27T00:00:00Z",
  "tasks": {
    "1": {
      "line_start": 120,
      "line_end": 145,
      "name": "Repository Scaffold + lib/ Extraction",
      "goal": "Create the new directory skeleton...",
      "files": ["scripts/lib/common.sh", "scripts/lib/checkpoint.sh"],
      "depends_on": [],
      "complexity": "Low",
      "status": "pending",
      "validation_line": 138
    }
  },
  "dep_graph": {
    "1": [],
    "2": [1],
    "3": [1],
    "4": [1],
    "5": [1],
    "6": [3, 4, 5]
  },
  "file_ownership": {
    "scripts/lib/common.sh": [1],
    "scripts/lib/checkpoint.sh": [1]
  }
}
```

---

### 8.11 `skeleton integrate` Checklist (Appendix A)

1. Run `skeleton upgrade --mode=hybrid` (framework files)
2. `ars init` if no `.ai/`
3. `detect_legacy.py` → `ars import` merge
4. Write `config/skeleton.yaml` from template (runtime only)
5. Merge/project-fill `.ai/manifest.yaml`
6. `ars validate`
7. `ars compose --target <provider>`
8. `skeleton router install && start`
9. `skeleton router oauth` (guided)
10. Generate hooks from `templates/hooks/<detected-stack>/`
11. `skeleton doctor`
12. Print next step: `skeleton run` or `skeleton run --full`

---

### 8.12 Driver Selection Rules (spec §7.5)

| `execution.driver` | `execution.cli.provider` | Runtime           |
| ------------------ | ------------------------ | ----------------- |
| `router_http`      | ignored                  | Harness → 9router |
| `cli_subscription` | `copilot`                | copilot CLI       |
| `cli_subscription` | `claude`                 | claude CLI        |
| `cli_subscription` | `codex`                  | codex CLI         |
| `sdk_cursor`       | ignored                  | @cursor/sdk       |

**INVALID:** `cli_subscription` + `cli.provider: cursor` → doctor error with fix hint.

---

### 8.13 Skills Resolution Algorithm (spec §7.7)

```
FINAL_SKILLS =
    FRAMEWORK_CORE                    # SKELETON_ROOT/framework/skills/*
  + manifest.skills.always            # .ai/skills/*
  + PLAN.task.skills (if specified)   # per-task frontmatter override
  + STAGE_SKILLS[stage_name]          # e.g., docs-sync on stage [4]
```

**Agent resolution (`resolve_agent(stage, task)`):**

1. PLAN task frontmatter: `agent: <name>`
2. `manifest.defaults.agent`
3. Framework default for stage
4. Load `AGENT.md` content from `.ai/agents/{name}/` into prompt

---

### 8.14 Quota Retry + Failure Handling (spec §20)

**Quota exhaustion (9router paths):**

1. Driver receives 429 / quota / combo exhausted → exit code 2
2. If 9router can switch combo member → transparent retry (9router handles)
3. If all exhausted → skeleton `quota_retry`: sleep `router.quota_retry.interval`, retry same stage
4. If `max_total_wait` exceeded → fail run with actionable message

**Quota exhaustion (Cursor SDK):**

- Same `quota_retry` policy at driver level — no 9router involved
- Map Cursor rate-limit error strings → exit code 2

**Checkpoint rollback (spec §20.3):**

- Tag before task: `checkpoint-task-N-pre`
- On retry exceed: `git reset --hard checkpoint-task-N-pre`
- Log to `.skeleton-dev/logs/agent-chain.log`

---

### 8.15 Target Repository Layout (spec §18.1)

```
skeleton-parallel/
  bin/skeleton
  framework/agents/    framework/skills/
  router/wrap.sh       router/9router-pin.json    router/docker-compose.yml
  drivers/router_http/ drivers/cli/{copilot,claude,codex}.sh
  drivers/cursor-sdk/{package.json,run.mjs}   drivers/registry.yaml
  templates/hooks/{go,python,typescript,fullstack}/
  scripts/skeleton-run.sh   scripts/run_parallel.sh (shim)
  scripts/knowledge/{sync.sh,detect_legacy.py,import.sh,compose.sh}
  scripts/plan/{plan_parser.py,plan_validate.py}
  scripts/pipeline/{agent_pipeline.sh,modes.sh,task_executor.sh,
                    integration.sh,global_validation.sh,acceptance.sh,pr.sh}
  scripts/lib/{common.sh,checkpoint.sh,state.sh,router.sh,
               agent.sh,hooks.sh,policy.sh,config.sh}
  config/skeleton.yaml.template    config/phases.yaml (deprecated)
  docs/specs/2026-06-27-agentic-loop-cli-design.md
```

---

### 8.16 Phase → Task Migration Map (spec §10.5)

| Legacy                           | New                                              |
| -------------------------------- | ------------------------------------------------ |
| `config/phases.yaml` phase N     | `### Task N` in `docs/PLAN.md`                   |
| `PHASE_TASK.md`                  | `.skeleton-dev/TASK_PROMPT.md`                   |
| `phase-builder`                  | `task-runner`                                    |
| `track/phase-N`                  | `track/task-N`                                   |
| `.parallel-dev/`                 | `.skeleton-dev/` (shim reads old path 1 release) |
| `run_parallel.sh start 1 2 3`    | `skeleton run 1 2 3`                             |
| `run_parallel.sh start --mode=1` | `skeleton run --parallel`                        |
| `run_parallel.sh start --mode=2` | `skeleton run --sequential`                      |
| `run_parallel.sh start --mode=3` | `skeleton run` (hybrid default)                  |
| `MODEL_HEAVY` env                | `router.combos.heavy` in skeleton.yaml           |
| `COPILOT_MODEL` env              | `execution.cli.model` in skeleton.yaml           |
| `MAX_PARALLEL_AGENTS` env        | `execution.max_parallel_agents` in skeleton.yaml |

---

### 8.17 Stage [2] Skip Matrix (spec §8.6)

| Scenario                    | [2] Union Merge              | [3]–[6]  |
| --------------------------- | ---------------------------- | -------- |
| Single task, in-place       | **Skip**                     | **Run**  |
| Multiple tasks, one branch  | **Skip**                     | **Run**  |
| Multiple parallel worktrees | **Run**                      | **Run**  |
| `--no-auto-merge`           | Deferred to `skeleton merge` | Deferred |

---

_End of plan._
