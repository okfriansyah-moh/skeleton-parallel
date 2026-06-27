# Agentic Loop CLI — Design Specification

> **Version:** 1.0 (v8 architecture)  
> **Date:** 2026-06-27  
> **Status:** Approved for implementation planning  
> **Authors:** skeleton-parallel design session  
> **Supersedes:** phase-based `run_parallel.sh` + `config/phases.yaml` as primary work contract  

---

## Table of contents

1. [Executive summary](#1-executive-summary)
2. [Goals and non-goals](#2-goals-and-non-goals)
3. [Terminology](#3-terminology)
4. [System architecture](#4-system-architecture)
5. [Knowledge plane (ARES)](#5-knowledge-plane-ares)
6. [Routing plane (skeleton-wrapped 9router)](#6-routing-plane-skeleton-wrapped-9router)
7. [Execution drivers](#7-execution-drivers)
8. [Orchestration pipeline](#8-orchestration-pipeline)
9. [Agentic loop layers](#9-agentic-loop-layers)
10. [PLAN.md work contract](#10-planmd-work-contract)
11. [Testing strategy (T1, T2, T3)](#11-testing-strategy-t1-t2-t3)
12. [Global validation and acceptance (5a, 5b, 5c)](#12-global-validation-and-acceptance-5a-5b-5c)
13. [Configuration](#13-configuration)
14. [CLI reference](#14-cli-reference)
15. [Multi-project operation](#15-multi-project-operation)
16. [State, logs, and observability](#16-state-logs-and-observability)
17. [Documentation and protected paths policy](#17-documentation-and-protected-paths-policy)
18. [Repository layout and script migration](#18-repository-layout-and-script-migration)
19. [ExecutionDriver interface](#19-executiondriver-interface)
20. [Failure handling and quota retry](#20-failure-handling-and-quota-retry)
21. [Migration from run_parallel.sh](#21-migration-from-run_parallelsh)
22. [Release scope (Must / Should / Defer)](#22-release-scope-must--should--defer)
23. [Future parking lot](#23-future-parking-lot)
24. [Self-review checklist](#24-self-review-checklist)
25. [Lifecycle commands (init, doctor, autoskills)](#25-lifecycle-commands-init-doctor-autoskills)

---

## 1. Executive summary

skeleton-parallel evolves from a **phase-based parallel development script** into a **provider-agnostic agentic loop CLI** (`skeleton`) that:

- Executes work from **`docs/PLAN.md`** tasks (a2a-brainstormer / SDD format), not `config/phases.yaml` phases.
- Runs **nested agentic loops** (turn → task → plan → optional goal) with hybrid parallel/serial scheduling (hybrid default).
- Preserves the **full six-stage integration pipeline** (union merge → review → docs sync → global validation → PR).
- Separates **knowledge** (ARES `.ai/`), **routing** (9router, wrapped by skeleton), and **execution** (pluggable drivers).
- Supports **three execution drivers from v1.0**:
  - **Model 1 — `router_http`:** HTTP harness → skeleton-wrapped 9router (OAuth subscriptions).
  - **Model 2 — `cli_subscription`:** Vendor **CLI** for Copilot, Claude Code, Codex.
  - **Model 2 (Cursor) — `sdk_cursor`:** **`@cursor/sdk` only** for Cursor (no Cursor CLI driver).

**Critical distinction:** Cursor SDK is an **execution driver**, not a replacement for 9router. 9router routes Copilot/Codex/Claude subscription traffic; Cursor SDK talks to Cursor’s agent runtime directly.

---

## 2. Goals and non-goals

### 2.1 Goals

| ID | Goal |
|----|------|
| G1 | One CLI (`skeleton run`) for parallel, sequential, and hybrid task execution from PLAN.md |
| G2 | Provider-agnostic **knowledge** via ARES `.ai/` with auto sync (compose-if-stale, import-on-trigger) |
| G3 | Provider-agnostic **inference routing** via skeleton-wrapped 9router (OAuth, combos, fallback) |
| G4 | Dual execution: HTTP→9router **and** vendor CLI **and** Cursor SDK from v1.0 |
| G5 | Subscription-based auth (Copilot/Codex/Claude via 9router or CLI login; Cursor via API key / plan) — no raw vendor API keys in repo config for drivers A/B |
| G6 | Quota exhaustion handling: configurable sleep/retry when tokens/combos exhausted |
| G7 | Per-task **and** post-integration testing (T1 + T3) |
| G8 | Acceptance validation (5a technical, 5b intent hard+soft LLM, 5c test sufficiency via extended test-builder) |
| G9 | Per-task runs (`skeleton run 1 2 3`) with full post-pipeline where applicable |
| G10 | Multi-project: each repo brings domain agents/skills; skeleton brings framework agents/skills |
| G11 | Preserve checkpoint/rollback, bounded retries, union merge, protected paths |

### 2.2 Non-goals (v1.0)

| ID | Non-goal |
|----|----------|
| NG1 | Web UI dashboard (defer v1.2+) |
| NG2 | IDE-native dual surface (parking lot B/C) |
| NG3 | `skeleton brainstorm` → a2a-brainstormer code generation (defer) |
| NG4 | A2A protocol agent services as runtime (defer v2+) |
| NG5 | Cursor CLI as execution driver (use SDK only) |
| NG6 | Routing Cursor SDK traffic through 9router |
| NG7 | Antigravity CLI driver (compose knowledge only unless CLI exists later) |

---

## 3. Terminology

| Term | Definition |
|------|------------|
| **ARES** | AI Repository Standard tooling (`ars` CLI): `.ai/` canonical → `ars compose` → provider artifacts |
| **9router** | Self-hosted OpenAI-compatible gateway; OAuth for Copilot/Codex/Claude; combos, fallback, RTK |
| **PLAN.md** | Spec-driven implementation plan (`docs/PLAN.md` or `docs/PLAN-*.md`) with `### Task N` sections |
| **Stage −1** | Automatic knowledge sync before execution |
| **Stage 0** | Per-task agent pipeline execution |
| **Stages [2]–[6]** | Integration pipeline after task batch |
| **Driver A / Model 1** | `router_http` — harness → 9router |
| **Driver B / Model 2 CLI** | `cli_subscription` — copilot \| claude \| codex CLI |
| **Driver C / Model 2 Cursor** | `sdk_cursor` — `@cursor/sdk` |
| **T1** | Per-task tests (Stage 0) |
| **T2** | Per-track smoke (optional, end of Stage 0 batch) |
| **T3** | Full-repo tests (Stage 5a) |
| **Framework skills** | Bundled under `SKELETON_ROOT/framework/skills/` |
| **Project skills** | `.ai/skills/` in target repository |
| **Compose target** | ARES `ars compose --target <provider>` — shapes knowledge artifacts only |
| **Execution driver** | How skeleton invokes LLM agents for a stage |

---

## 4. System architecture

### 4.1 Five planes

```
┌────────────────────────────────────────────────────────────────────────────┐
│  PLANE 1 — KNOWLEDGE (ARES)                                                 │
│  .ai/manifest.yaml · instructions · agents · skills · prompts               │
│  import-on-trigger → ars validate → compose-if-stale                        │
│  Compose targets: copilot | claude | codex | cursor | antigravity           │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼───────────────────────────────────────────┐
│  PLANE 2 — ROUTING (skeleton-wrapped 9router)                                │
│  Used by: router_http (always) · cli_subscription (when router.enabled)       │
│  NOT used by: sdk_cursor                                                     │
│  skeleton router install | start | oauth | combos | check                    │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼───────────────────────────────────────────┐
│  PLANE 3 — EXECUTION DRIVERS (v1.0 — all three)                              │
│  router_http │ cli_subscription (copilot|claude|codex) │ sdk_cursor          │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼───────────────────────────────────────────┐
│  PLANE 4 — ORCHESTRATION (skeleton CLI)                                       │
│  Stage −1 · PLAN scheduling · Stage 0 · Stages [2]–[6] · agentic loops       │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼───────────────────────────────────────────┐
│  PLANE 5 — PROJECT                                                           │
│  PLAN.md · hooks · PROGRESS_REPORT.md · domain skills · architecture         │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Concept separation (do not conflate)

| Concept | Responsibility | Is NOT |
|---------|----------------|--------|
| **ARES** | Portable repository knowledge | Agent runtime, routing, billing |
| **9router** | Multi-provider subscription routing, combos | Cursor SDK, skeleton orchestration |
| **Cursor SDK** | Cursor agent runtime (local/cloud) | 9router, Copilot CLI |
| **skeleton** | Orchestration, loops, merge, tests, PR | LLM inference implementation |

### 4.3 End-to-end data flow

```
Human / CI
    │
    ▼
skeleton run [--plan] [tasks] [--driver]
    │
    ├─► Stage −1: .ai/ sync → composed artifacts (CLAUDE.md, .github/, etc.)
    ├─► router check/start (if driver needs 9router)
    ├─► plan_parser: tasks, deps, files, validation, acceptance
    ├─► Stage 0: for each task/track → ExecutionDriver → agent pipeline
    ├─► [2] merge worktrees (if ≥2 tracks)
    ├─► [3] merge-reviewer
    ├─► [4] docs-sync → PROGRESS_REPORT.md
    ├─► [5] 5a → 5b → 5c (with feedback router)
    └─► [6] git push + gh pr create
```

---

## 5. Knowledge plane (ARES)

### 5.1 Canonical source: `.ai/`

```
.ai/
  manifest.yaml           # identity, defaults, skills.always, import_policy
  instructions/           # mission, architecture rules, contribution
  agents/<name>/AGENT.md  # thin role definitions
  skills/<name>/SKILL.md  # domain + shared skills
  prompts/                # implement-and-review-task, etc.
```

**Option C (v1):** `.ai/` is required as canonical end state. Legacy provider files are import sources, not systems of record.

### 5.2 Single source of truth split

| Concern | Canonical file | Examples |
|---------|----------------|----------|
| Identity, compose target, default agent/plan, project skills | `.ai/manifest.yaml` | `provider: claude`, `domain: media` |
| Runtime: router, retries, driver, hooks, PR mode | `config/skeleton.yaml` | `router.combo`, `execution.driver` |

**Rule:** No duplicate identity fields in `config/skeleton.yaml`. If both exist during migration, manifest wins and skeleton.yaml runtime-only keys are kept.

### 5.3 Stage −1 — Knowledge sync (automatic)

Runs at the start of: `skeleton run`, `skeleton merge`, `skeleton goal`.

#### 5.3.1 Import triggers (combination policy)

Import runs when **any** condition is true:

| Trigger | Action |
|---------|--------|
| `.ai/` missing or empty | `ars import` from detected legacy |
| `skeleton integrate` (one-time flag file) | Full import from all detected sources |
| `skeleton sync --import` | User-forced import |
| `manifest.knowledge.import_policy: always` | Import on every sync (discouraged default) |
| `import_policy: merge_on_stale` AND legacy artifact mtime > `.ai/` counterpart | Merge import |

**Default import policy:** `merge_on_stale` on integrate; **no import on normal `skeleton run`** if `.ai/` healthy.

#### 5.3.2 Legacy detection order

| Source | `ars import` target |
|--------|---------------------|
| `.github/copilot-instructions.md`, `.github/agents/`, `.github/skills/` | `github` |
| `CLAUDE.md`, `.claude/` (if present) | `claude` |
| `AGENTS.md` (codex) | `codex` |
| `.cursor/rules/` | `cursor` |
| `.antigravity/` | `antigravity` |

Multiple sources may be imported sequentially with merge semantics.

#### 5.3.3 Compose triggers (staleness guard)

Compose runs when **any** condition is true:

| Trigger | Action |
|---------|--------|
| Hash(`.ai/`) ≠ `.skeleton-dev/compose.stamp` | `ars compose --target <manifest.defaults.provider>` |
| `skeleton sync` (default) | Compose |
| `skeleton integrate` | Compose |
| First run in repo (no stamp) | Compose |

**Default on normal `skeleton run`:** compose **only if stale** — not full import/compose every time.

#### 5.3.4 Stage −1 algorithm

```
1. Resolve PROJECT_ROOT (cwd or --dir)
2. Load .ai/manifest.yaml (required after integrate; scaffold if integrate-only)
3. IMPORT if combination policy triggers → ars import * --merge
4. ars validate → on failure: abort with doctor report (non-zero exit)
5. COMPOSE if stale → ars compose --target manifest.defaults.provider
6. Legacy fallback: if compose fails but previous composed artifacts exist
   → log WARN, use last good composed output, set run flag composed_degraded=true
7. If no .ai/ and import failed → abort with fix instructions
8. Write .skeleton-dev/compose.stamp = sha256(.ai/**)
```

#### 5.3.5 Compose targets vs execution drivers

| `manifest.defaults.provider` | Composed artifacts (examples) |
|------------------------------|-------------------------------|
| `copilot` | `.github/copilot-instructions.md`, agents, skills |
| `claude` | `CLAUDE.md`, Claude-oriented rules |
| `codex` | `AGENTS.md` |
| `cursor` | `.cursor/rules/`, prompts |
| `antigravity` | `.antigravity/` |

Compose target affects **prompt/knowledge shape**. Execution driver is independent (see §7).

---

## 6. Routing plane (skeleton-wrapped 9router)

### 6.1 Purpose

9router provides:

- OpenAI-compatible `http://localhost:20128/v1`
- OAuth connection to **subscription** backends (Copilot, Codex, Claude, etc.)
- Combos, round-robin, tier fallback
- RTK token reduction (aligned with skeleton `rtk` / `caveman` skills)
- Quota visibility in dashboard

skeleton **wraps** 9router — it is not assumed to be manually installed.

### 6.2 Repository layout (skeleton repo)

```
skeleton-parallel/
  router/
    9router-pin.json          # locked npm/docker version
    docker-compose.yml        # optional dev stack
    wrap.sh                   # start | stop | health
    oauth-guide.md            # copied to project docs on integrate
  bin/skeleton                # router subcommands
```

### 6.3 Router CLI (first-class)

| Command | Behavior |
|---------|----------|
| `skeleton router install` | Install pinned 9router (npm -g, docker pull, or binary) |
| `skeleton router start` | Start daemon; default port 20128 |
| `skeleton router stop` | Stop daemon |
| `skeleton router status` | Running / PID / port |
| `skeleton router check` | HTTP health; exit 0/1 |
| `skeleton router oauth` | Print URL / open dashboard; list connected providers |
| `skeleton router combos` | List combos; set project default in skeleton.yaml |

### 6.4 When 9router is required

| Execution config | 9router required |
|------------------|------------------|
| `driver: router_http` | **Yes** |
| `driver: cli_subscription` + `router.enabled: true` | **Yes** (env injection) |
| `driver: cli_subscription` + `router.enabled: false` | No |
| `driver: sdk_cursor` | **No** |

`skeleton run` calls `skeleton router check` when required; if down and `router.auto_start: true`, runs `skeleton router start`.

### 6.5 CLI env injection (Model 2 + router)

When `router.inject: true`, skeleton sets provider-appropriate env before spawning CLI:

| CLI | Typical env vars (documented per 9router version) |
|-----|---------------------------------------------------|
| Copilot | Base URL override per 9router Copilot tool card |
| Claude Code | `ANTHROPIC_BASE_URL` or documented equivalent → 9router |
| Codex | OpenAI-compatible base URL → 9router |

Exact variable names are pinned in `router/inject-env.sh` per 9router release.

### 6.6 Alternative router drivers (extensibility)

| `router.driver` | Use case |
|-----------------|----------|
| `nine_router` | Default — wrapped 9router |
| `openai_compatible` | Any `/v1` proxy (LiteLLM, Ollama shim) — ping only, no auto-install |
| `mock` | CI orchestration tests without real LLM |

---

## 7. Execution drivers

### 7.1 Overview

All pipeline stages call the same **`ExecutionDriver`** interface (§19). Stage names (`task-runner`, `dto-guardian`, …) are unchanged; only the invocation mechanism differs.

```
                    skeleton stage invocation
                              │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                    ▼
   router_http          cli_subscription       sdk_cursor
   (Model 1)            (Model 2)              (Model 2 Cursor)
         │                    │                    │
         ▼                    ▼                    ▼
   HTTP /v1              copilot | claude |      @cursor/sdk
                         codex CLI               Agent.send()
         │                    │                    │
         ▼                    ▼                    ▼
      9router            optional 9router         Cursor cloud/local
      OAuth              via inject               (no 9router)
```

### 7.2 Driver A — `router_http` (Model 1)

**Description:** skeleton-owned tool loop (read/write/bash/grep) using OpenAI-compatible chat completions against 9router.

**Auth:** 9router dashboard OAuth — subscriptions, not repo API keys.

**Use when:**

- Single code path across providers
- Combo fallback across Copilot/Codex/Claude subscriptions
- CI without vendor CLIs installed

**Prompt assembly:**

```
system = composed_instructions
       + framework_skills (SKELETON_ROOT)
       + project_skills (.ai/)
       + TASK_PROMPT.md
       + stage_template(task-runner | dto-guardian | ...)
user   = stage-specific task
```

### 7.3 Driver B — `cli_subscription` (Model 2)

**Description:** Spawn vendor CLI subprocess per stage with injected prompt, skills list, workspace constraints.

| `execution.cli.provider` | Binary | Subscription auth |
|--------------------------|--------|-------------------|
| `copilot` | `copilot` | GitHub token / `copilot` login |
| `claude` | `claude` | `claude login` |
| `codex` | `codex` | Codex OAuth |

**Cursor is NOT a `cli.provider` value.** Selecting Cursor requires `driver: sdk_cursor`.

**Invocation pattern (Copilot — reference, matches current `run_parallel.sh`):**

```bash
copilot \
  -p "${STAGE_PROMPT}" \
  --agent="${AGENT_NAME}" \
  --model="${MODEL_OR_COMBO_ALIAS}" \
  --no-ask-user \
  --allow-all-tools \
  --autopilot
```

Claude/Codex adapters follow equivalent non-interactive flags per vendor docs.

**Optional 9router:** When `router.enabled: true` and `router.inject: true`, skeleton wraps env before exec.

### 7.4 Driver C — `sdk_cursor` (Model 2 — Cursor only)

**Description:** Node ≥ 22.13 wrapper invoking `@cursor/sdk`.

**Package:** `npm install @cursor/sdk` (pinned in `skeleton/drivers/cursor-sdk/package.json`).

**Auth:** `CURSOR_API_KEY` (user or service account from Cursor dashboard). Bills to Cursor plan — not Anthropic/OpenAI API keys.

**Runtime:**

| Mode | Config | Use case |
|------|--------|----------|
| `local` | `cursor.runtime: local`, `local: { cwd: PROJECT_ROOT }` | Default dev/CI on working tree |
| `cloud` | `cursor.runtime: cloud`, repo + branch | Parallel/long runs, disconnected caller |

**Minimal wrapper contract:**

```typescript
// skeleton/drivers/cursor-sdk/run.mjs (conceptual)
import { Agent } from "@cursor/sdk";

const agent = await Agent.create({
  apiKey: process.env.CURSOR_API_KEY,
  model: { id: config.model },
  local: { cwd: process.env.PROJECT_ROOT },
});

const run = await agent.send(stagePrompt);
for await (const event of run.stream) {
  emitToSkeleton(event); // map to agent-chain.log
}
const result = await run.result;
process.exit(result.ok ? 0 : 1);
```

**Not supported:** Cursor CLI as driver; Cursor traffic through 9router.

### 7.5 Driver selection rules

| `execution.driver` | `execution.cli.provider` | Runtime |
|--------------------|--------------------------|---------|
| `router_http` | ignored | Harness → 9router |
| `cli_subscription` | `copilot` | copilot CLI |
| `cli_subscription` | `claude` | claude CLI |
| `cli_subscription` | `codex` | codex CLI |
| `sdk_cursor` | ignored | @cursor/sdk |

**Invalid:** `cli_subscription` + `cli.provider: cursor` → doctor error with fix hint.

### 7.6 Provider × compose × execution matrix (examples)

| Project | `manifest.provider` (compose) | `execution.driver` | `cli.provider` / cursor |
|---------|------------------------------|--------------------|-------------------------|
| Video shorts | `claude` | `cli_subscription` | `copilot` |
| Crypto | `antigravity` | `router_http` | — |
| Stocks | `codex` | `cli_subscription` | `codex` |
| Cursor-native | `cursor` | `sdk_cursor` | `model: composer-2.5` |

### 7.7 Skills resolution (all drivers)

```
FINAL_SKILLS =
    FRAMEWORK_CORE                    # SKELETON_ROOT/framework/skills/*
  + manifest.skills.always            # .ai/skills/*
  + PLAN.task.skills (if specified)
  + STAGE_SKILLS[stage_name]          # e.g. docs-sync on [4]
```

Prompt bodies loaded from `.ai/` markdown directly where possible (token control); composed artifacts supply IDE-facing rules.

### 7.8 Framework agents (skeleton) vs project agents

| Layer | Location | Examples |
|-------|----------|----------|
| Framework pipeline agents | `SKELETON_ROOT/framework/agents/` | task-runner, dto-guardian, merge-reviewer |
| Project agents | `.ai/agents/` | scene-builder, wallet-auditor |

**Resolution:** `resolve_agent(stage, task)`:

1. PLAN task frontmatter: `agent: scene-builder`
2. `manifest.defaults.agent`
3. Framework default for stage
4. Load AGENT.md content from `.ai/agents/{name}/` into prompt

---

## 8. Orchestration pipeline

### 8.1 Scheduling modes

| Mode | Flag | Behavior |
|------|------|----------|
| **Hybrid** | *(default)* | Batch tasks by PLAN §5 dependency graph + file-ownership safety; parallel inside batch, serial across batches |
| **Parallel** | `--parallel` | One worktree per task (subject to `max_parallel_agents`) |
| **Sequential** | `--sequential` | Single branch/session; strict dependency order |

**Removed:** `--mode=1|2|3` — replaced by explicit flags; hybrid is default.

### 8.2 Task selection

| Invocation | Task set |
|------------|----------|
| `skeleton run` | All pending tasks in selected PLAN |
| `skeleton run --full` | Explicit alias for all pending |
| `skeleton run 1 2 3` | Tasks 1, 2, 3 only |
| `skeleton run --tasks 1,2,3` | Same |

**Plan selection:**

| Invocation | Plan |
|------------|------|
| `skeleton run --plan docs/PLAN.md` | Explicit |
| `skeleton run` | Default `manifest.defaults.plan`; if multiple `docs/PLAN*.md`, interactive picker |
| `skeleton plan list` | Non-interactive inventory |

### 8.3 Dependency validation

Default: **`--strict-deps`** — block run if selected tasks depend on incomplete tasks.

Escape: `--force-deps` — log warning, proceed (noted in PR body).

### 8.4 Model routing (heavy task)

| Mode | Heavy model/combo |
|------|-------------------|
| Hybrid | Heaviest task in batch (from §6 complexity → score) → `router.combo` heavy-lite alias |
| Parallel | Heaviest pending → heavy alias |
| Sequential | Single combo alias throughout |

Rotation pool for non-heavy stages: configured in `config/skeleton.yaml` as 9router combo aliases (replaces hardcoded `MODEL_ROTATE_POOL`).

### 8.5 Full pipeline diagram

```
skeleton run [--plan PATH] [task IDs…] [--driver …] [--parallel|--sequential]
        │
        ▼
╔══════════════════════════════════════════════════════════════════╗
║  STAGE −1  Knowledge sync + router check/start if needed          ║
╚══════════════════════════════╤═══════════════════════════════════╝
                               ▼
╔══════════════════════════════════════════════════════════════════╗
║  RESOLVE  plan · tasks · deps · parallel-safe file sets           ║
╚══════════════════════════════╤═══════════════════════════════════╝
                               ▼
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 0  Per task / per parallel track                           ║
║  See §8.6                                                         ║
╚══════════════════════════════╤═══════════════════════════════════╝
                               ▼
╔══════════════════════════════════════════════════════════════════╗
║  [2] Union merge — conflict-resolver, 5 retries (if ≥2 tracks)    ║
║  [3] Post-merge review — merge-reviewer, 5 retries                ║
║  [4] Docs sync — PROGRESS_REPORT if present [advisory]            ║
║  [5] Global validation — 5a, 5b, 5c (§12)                        ║
║  [6] git push + gh pr create                                      ║
╚══════════════════════════════════════════════════════════════════╝
```

### 8.6 Stage [2] skip matrix

| Scenario | [2] Merge | [3]–[6] |
|----------|-----------|---------|
| Single task, in-place | Skip | **Run** |
| Multiple tasks, one branch | Skip | **Run** |
| Multiple parallel worktrees | **Run** | **Run** |
| `--no-auto-merge` | Deferred to `skeleton merge` | Deferred |

### 8.7 Stage 0 — Per-task agent chain (preserved)

Checkpoint: `checkpoint-task-N-pre` (git tag).

| Step | Agent | Max retries | On exceed |
|------|-------|-------------|-----------|
| 1 | task-runner | 5 | rollback |
| 2 | dto-guardian | 5 | rollback |
| 3 | integration | 5 | rollback |
| 4 | security-auditor | 3 | rollback |
| 5 | test-builder | 3 | rollback |
| 6 | protected file check | — | rollback |
| 7 | quality-gates.sh | — | refactor ≤3, then rollback |

**On success:**

- Mark `<!-- ✅ Task N completed -->` in PLAN.md (only allowed PLAN mutation in Stage 0)
- Commit: `feat(task-N): implement <name>`

**Input file:** `.skeleton-dev/TASK_PROMPT.md` generated from:

- `### Task N` section
- Referenced §8 subsections (indexed load — not full PLAN)
- `.ai/prompts/implement-and-review-task.md` template

### 8.8 Stages [2]–[6] detail (unchanged semantics)

| Stage | Agent/tool | Retries | Blocking |
|-------|------------|---------|----------|
| [2] Union merge | conflict-resolver | 5 | Yes |
| [3] Post-merge review | merge-reviewer | 5 | Yes |
| [4] Docs sync | merge-reviewer + docs-sync skill | 1 | **No** (advisory) |
| [5a] Technical gates | quality-gates.sh + refactor | 5 | Yes |
| [5b] Acceptance | acceptance-gates.sh + optional LLM | 5 | Yes |
| [5c] Sufficiency | test-builder (extended) | 5 | Yes |
| [6] PR | `git push` + `gh pr create` | — | Yes |

**Protected paths during merge:** `contracts/`, `database/`, `docs/` — additive-only rules preserved from `run_parallel.sh`.

---

## 9. Agentic loop layers

| Layer | Name | Mechanism | Stop condition |
|-------|------|-----------|----------------|
| **L1** | Turn loop | Inside ExecutionDriver (CLI tools or harness tools) | No more tool calls / stage complete |
| **L2** | Task loop | task-runner → validate → fix → repeat | Task `Validation` exit 0 |
| **L3** | Plan loop | Scheduler runs task batches until PLAN complete | All tasks ✅ |
| **L4** | Goal loop | Optional `--until` + `--max-turns` | Shell expr pass + optional LLM evaluator |

**Budget caps (L4, all layers):** `max_turns`, `max_tokens`, wall-clock timeout — always enforced in `config/skeleton.yaml`.

---

## 10. PLAN.md work contract

### 10.1 Location and discovery

| Path | Priority |
|------|----------|
| `docs/PLAN.md` | Default |
| `docs/PLAN-<feature>.md` | Discovered by glob |
| `manifest.defaults.plan` | Override default |

### 10.2 Required PLAN sections (in order)

Per plan-management / a2a-brainstormer reference:

1. Goal  
2. Architecture Overview  
3. Tech Stack  
4. Project Structure  
5. Implementation Tasks (dependency graph + `### Task N`)  
6. Task Summary table  
7. How to Use This Plan  
8. Deep Knowledge Reference (§8)  

### 10.3 Task section schema

```markdown
### Task N — {Name} <!-- ✅ Task N completed -->

**Goal:** …

**Files to create:**
- `path/file` — description, §8.X refs

**Validation:**
- `command`: expected outcome

**Acceptance criteria:** (optional, recommended)
- user-visible expected behavior

**Prompt context needed:** §8.X, blueprint §Y

**agent:** task-runner (optional override)
```

### 10.4 PLAN parser requirements

**File:** `scripts/plan/plan_parser.py`

| Function | Requirement |
|----------|-------------|
| Index tasks | Line offsets for O(1) section load — do not load 100k+ line file whole |
| Parse §6 table | Complexity, depends-on |
| Parse §5 graph | Dependency edges |
| File ownership | Union of `Files to create` per task |
| Completion | HTML comment markers |
| Parallel safety | No overlapping `Files to create` between concurrent tasks |
| Export JSON | `.skeleton-dev/plan-index.json` for shell orchestrator |

### 10.5 Phase → task migration map

| Legacy | New |
|--------|-----|
| `config/phases.yaml` phase N | `### Task N` |
| `PHASE_TASK.md` | `.skeleton-dev/TASK_PROMPT.md` |
| `phase-builder` | `task-runner` |
| `track/phase-N` | `track/task-N` |
| `.parallel-dev/` | `.skeleton-dev/` |
| `run_parallel.sh start 1 2 3` | `skeleton run 1 2 3` |

**Deprecation:** `phases.yaml` adapter reads PLAN §6 for one release, then remove.

---

## 11. Testing strategy (T1, T2, T3)

### 11.1 Rationale

**Both per-task and post-integration testing are required** for quality:

- T1 catches isolated task errors before merge cost.
- T3 catches cross-task integration, E2E, and PLAN-level intent.

### 11.2 Layers

| Layer | When | What | Driver impact |
|-------|------|------|---------------|
| **T1** | After each task in Stage 0 | PLAN `Validation` + `quality-gates.sh` | None — always runs |
| **T2** | End of Stage 0 batch (optional) | Affected-tests smoke on same branch | Config `testing.t2_enabled` |
| **T3** | Stage 5a after merge | Full backend + frontend suite | None — always runs |

### 11.3 Backend vs frontend hooks

Generated on `skeleton integrate` (project-aware):

| Hook | When |
|------|------|
| `scripts/hooks/quality-gates.sh` | T1 end, 5a |
| `scripts/hooks/acceptance-gates.sh` | 5b orchestrator |
| `scripts/hooks/acceptance-gates-backend.sh` | If backend detected |
| `scripts/hooks/acceptance-gates-frontend.sh` | If frontend detected (Playwright/Cypress template) |

`skeleton hooks regenerate` re-detects stack after structure change.

---

## 12. Global validation and acceptance (5a, 5b, 5c)

### 12.1 Stage 5 flow

```
[5a] Technical gates (T3)
  │  quality-gates.sh — full repo
  │  fail → refactor (≤5) → retry 5a
  ▼
[5b] Acceptance — intent vs expected
  │  Hard: acceptance-gates.sh, PLAN criteria, E2E
  │  Soft: LLM evaluator (config acceptance.llm_evaluator: true)
  │  fail → feedback router (§12.3)
  ▼
[5c] Test sufficiency — extended test-builder
  │  Verdict: SUFFICIENT | NEEDS_TESTS | NEEDS_FIX
  │  fail → feedback router
  ▼
PASS → [6] PR
```

### 12.2 LLM acceptance (explicit non-determinism)

Soft LLM layers in 5b/5c are **intentionally non-deterministic**. Orchestration determinism applies to:

- Task scheduling order given same PLAN index
- Script gate results
- Retry bounds and state transitions

### 12.3 Feedback router (5b/5c failure)

| Failure class | Route to | Then |
|---------------|----------|------|
| Lint/build/unit | refactor | 5a |
| Wrong behavior, small scope | refactor | 5a → 5b |
| Missing tests | test-builder | 5a → 5c |
| Wrong feature / task scope | task-runner on Task N | Stage 0 for N → re-enter [2]–[6] |
| Frontend flow broken | task-runner on owning task + E2E | same |

**Max cycles:** `acceptance.max_retries` (default 5) — then run FAILED, no PR.

---

## 13. Configuration

### 13.1 `.ai/manifest.yaml` (canonical identity)

```yaml
version: "2.0"
project:
  name: shorts-gen
  domain: media
  description: Short-form video generation pipeline
  tags: [ffmpeg, scene-split]

defaults:
  provider: claude          # ars compose --target
  agent: task-runner
  plan: docs/PLAN.md

skills:
  always:
    - plan-management
    - scene-pipeline
    - ffmpeg-encoding

knowledge:
  import_policy: merge_on_stale   # never | on_missing | merge_on_stale | always
```

### 13.2 `config/skeleton.yaml` (runtime only)

```yaml
version: "1"

execution:
  driver: cli_subscription       # router_http | cli_subscription | sdk_cursor
  cli:
    provider: copilot            # copilot | claude | codex — NOT cursor
  cursor:
    runtime: local                 # local | cloud
    model: composer-2.5
    # api_key from env CURSOR_API_KEY only

  mode: hybrid                     # hybrid | parallel | sequential
  max_parallel_agents: 3

router:
  driver: nine_router              # nine_router | openai_compatible | mock
  enabled: true
  auto_start: true
  endpoint: http://localhost:20128/v1
  api_key_env: NINE_ROUTER_KEY
  combo: project-default
  inject: true
  quota_retry:
    enabled: true
    interval: 1h
    max_total_wait: 24h
    jitter: 5m
    on_exhausted: sleep_and_retry   # sleep_and_retry | fail_fast | next_combo

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
  skip: false                    # skeleton run --skip-acceptance sets true

integration:
  pr_mode: per_run               # per_run | manual | single_branch
  auto_merge: true               # --no-auto-merge negates

testing:
  t2_enabled: false
  strict_deps: true

hooks:
  quality: scripts/hooks/quality-gates.sh
  acceptance: scripts/hooks/acceptance-gates.sh
  acceptance_backend: scripts/hooks/acceptance-gates-backend.sh
  acceptance_frontend: scripts/hooks/acceptance-gates-frontend.sh

logging:
  dir: .skeleton-dev/logs
```

---

## 14. CLI reference

### 14.1 Integration and knowledge

| Command | Description |
|---------|-------------|
| `skeleton integrate` | Scaffold `.ai/`, import legacy, compose, router install/oauth, hooks, doctor |
| `skeleton upgrade` | Framework files only (existing behavior, enhanced) |
| `skeleton sync [--import] [--compose]` | Force Stage −1 components |
| `skeleton knowledge status` | .ai/ vs legacy vs compose.stamp staleness |
| `skeleton context` | Domain, provider, driver, pending tasks, agents/skills counts |
| `skeleton doctor` | ars validate + router + hooks + node version (Cursor SDK) |
| `skeleton plan list` | List PLAN files and pending counts |

### 14.2 Router

| Command | Description |
|---------|-------------|
| `skeleton router install` | Install pinned 9router |
| `skeleton router start` | Start daemon |
| `skeleton router stop` | Stop daemon |
| `skeleton router status` | Process status |
| `skeleton router check` | Health check exit code |
| `skeleton router oauth` | Provider connection guidance |
| `skeleton router combos` | List/set combo |

### 14.3 Execution

| Command | Description |
|---------|-------------|
| `skeleton run [tasks…]` | Run pending or listed tasks |
| `skeleton run --full` | All pending tasks |
| `skeleton run --plan PATH` | Explicit PLAN |
| `skeleton run --tasks 1,2,3` | Explicit task list |
| `skeleton run --driver router_http\|cli_subscription\|sdk_cursor` | Override driver |
| `skeleton run --parallel` | Full parallel mode |
| `skeleton run --sequential` | Sequential mode |
| `skeleton run --no-auto-merge` | Stop after Stage 0 |
| `skeleton run --skip-acceptance` | Skip 5b/5c (debug) |
| `skeleton run --acceptance-only` | Re-run 5b/5c on current branch |
| `skeleton run --force-deps` | Bypass dependency check |
| `skeleton goal "…" --until EXPR` | L4 macro loop |
| `skeleton merge` | Manual [2]–[6] |
| `skeleton status` | Task + 5a/5b/5c substages |
| `skeleton cleanup` | Worktrees, branches, state |
| `skeleton gates` | quality-gates only |
| `skeleton hooks regenerate` | Re-detect language hooks |

### 14.4 Global flags

| Flag | Description |
|------|-------------|
| `--dir PATH` | Project root (default cwd) |
| `--no-interactive` | CI: fail if plan ambiguous |

---

## 15. Multi-project operation

### 15.1 Model

skeleton CLI is **installed once** (global or cloned). Each project is **self-contained**:

- `.ai/manifest.yaml` — domain identity  
- `.ai/skills/`, `.ai/agents/` — domain knowledge  
- `docs/PLAN.md` — work contract  
- `config/skeleton.yaml` — runtime  

### 15.2 Examples

```bash
cd ~/shorts-gen    && skeleton run           # media / claude compose / copilot CLI
cd ~/crypto-wallet && skeleton run 3 4      # antigravity compose / router_http
cd ~/stock-analyzer && skeleton run --driver sdk_cursor
```

### 15.3 Framework skills path

```
SKELETON_ROOT/framework/skills/   → always loaded
PROJECT_ROOT/.ai/skills/          → manifest.skills.always + task skills
```

Never assume `./github/skills` is framework — that is composed project output.

---

## 16. State, logs, and observability

### 16.1 Directory layout

```
.skeleton-dev/
  compose.stamp              # sha256 of .ai/
  plan-index.json            # parser output
  run-status.json            # per-task + pipeline substates
  events.jsonl               # lifecycle events (UI later)
  state.json                 # mode, branches, integration_branch
  logs/
    agent-chain.log
    task-3-task-runner-1.log
    global-validation-5a.log
    global-validation-5b.log
    acceptance-sufficiency-5c.log
    post-merge-review-1.log
    docs-sync.log
  TASK_PROMPT.md             # current task prompt (generated)
```

### 16.2 `run-status.json` pipeline rows

Post-phase rows include substages:

- `post-merge-review`
- `docs-sync`
- `global-validation-5a`
- `global-validation-5b`
- `global-validation-5c`
- `remediation`
- `pr-create`

### 16.3 `events.jsonl` schema (minimal)

```json
{"ts":"…","type":"task_start","task":3,"driver":"cli_subscription"}
{"ts":"…","type":"agent_end","agent":"task-runner","task":3,"exit":0}
{"ts":"…","type":"quota_wait","duration":"1h","combo":"project-default"}
{"ts":"…","type":"acceptance_fail","stage":"5b","route":"test-builder"}
```

---

## 17. Documentation and protected paths policy

| Path | Stage 0 agents | Stage [4] docs-sync |
|------|----------------|---------------------|
| `docs/PLAN.md` | Only `<!-- ✅ Task N -->` markers | Read-only |
| `docs/PROGRESS_REPORT.md` | Read-only | **Update if file exists** |
| `docs/architecture.md` | Read-only | Advisory drift only |
| `contracts/` | Additive only | — |
| `database/` | Policy per PLAN (typically restricted) | — |

---

## 18. Repository layout and script migration

### 18.1 Target skeleton-parallel layout

```
skeleton-parallel/
  bin/skeleton
  framework/
    agents/
    skills/
  router/
    wrap.sh
    docker-compose.yml
    9router-pin.json
  drivers/
    router_http/
    cli/
      copilot.sh
      claude.sh
      codex.sh
    cursor-sdk/
      package.json
      run.mjs
    registry.yaml
  templates/
    hooks/{go,python,typescript,fullstack}/
  scripts/
    skeleton-run.sh
    run_parallel.sh              # DEPRECATED shim
    knowledge/
      sync.sh
      detect_legacy.py
      import.sh
      compose.sh
    plan/
      plan_parser.py
      plan_validate.py
    pipeline/
      agent_pipeline.sh
      modes.sh
      task_executor.sh
      integration.sh
      global_validation.sh
      acceptance.sh
      pr.sh
    lib/
      common.sh
      copilot.sh
      router.sh
      checkpoint.sh
      agent.sh
      hooks.sh
      state.sh
      policy.sh
  config/
    skeleton.yaml.template
  docs/
    specs/
      2026-06-27-agentic-loop-cli-design.md
```

### 18.2 Migration phases

| Phase | Deliverable | Risk |
|-------|-------------|------|
| **1** | Extract `run_parallel.sh` → `lib/` + `pipeline/`; shim unchanged behavior | Low |
| **2** | `plan_parser.py`; phase→task rename; `.skeleton-dev/` | Medium |
| **3** | Stage −1, drivers, router wrap, hooks templates, `skeleton run` | High |

**Rule:** Phase 1 must pass existing parallel dev workflows before Phase 2.

---

## 19. ExecutionDriver interface

### 19.1 Shell contract

```bash
# drivers/registry.yaml resolves to:
run_driver() {
  local driver="$1"       # router_http | cli_subscription | sdk_cursor
  local stage="$2"        # task-runner | dto-guardian | ...
  local work_dir="$3"
  local prompt_file="$4"  # path to prompt markdown
  local model="$5"        # combo alias or model id
  local log_file="$6"
  # returns exit code; streams to log_file
}
```

### 19.2 Required capabilities

| Capability | router_http | cli_subscription | sdk_cursor |
|------------|-------------|------------------|------------|
| Non-interactive | Yes | Yes | Yes |
| Workspace confined to PROJECT_ROOT | Yes | Yes | Yes |
| Structured exit codes | Yes | Yes | Yes |
| Token/quota error classification | Yes | Yes | Yes |
| Streaming log | Yes | Yes | Yes |

### 19.3 Stage prompt template variables

| Variable | Source |
|----------|--------|
| `{{TASK_NUMBER}}` | Current task |
| `{{PLAN_PATH}}` | Active plan |
| `{{SKILLS_CSV}}` | Resolved skill list |
| `{{WORKSPACE_CONSTRAINT}}` | Fixed policy string |
| `{{STAGE_NAME}}` | Pipeline stage |

---

## 20. Failure handling and quota retry

### 20.1 Quota exhaustion (9router paths)

1. Driver receives 429 / quota / combo exhausted from 9router.  
2. If 9router can switch combo member → transparent retry.  
3. If all members exhausted → skeleton `quota_retry`: sleep `interval`, retry same stage.  
4. If `max_total_wait` exceeded → fail run with actionable message (dashboard link).

### 20.2 Quota exhaustion (Cursor SDK)

Same `quota_retry` policy at driver level — no 9router involved. Map Cursor rate-limit errors to retry class.

### 20.3 Checkpoint rollback

Unchanged semantics from `run_parallel.sh`:

- Tag before task pipeline: `checkpoint-task-N-pre`
- On retry exceed: `git reset --hard` to tag
- Log to `agent-chain.log`

---

## 21. Migration from run_parallel.sh

### 21.1 Shim behavior

```bash
# scripts/run_parallel.sh (deprecated)
echo "WARN: use 'skeleton run' instead" >&2
exec skeleton run "$@"
# map: start --mode=1 → --parallel, --mode=2 → --sequential
```

### 21.2 Environment variable mapping

| Legacy env | New config |
|------------|------------|
| `MODEL_HEAVY` | `router.combos.heavy` |
| `MODEL_HEAVY_LITE` | `router.combos.heavy_lite` |
| `MAX_PARALLEL_AGENTS` | `execution.max_parallel_agents` |
| `COPILOT_MODEL` | combo alias or `execution.cli.model` |

---

## 22. Release scope (Must / Should / Defer)

### 22.1 Must — v1.0.0

- [ ] `skeleton run` with PLAN parser and task selection (full + partial)
- [ ] Hybrid default; `--parallel` / `--sequential`
- [ ] Stage 0 agent pipeline (extracted, task-named)
- [ ] Stages [2]–[6] preserved
- [ ] T1 + T3 testing; 5a hard gates
- [ ] Stage −1 compose-if-stale + combination import
- [ ] `.ai/manifest.yaml` + `config/skeleton.yaml` split
- [ ] Wrapped 9router: install/start/check/oauth
- [ ] Driver `router_http`
- [ ] Driver `cli_subscription` (copilot first; claude/codex adapters)
- [ ] Driver `sdk_cursor` (local runtime minimum)
- [ ] `skeleton integrate` + project-aware hooks generation
- [ ] `run_parallel.sh` deprecation shim
- [ ] PROGRESS_REPORT update in [4] when present
- [ ] Script migration phase 1 complete

### 22.2 Should — v1.1.0

- [ ] 5b acceptance hooks (backend + frontend templates)
- [ ] 5b soft LLM + 5c sufficiency (extended test-builder)
- [ ] `router.inject` for claude/codex CLIs
- [ ] `sdk_cursor` cloud runtime
- [ ] `events.jsonl` + enhanced `skeleton status`
- [ ] Script migration phases 2–3

### 22.3 Defer — v1.2+

- [ ] UI dashboard
- [ ] IDE-native / dual surface (parking lot B/C)
- [ ] `skeleton brainstorm`
- [ ] A2A protocol runtime
- [ ] Workspace registry `~/.config/skeleton/workspaces.yaml`
- [ ] Antigravity CLI driver

---

## 23. Future parking lot

| Item | Notes |
|------|-------|
| UI over `events.jsonl` | Read-only dashboard |
| Parking lot B | ARES-composed IDE hooks /goal |
| Parking lot C | Dual `agent-loop.yaml` CLI + IDE |
| a2a-brainstormer | PLAN generator command |
| Best-of-N runners | Parallel driver experiments |

---

## 24. Self-review checklist

| Check | Status |
|-------|--------|
| No TBD placeholders in core flows | Pass |
| Cursor SDK ≠ 9router stated explicitly | Pass |
| Copilot/Claude/Codex = CLI; Cursor = SDK only | Pass |
| Dual drivers v1.0 documented | Pass |
| Stage −1 not full import every run | Pass |
| manifest vs skeleton.yaml split | Pass |
| docs/ PLAN vs PROGRESS_REPORT policy | Pass |
| T1 + T3 both required | Pass |
| 5b soft LLM kept per user decision | Pass |
| Per-task + full pipeline [3]–[6] | Pass |
| Scope split Must/Should/Defer | Pass |
| Internal contradictions | None found |
| Scope creep bounded by defer list | Pass |

---

## Appendix A — `skeleton integrate` checklist

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

## Appendix B — References

- ARES: https://github.com/okfriansyah-moh/ares  
- 9router: https://github.com/decolua/9router  
- a2a-brainstormer PLAN format: `plan-management` skill reference  
- Cursor SDK: https://cursor.com/docs/sdk/typescript  
- Claude agent loop: https://code.claude.com/docs/en/agent-sdk/agent-loop  
- Current orchestrator: `scripts/run_parallel.sh`  
- Parallel dev doc: `docs/PARALLEL_DEV.md`  

---

## 25. Lifecycle commands (init, doctor, autoskills)

The `skeleton` binary is **one CLI** with two command families. **Lifecycle** commands scaffold and prepare a project; **execution** commands run the agentic loop. Lifecycle commands are **maintained in v1.0** and enhanced — not replaced by `skeleton run`.

### 25.1 Command families

```
┌─────────────────────────────────────────────────────────────────┐
│  LIFECYCLE (maintained + enhanced in v1)                          │
│  init · upgrade · integrate · doctor · autoskills · sync · add    │
│  list · hooks regenerate · knowledge status · context             │
│  → scaffold, validate, domain skills, ARES sync                   │
└────────────────────────────┬────────────────────────────────────┘
                             │ project ready (PLAN.md exists)
┌────────────────────────────▼────────────────────────────────────┐
│  EXECUTION (agentic loop — v1 implementation)                   │
│  run · merge · goal · router * · plan list · status · cleanup     │
│  → PLAN tasks, drivers, 9router, pipeline Stage −1–[6]           │
└─────────────────────────────────────────────────────────────────┘
```

### 25.2 Greenfield workflow (new project)

```bash
export PATH="$PWD/skeleton-parallel/bin:$PATH"

skeleton init go --name=my-service
cd my-service

skeleton doctor
skeleton autoskills

# Produce docs/PLAN.md (brainstormer, manual, or roadmap conversion)
# … architecture prompts as needed …

skeleton run --full          # v1 — replaces run_parallel.sh
```

| Step | Command | v1 behavior |
|------|---------|-------------|
| Scaffold | `skeleton init` | Language template + framework files; **adds** `.ai/`, `config/skeleton.yaml`, hook templates, `docs/PLAN.md` stub |
| Validate | `skeleton doctor` | Framework + **`.ai/`**, `ars validate`, router/driver deps, hooks, PLAN presence |
| Domain skills | `skeleton autoskills` | Installs into **`.ai/skills/`** (primary); runs compose refresh |
| Execute | `skeleton run` | Stage −1 → Stage 0 → [2]–[6] |

Optional Copilot agent validation on `init` / `doctor` / `autoskills` is **retained** (`--no-agent`, `SKIP_AGENT=true`).

### 25.3 Brownfield workflow (existing repository)

```bash
cd existing-project
skeleton integrate           # v1 — import legacy → .ai/ → compose → router → hooks
skeleton doctor
skeleton autoskills
skeleton run 1 2 3
```

| Path | Entry | Notes |
|------|-------|-------|
| Framework files only | `skeleton upgrade` | Replace/Hybrid/Skip (existing behavior) |
| Full agentic adoption | `skeleton integrate` | upgrade + ARES + router + hooks |

### 25.4 Lifecycle command reference

| Command | Purpose | Agent spawn (optional) |
|---------|---------|------------------------|
| `init` | New project from language template | Foreground validation |
| `upgrade` | Refresh framework files from skeleton-parallel | Foreground validation |
| `integrate` | Brownfield: `.ai/`, import, compose, router, hooks | Foreground validation |
| `doctor` | Health check; static + optional auto-fix | FG if issues, BG if clean |
| `autoskills` | Detect stack; install/merge domain skills | Analysis + generation agents |
| `sync` | Force Stage −1 (import and/or compose) | Background validation |
| `add` | Add skill or agent | Background validation |
| `list` | List templates, skills, agents | — |
| `hooks regenerate` | Re-detect language; rewrite hook templates | — |
| `context` | Print domain, provider, driver, pending tasks | — |
| `knowledge status` | `.ai/` vs legacy vs compose.stamp | — |

### 25.5 Lifecycle vs execution: what changes in v1

| Area | Today | v1 target |
|------|-------|-----------|
| Skills install path | `.github/skills/` | **`.ai/skills/`** (composed to provider) |
| Work contract | `config/phases.yaml` + `run_parallel.sh` | **`docs/PLAN.md`** + **`skeleton run`** |
| State directory | `.parallel-dev/` | **`.skeleton-dev/`** (shim reads old path one release) |
| Validation agent | Copilot CLI only | Copilot for lifecycle; **pluggable drivers** for `run` |
| Post-scaffold config | `phases.yaml` | **`config/skeleton.yaml`** (runtime) + **`.ai/manifest.yaml`** (identity) |

### 25.6 `autoskills` and multi-project domain knowledge

`skeleton autoskills` remains the tool for **project-specific** skills (video, crypto, stocks, etc.):

1. Detect language and features from repo files.
2. Recommend/install framework-aligned domain skills.
3. Write skills under **`.ai/skills/<name>/SKILL.md`**.
4. Trigger `ars compose` (or Stage −1 on next `run`).

Framework skills stay in **`SKELETON_ROOT/framework/skills/`** — not copied per project.

### 25.7 Prerequisites after v1

| Requirement | Lifecycle | Execution |
|-------------|-----------|-----------|
| `ars` CLI | `integrate`, `sync`, `doctor` | Stage −1 on `run` |
| 9router | `integrate`, `router *` | When `router_http` or `cli` + `router.enabled` |
| Copilot CLI | Optional on lifecycle commands | When `cli.provider: copilot` |
| Claude / Codex CLI | — | When respective `cli.provider` |
| Node ≥ 22.13 | — | When `driver: sdk_cursor` |
| `gh` | — | Stage [6] PR |

---

*End of specification.*
