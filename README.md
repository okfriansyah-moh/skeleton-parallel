# Skeleton Parallel

> Provider-agnostic agentic loop CLI for building deterministic pipeline systems with AI-assisted parallel development. One `docs/PLAN.md` → Copilot, Claude, Codex, Cursor — any driver, any language.
![Skeleton Parallel infographic](assets/skeleton-parallel-infographics.png)

[![License](https://img.shields.io/github/license/okfriansyah-moh/skeleton-parallel)](LICENSE)
[![Release](https://img.shields.io/github/v/release/okfriansyah-moh/skeleton-parallel)](https://github.com/okfriansyah-moh/skeleton-parallel/releases/latest)

**Topics:** `ai` · `agentic-loop` · `parallel-development` · `cli` · `github-copilot` · `claude-code` · `cursor` · `codex` · `developer-tools` · `skeleton` · `golang` · `python` · `typescript` · `bash` · `open-source`

**Latest release:** [Download latest](https://github.com/okfriansyah-moh/skeleton-parallel/releases/latest)

**→ [Installation](#installation)** · [Quick Start](#quick-start) · [Commands](#command-reference) · [Pipeline](#pipeline) · [Drivers](#driver-support)

skeleton-parallel lets a team define work once in `docs/PLAN.md`, then execute it autonomously through any AI provider — GitHub Copilot, Claude Code, Cursor, or OpenAI Codex — with a full six-stage validation pipeline and automatic rollback on failure.

The golden rule: every task runs through the same pipeline regardless of which AI driver is active. Switch providers by changing one line in `config/skeleton.yaml`.

```mermaid
flowchart LR
  subgraph plan["Where work is defined"]
    P["docs/PLAN.md"]
  end

  subgraph drivers["Execution drivers"]
    D1["router_http → 9router"]
    D2["cli_subscription → copilot / claude / codex"]
    D3["sdk_cursor → Cursor agent runtime"]
  end

  subgraph pipeline["Autonomous pipeline"]
    S1["Stage −1  Knowledge sync"]
    S2["Stage  0  7-step agent chain per task"]
    S3["[2]–[3]  Union merge + review"]
    S4["[5a]–[5c]  Quality + acceptance gates"]
    S5["[6]  git push + gh pr create"]
  end

  P -->|skeleton run| S1
  S1 --> S2
  S2 -->|router_http| D1
  S2 -->|cli_subscription| D2
  S2 -->|sdk_cursor| D3
  S2 --> S3
  S3 --> S4
  S4 --> S5
```

## When to use skeleton-parallel

Define work in `docs/PLAN.md`. Let `skeleton run` execute it end-to-end through any AI provider.

### Scenarios

**0. Zero to running pipeline — design → plan → execute** · `a2a-brainstorm` + `skeleton plan` + `skeleton run`

skeleton-parallel's natural entry point is a structured architecture document and a task plan. The recommended design-to-execution loop uses two tools in sequence:

| Tool | Phase | Output |
|------|-------|--------|
| [a2a-brainstorm](https://github.com/okfriansyah-moh/a2a-brainstorm) | Design | `architecture.md`, `plan.md`, `readme.md` via multi-agent convergence |
| `skeleton plan --from=plan.md` | Bridge | `docs/PLAN.md` enriched with task IDs, deps, file ownership, acceptance criteria |
| `skeleton run --full` | Execution | Full 6-stage agentic pipeline through quality gates → PR |

**Real example: idx-signal-system** — self-hosted IDX stock screening, 8 build phases (data layer, scoring engine, backtest, flow/news/sector, Tier B scout, delivery, calibration).

```sh
# ── Step 1: Start 9router ─────────────────────────────────────────────────────
skeleton router install   # npm install -g 9router (github.com/decolua/9router)
skeleton router start     # start daemon — http://localhost:20128/dashboard
skeleton router status    # verify: Running: yes, Health: OK

# ── Step 2: Auth check ────────────────────────────────────────────────────────
cd /path/to/idx-signals-systems
skeleton auth --provider=9router   # verify daemon is up before any agent work

# ── Step 3: Scaffold Python backend ──────────────────────────────────────────
# Additive — never touches existing docs/ or other directories
skeleton init python --role=backend --root=backend/ --name=idx-signals-system
skeleton init python --role=mcp-server --root=mcp-server/ --name=idx-signals-mcp

# ── Step 4: Wire skeleton at project root ─────────────────────────────────────
skeleton integrate
# → creates .ai/manifest.yaml, config/skeleton.yaml, scripts/hooks/

# ── Step 5: Configure 9router driver ─────────────────────────────────────────
# Edit config/skeleton.yaml:
#   execution:
#     driver: router_http
#   router:
#     combo: project-default

# Open http://localhost:20128/dashboard → Connections → add Claude → copy token.
# Create router/inject-env.sh (chmod 600, never commit):
#   export ANTHROPIC_BASE_URL="http://localhost:20128/v1"
#   export ANTHROPIC_API_KEY="<token-from-dashboard>"

skeleton router health              # confirm token is accepted
skeleton auth --provider=9router    # full pre-flight pass

# ── Step 6: Enrich PLAN.md for skeleton execution ─────────────────────────────
# docs/PLAN.md already exists from a2a-brainstorm — enrich it with task IDs,
# dependency chain, file ownership, and acceptance criteria checkboxes.
skeleton plan --from=docs/PLAN.md
# → reads docs/PLAN.md, spawns enrichment agent via 9router
# → adds T-001…T-008 IDs, Depends:, Files:, Acceptance: checkboxes
# → rewrites docs/PLAN.md in skeleton execution format

# ── Step 7: Validate everything ───────────────────────────────────────────────
skeleton doctor
# → ✓ .ai/manifest.yaml, config/skeleton.yaml, docs/PLAN.md
# → ✓ driver: router_http → 9router health OK
# → ✓ 8 tasks found in docs/PLAN.md
# → ✓ scripts/hooks/quality-gates.sh

# ── Step 8: Dry run ───────────────────────────────────────────────────────────
skeleton run --dry-run    # preview full execution plan without touching code

# ── Step 9: Execute ───────────────────────────────────────────────────────────
skeleton run 1              # T-001: market_data layer
skeleton run 2              # T-002: scoring engine (technicals)
skeleton run 3              # T-003: backtest runner
skeleton run --parallel 4 5 # T-004 & T-005 in parallel worktrees
skeleton run 6              # T-006: Tier B scout + promotion
skeleton run 7              # T-007: delivery + scheduler
skeleton run 8              # T-008: calibration + Telegram approval
skeleton run --full         # or run all 8 phases end-to-end

# ── When done ─────────────────────────────────────────────────────────────────
skeleton router stop
```

The 8 tasks generated for idx-signal-system:

| Task | Phase | Module | Key Files |
|------|-------|--------|-----------|
| T-001 | Data layer | `market_data` | `backend/modules/market_data/fetchers/`, `repository.py` |
| T-002 | Scoring engine (technicals) | `scoring` | `backend/modules/scoring/technicals.py`, `support_resistance.py` |
| T-003 | Backtest runner | `backtest` | `backend/modules/backtest/service.py`, `run_backtest_cli.py` |
| T-004 | Flow + corp actions + sector caps | `scoring` (extend) | `backend/modules/scoring/flow.py`, `sector_cap.py` |
| T-005 | News/LLM tagging | `news_intelligence` | `backend/modules/news_intelligence/providers/`, `service.py` |
| T-006 | Tier B scout + promotion | `universe` | `backend/modules/universe/liquidity_ranking.py`, `service.py` |
| T-007 | Delivery + scheduler | `delivery`, `jobs/` | `backend/modules/delivery/telegram_bot.py`, `jobs/run_morning.py`, `scheduler/` |
| T-008 | Calibration + Telegram approval | `calibration` | `backend/modules/calibration/service.py`, `telegram_approval.py` |

**No a2a session yet?** Generate from an architecture doc directly:

```sh
# If you have docs/architecture.md but no a2a plan:
skeleton plan --source=docs/architecture.md
# Single-agent generation — good starting point, less architectural depth than a2a
```

```sh
# skeleton plan flags
skeleton plan                                  # auto-detect: a2a plan first, then arch doc
skeleton plan --from=docs/plan.md              # import a2a-brainstorm output (recommended)
skeleton plan --source=docs/architecture.md    # generate without a2a
skeleton plan --from=docs/plan.md --dir=../x   # different project directory
skeleton plan --dry-run                        # show what would run, skip agent + file write
```

**1. Start a new project from scratch** · `skeleton init`

Scaffold a language-specific project with modular monolith architecture, `.ai/` knowledge, config, and hooks on day one.

```sh
skeleton init go --name=my-service          # Go
skeleton init python --name=my-pipeline     # Python
skeleton init typescript --name=my-app      # TypeScript
skeleton init java --name=my-backend        # Java
skeleton init rust --name=my-lib            # Rust
skeleton init nodejs --name=my-api          # Node.js
```

**1b. Scaffold into a planned multi-role architecture** · `skeleton init --role`

Already have a `docs/architecture.md` with top-level service directories planned? `skeleton init` reads it and acts as an **additive generator** — placing only tooling files, never overwriting your planned structure.

```
# docs/architecture.md already exists and defines:
idx-signal-system/
├── backend/
│   ├── modules/
│   ├── shared/
│   └── tests/
├── frontend/
└── mcp-server/
```

```sh
# Add Python tooling under backend/ — skips app/, contracts/, database/
# because backend/ is architecture-declared
skeleton init python --role=backend --root=backend/

# Add TypeScript tooling under frontend/
skeleton init typescript --role=frontend --root=frontend/

# Add another Python service under mcp-server/
skeleton init python --role=mcp-server --root=mcp-server/
```

Each call places only tooling files (`pyproject.toml`, `requirements.txt`, `.gitignore`, `config/config.yaml`) and never imposes the template's source structure on directories your architecture already owns. A `.skeleton/layout.yaml` manifest is created at the project root recording each role.

```yaml
# .skeleton/layout.yaml — auto-generated, tracks multi-role layout
version: "1.0"
merge_policy: respect-existing
architecture_source: docs/architecture.md
roles:
  backend:
    language: python
    root: backend/
    status: active
  frontend:
    language: typescript
    root: frontend/
    status: active
```

**Merge modes** (auto-detected, or override with `--mode`):

| Mode | When used | Behavior |
|------|-----------|----------|
| `create` | Fresh empty directory | Full scaffold |
| `overlay` | Existing dir, no architecture file | Fill missing files only |
| `respect-existing` | `architecture.md` found + role set | Tooling only; structure dirs skipped |

**2. Execute tasks through any AI provider** · `skeleton run`

Define tasks in `docs/PLAN.md`, then run the full pipeline — all tasks, one task, or a subset.

```sh
skeleton run --full          # all pending tasks, hybrid mode
skeleton run 1 2 3           # specific task IDs
skeleton run --parallel 2 3 4    # tasks in parallel worktrees (max speed)
skeleton run --sequential 1 2 3  # strict dependency order, single branch
skeleton run --driver cli_subscription --full  # override driver at runtime
```

**3. Switch AI providers without changing anything else** · `config/skeleton.yaml`

Change one line. The PLAN, hooks, pipeline stages, and all commands stay identical.

```sh
# config/skeleton.yaml:
#   execution:
#     driver: cli_subscription
#     cli:
#       provider: claude   ← change from: copilot | codex | cursor

skeleton run --full   # same command, different provider
```

**4. Preview execution before running** · `skeleton run --dry-run`

Print the full execution plan — tasks, deps, file sets, driver — without invoking any agents or touching git.

```sh
skeleton run --dry-run
skeleton run --dry-run --plan docs/PLAN.md 1 2 3
skeleton run --dry-run --parallel
```

**5. Set up 9router for multi-provider routing** · `skeleton router`

9router is a local daemon that proxies agent calls through a single OpenAI-compatible endpoint, enabling quota rotation, provider fallback, and OAuth token management. Required only when `driver: router_http` in `config/skeleton.yaml`.

```sh
skeleton router install   # npm install -g 9router (github.com/decolua/9router)
skeleton router start     # start daemon on localhost:20128
skeleton router status    # verify: Running: yes, Health: OK
skeleton router oauth     # print OAuth setup guide for each provider
```

After `start`, open `http://localhost:20128/dashboard` → **Connections** → add your provider (Claude, Copilot, Codex) → copy the token into `router/inject-env.sh`:

```bash
# router/inject-env.sh  (chmod 600, never commit)
export ANTHROPIC_BASE_URL="http://localhost:20128/v1"
export ANTHROPIC_API_KEY="<your-key>"
```

Then set `driver: router_http` in `config/skeleton.yaml`:

```yaml
execution:
  driver: router_http
router:
  combo: project-default   # combo configured in 9router dashboard
```

```sh
skeleton router health    # confirm the daemon is responding
skeleton router stop      # stop daemon when done
```

Skip this step entirely if using `driver: cli_subscription` (claude/copilot/codex CLI direct — no daemon needed).

**6. Onboard an existing repo** · `skeleton integrate`

Your repo already has `.github/copilot-instructions.md`, agents, or hooks. Import everything into `.ai/`, wire the router, and regenerate hooks.

```sh
cd existing-repo
skeleton integrate           # runs full Appendix A checklist
skeleton integrate --dir=./path/to/repo
```

**7. Validate project health** · `skeleton doctor`

Provider-agnostic health check. Validates `.ai/manifest.yaml` (ARES canonical source), `config/skeleton.yaml`, skills/agents from `.ai/` (`.github/` as legacy fallback), pipeline infra, and the harness file for your configured provider (Copilot → `.github/copilot-instructions.md`, Claude → `CLAUDE.md`, Codex → `AGENTS.md`, Cursor → `.cursor/rules/`).

```sh
skeleton doctor              # checks current directory
skeleton doctor --dir=../my-project
```

**8. Upgrade an existing project** · `skeleton upgrade`

Pull the latest framework files (scripts, templates, agents) into a project without overwriting your customizations.

```sh
skeleton upgrade                        # auto-detect mode
skeleton upgrade --mode=hybrid          # merge new + keep custom
skeleton upgrade --mode=replace         # full replacement
skeleton upgrade --dir=../my-project --no-agent
```

**9. Auto-detect stack and install matching skills** · `skeleton autoskills`

Scans the project's language, frameworks, and tools, then installs the matching skill modules into `.ai/skills/` (ARES canonical source).

```sh
skeleton autoskills                     # current directory
skeleton autoskills --dir=../my-project
skeleton autoskills --dry-run           # preview only
skeleton autoskills -y                  # skip confirmation prompts
```

**10. Add a skill or agent to a project** · `skeleton add`

Install a single named skill or agent from the skeleton-parallel registry into `.ai/skills/` or `.ai/agents/` (ARES canonical source). After adding, run `ars compose --target <provider>` to update your provider harness.

```sh
skeleton add skill security-audit    # installs to .ai/skills/security-audit/
skeleton add skill test-generation
skeleton add agent test-builder      # installs to .ai/agents/
skeleton add agent conflict-resolver
```

**11. Browse available resources** · `skeleton list`

List all skills, agents, or language templates available in the registry.

```sh
skeleton list skills
skeleton list agents
skeleton list templates
```

**12. Sync skills and agents from upstream** · `skeleton sync`

Sync all skills, agents, and prompts from the skeleton-parallel upstream into `.ai/` (ARES canonical source), then run `ars compose --target <provider>` to regenerate your provider harness. If `ars` is not installed, skeleton will offer to install it automatically.

```sh
skeleton sync                     # sync to .ai/ + compose provider harness
skeleton sync --dir=../my-project
```

**13. Compose provider harness from `.ai/` knowledge** · `ars compose`

skeleton-parallel uses [ARES](https://github.com/okfriansyah-moh/ares) (AI Repository Standard) as the canonical knowledge layer. Skills, agents, instructions, and prompts live in `.ai/` and are compiled into provider-specific harness files by the `ars` CLI.

```sh
ars compose --target copilot    # → .github/copilot-instructions.md
ars compose --target claude     # → CLAUDE.md
ars compose --target codex      # → AGENTS.md
ars compose --target cursor     # → .cursor/rules/*.mdc
```

Switch providers by changing `config/skeleton.yaml` and re-running `ars compose` — your `.ai/` source stays the same. To import existing provider files into `.ai/`:

```sh
ars import github   # import .github/copilot-instructions.md → .ai/
ars import claude   # import CLAUDE.md → .ai/
ars validate        # check .ai/ structure
```

**14. Regenerate hook templates** · `skeleton hooks regenerate`

Copy the language-appropriate hook templates (`quality-gates.sh`, `acceptance-gates.sh`) into `scripts/hooks/`.

```sh
skeleton hooks regenerate
skeleton hooks regenerate --dir=../my-project
```

**16. Check pipeline state** · `skeleton status`

Print the current run state from `.skeleton-dev/run-status.json` — which stages passed, failed, or are in progress.

```sh
skeleton status
```

**17. Clean up worktrees and branches** · `skeleton cleanup`

Remove all parallel worktrees, stale task branches, and reset `.skeleton-dev/` state after a run.

```sh
skeleton cleanup             # prompt before removing
skeleton cleanup --force     # no prompts
```

**18. CI with bounded retries and automatic rollback** · `skeleton run --full`

Each task gets a git checkpoint before execution. On retry exhaustion the branch rolls back automatically.

```sh
skeleton run --full
# On task failure:        auto-rollback to checkpoint-task-N-pre
# On quality gate fail:   refactor cycles up to MAX_REFACTOR_CYCLES
# On acceptance fail:     feedback router re-routes to the correct fix path
```

**19. Migrate from `run_parallel.sh` + `config/phases.yaml`** · `skeleton run`

The old phase-based orchestrator still works via a compatibility shim. Migrate when ready.

```sh
# Still works in v1.0 (shim active for one release):
./scripts/run_parallel.sh start --mode=3 1 2 3

# New equivalent:
skeleton run 1 2 3
```

**20. Check version or get help** · `skeleton version` · `skeleton help`

```sh
skeleton version     # print installed version (derived from git tag)
skeleton help        # full usage reference with all flags
```

## Installation

### macOS and Linux (one-line installer)

No Go or Node required:

```sh
curl -fsSL https://raw.githubusercontent.com/okfriansyah-moh/skeleton-parallel/main/install.sh | bash
```

Then add to PATH if prompted:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

Verify:

```sh
skeleton version
```

### Manual install (clone + symlink)

```sh
git clone https://github.com/okfriansyah-moh/skeleton-parallel ~/.skeleton-parallel
mkdir -p ~/.local/bin
ln -s ~/.skeleton-parallel/bin/skeleton ~/.local/bin/skeleton
skeleton version
```

### Update

```sh
git -C ~/.skeleton-parallel pull
```

### Windows

Use WSL (recommended) and run the macOS/Linux installer inside your WSL shell.

**PowerShell** (without WSL):

```powershell
git clone https://github.com/okfriansyah-moh/skeleton-parallel $env:USERPROFILE\.skeleton-parallel
# Add $env:USERPROFILE\.skeleton-parallel\bin to your PATH
# Invoke via: bash $env:USERPROFILE\.skeleton-parallel\bin\skeleton <cmd>
```

## Quick Start

```sh
skeleton init go --name=my-service
cd my-service

# Edit docs/PLAN.md — define your tasks
# Configure config/skeleton.yaml — choose driver + provider

skeleton doctor      # verify setup
skeleton run --full  # execute all pending tasks end-to-end
```

## Command Reference

| Command                                          | Description                                              |
| ------------------------------------------------ | -------------------------------------------------------- |
| `skeleton auth [--provider=PROV] [--dir=DIR]`    | Pre-flight: verify provider CLI auth before init/run. Providers: `claude` \| `copilot` \| `codex` \| `9router` (alias: `router_http`) |
| `skeleton init <lang> [--name=NAME] [--dir=DIR]` | Scaffold a new project from a language template          |
| `skeleton init <lang> --role=ROLE --root=PATH`   | Additive init into a planned multi-role architecture     |
| `skeleton run [tasks…] [flags]`                  | Execute PLAN.md tasks through the full pipeline          |
| `skeleton run --dry-run`                         | Print execution plan without invoking any agents         |
| `skeleton run --parallel`                        | One worktree per task (max speed)                        |
| `skeleton run --sequential`                      | Strict dependency order, single branch (min cost)        |
| `skeleton plan [--from=PLAN] [--source=DOC]`     | Bridge a2a plan or generate PLAN.md from architecture doc |
| `skeleton router <subcommand>`                   | Manage 9router daemon (install, start, stop, status, oauth) |
| `skeleton integrate [--dir=DIR]`                 | Brownfield onboarding: import legacy → .ai/ → hooks      |
| `skeleton doctor [--dir=DIR]`                    | Validate project health; check all required tools        |
| `skeleton autoskills [--dir=DIR]`                | Detect language and install matching skill modules       |
| `skeleton hooks regenerate [--dir=DIR]`          | Copy hook templates for detected stack                   |
| `skeleton upgrade [--mode=hybrid]`               | Update framework files in an existing project            |
| `skeleton status`                                | Show pipeline state from `.skeleton-dev/run-status.json` |
| `skeleton cleanup [--force]`                     | Remove worktrees, branches, clear state                  |
| `skeleton version`                               | Print version                                            |
| `skeleton help`                                  | Full usage reference                                     |

### `skeleton init` flags

| Flag            | Default              | Description                                                                 |
| --------------- | -------------------- | --------------------------------------------------------------------------- |
| `--name=NAME`   | directory name       | Project name used in generated files                                        |
| `--dir=DIR`     | `./<name>`           | Target directory                                                            |
| `--role=ROLE`   | —                    | Logical role name (`backend`, `frontend`, `mcp-server`…). Recorded in `.skeleton/layout.yaml` |
| `--root=PATH`   | same as `--role`     | Directory prefix for template files (e.g. `backend/`)                      |
| `--mode=MODE`   | auto-detected        | `create` · `overlay` · `respect-existing`                                  |
| `--force`       | false                | Overwrite existing files in overlay/respect-existing mode                   |
| `--no-agent`    | false                | Skip post-init Copilot agent spawn                                          |

### `skeleton plan` flags

| Flag              | Default               | Description                                                                     |
| ----------------- | --------------------- | ------------------------------------------------------------------------------- |
| `--from=PATH`     | auto-detected         | Import an a2a-brainstorm `plan.md` and enrich it into skeleton execution format |
| `--source=PATH`   | auto-detected         | Generate PLAN.md from an architecture doc (when no a2a plan is available)       |
| `--output=PATH`   | `docs/PLAN.md`        | Output path for the generated/enriched plan                                     |
| `--dir=DIR`       | `.`                   | Target project directory                                                        |
| `--dry-run`       | false                 | Show what would run; skip agent and file write                                  |
| `--no-agent`      | false                 | Skip agent spawn (prints manual instructions instead)                           |

Auto-detection order: `docs/plan.md` → `plan.md` → `docs/a2a-plan.md` (a2a import mode), then `docs/architecture.md` → `docs/ARCHITECTURE.md` → `docs/spec.md` → `docs/requirements.md` (generate mode).

The `--from` (a2a-import) mode enriches the a2a plan with `**ID:**` (T-001…), `**Depends:**`, `**Files:**` with concrete paths, and `**Acceptance:**` checkboxes. Content is preserved — only reformatted for `plan_parser.py` compatibility.

### `skeleton run` flags

| Flag                | Default                  | Description                                     |
| ------------------- | ------------------------ | ----------------------------------------------- |
| `--plan PATH`       | `manifest.defaults.plan` | Explicit PLAN.md path                           |
| `--tasks 1,2,3`     | all pending              | Comma-separated task IDs                        |
| `--parallel`        | —                        | Full parallel mode                              |
| `--sequential`      | —                        | Sequential mode                                 |
| `--driver DRIVER`   | from config              | Override execution driver                       |
| `--dry-run`         | false                    | Preview only; no agents, no git                 |
| `--force-deps`      | false                    | Proceed despite unsatisfied deps (logs warning) |
| `--no-auto-merge`   | false                    | Stop after Stage 0; skip merge and PR           |
| `--skip-acceptance` | false                    | Skip [5b] acceptance gates                      |
| `--acceptance-only` | false                    | Run [5b]/[5c] on current branch only            |

## Driver Support

| Driver             | Config value               | Requires                                     | When to use                                          |
| ------------------ | -------------------------- | -------------------------------------------- | ---------------------------------------------------- |
| `router_http`      | `driver: router_http`      | 9router daemon                               | Multi-provider routing, OAuth combos, quota rotation |
| `cli_subscription` | `driver: cli_subscription` | copilot / claude / codex CLI                 | Direct vendor CLI, no routing layer                  |
| `sdk_cursor`       | `driver: sdk_cursor`       | `@cursor/sdk`, Node 22.13+, `CURSOR_API_KEY` | Cursor agent runtime                                 |

```yaml
# config/skeleton.yaml — switch provider here, nothing else changes
execution:
  driver: cli_subscription # router_http | cli_subscription | sdk_cursor
  cli:
    provider: copilot # copilot | claude | codex
```

## Pipeline

```
skeleton run [tasks…] [flags]
        │
        ▼
╔══════════════════════════════════════════════════════════╗
║  STAGE −1  Knowledge sync (.ai/ compose-if-stale)        ║
╚══════════════════════════════╤═══════════════════════════╝
                               ▼
╔══════════════════════════════════════════════════════════╗
║  RESOLVE  plan · tasks · deps · parallel-safe file sets  ║
╚══════════════════════════════╤═══════════════════════════╝
                               ▼
╔══════════════════════════════════════════════════════════╗
║  STAGE 0  Per task / per parallel track                  ║
║  task-runner → dto-guardian → integration →              ║
║  security-auditor → test-builder → policy-check → T1     ║
╚══════════════════════════════╤═══════════════════════════╝
                               ▼
╔══════════════════════════════════════════════════════════╗
║  [2]  Union merge (if ≥2 parallel tracks) — 5 retries   ║
║  [3]  Post-merge review                   — 5 retries   ║
║  [4]  Docs sync (advisory)                — 1 attempt   ║
║  [5a] quality-gates.sh (T3)               — 5 cycles    ║
║  [5b] acceptance-gates.sh + LLM evaluator — 5 retries   ║
║  [5c] test-builder sufficiency            — 5 retries   ║
║  [6]  git push + gh pr create                           ║
╚══════════════════════════════════════════════════════════╝
```

### Resilience

| Mechanism           | Behavior                                                                                                              |
| ------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Checkpoint/rollback | Git tag before each task; auto-rollback on retry exhaustion                                                           |
| Bounded retries     | Every stage has a `retries.*` cap; guaranteed termination                                                             |
| Feedback router     | [5b] failures classified: `lint_build_unit` → refactor; `missing_tests` → test-builder; `wrong_feature` → task-runner |
| Union merge         | `conflict-resolver` agent combines all parallel track implementations; nothing discarded                              |
| Quota retry         | Driver exit code 2 (quota/429) triggers sleep-and-retry up to `max_total_wait`                                        |

## Repository Format

```
docs/PLAN.md                 task definitions, dep graph, file ownership, validation criteria
.ai/                         canonical AI knowledge (instructions, agents, skills, prompts)
config/skeleton.yaml         runtime config (driver, retries, acceptance, hooks)
scripts/hooks/
  quality-gates.sh           T1 + T3 quality gate hook (language-specific)
  acceptance-gates.sh        [5b] acceptance gate hook (project-specific E2E)
.skeleton-dev/
  plan-index.json            parsed task index
  run-status.json            per-stage pipeline state
  events.jsonl               structured observability log
  logs/                      per-agent log files
```

## Prerequisites

| Tool                           | Required For                     | Install                                                |
| ------------------------------ | -------------------------------- | ------------------------------------------------------ |
| `bash 4+`                      | All shell scripts                | `brew install bash`                                    |
| `git 2.5+`                     | Checkpoints, worktrees, PR       | `brew install git`                                     |
| `python3 3.10+`                | plan_parser.py, detect_legacy.py | `brew install python`                                  |
| `ars` (ARES CLI)               | Knowledge sync + harness compose (`ars compose`, `ars import`, `ars validate`) | [install ars](https://github.com/okfriansyah-moh/ares) |
| `9router`                      | `driver: router_http`            | `npm install -g 9router` ([decolua/9router](https://github.com/decolua/9router)) |
| `copilot` / `claude` / `codex` | `driver: cli_subscription`       | vendor-specific                                        |
| `node 22.13+`                  | `driver: sdk_cursor`             | `brew install node`                                    |
| `gh`                           | Stage [6] PR creation            | `brew install gh && gh auth login`                     |

## Migration from `run_parallel.sh`

`scripts/run_parallel.sh` is a **compatibility shim** in v1.0. It prints a deprecation warning and forwards to `skeleton run`. It will be removed in v2.0.

| Legacy                                    | v1.0 equivalent                                           |
| ----------------------------------------- | --------------------------------------------------------- |
| `run_parallel.sh start --mode=1 [phases]` | `skeleton run --parallel [tasks]`                         |
| `run_parallel.sh start --mode=2 [phases]` | `skeleton run --sequential [tasks]`                       |
| `run_parallel.sh start --mode=3 [phases]` | `skeleton run [tasks]` (hybrid default)                   |
| `run_parallel.sh status`                  | `skeleton status`                                         |
| `run_parallel.sh merge`                   | `skeleton merge`                                          |
| `run_parallel.sh cleanup`                 | `skeleton cleanup`                                        |
| `config/phases.yaml`                      | `docs/PLAN.md` (tasks + dep graph)                        |
| `MODEL_HEAVY` env                         | `router.combos.heavy` in `config/skeleton.yaml`           |
| `COPILOT_MODEL` env                       | `AGENT_MODEL` env (or `execution.cli.model` in `config/skeleton.yaml`) |
| `MAX_PARALLEL_AGENTS` env                 | `execution.max_parallel_agents` in `config/skeleton.yaml` |

See [docs/PARALLEL_DEV.md §11](docs/PARALLEL_DEV.md) for the full migration guide.

## Language Templates

`skeleton init <lang>` scaffolds a project with modular monolith architecture, `.ai/` knowledge, config, and hooks.

| Language     | Template                | Architecture                                         |
| ------------ | ----------------------- | ---------------------------------------------------- |
| `go`         | `templates/go/`         | Vertical slice, `internal/modules/`, health endpoint |
| `python`     | `templates/python/`     | Modular monolith, `app/modules/`, pyproject.toml     |
| `typescript` | `templates/typescript/` | ESM, `src/modules/`, vitest                          |
| `nodejs`     | `templates/nodejs/`     | CommonJS, `src/modules/`, jest                       |
| `rust`       | `templates/rust/`       | Workspace, `src/modules/`                            |
| `java`       | `templates/java/`       | Maven, `src/main/java/com/app/`                      |

## Agent System

### Core Pipeline Agents (15)

| Agent               | Stage              | Purpose                                      |
| ------------------- | ------------------ | -------------------------------------------- |
| `task-runner`       | Stage 0 step 1     | Implement one PLAN.md task end-to-end        |
| `dto-guardian`      | Stage 0 step 2     | Validate DTO contracts in `contracts/`       |
| `integration`       | Stage 0 step 3     | Wire modules, detect coupling violations     |
| `security-auditor`  | Stage 0 step 4     | OWASP-aware security assessment              |
| `test-builder`      | Stage 0 step 5     | Generate unit/integration tests              |
| `conflict-resolver` | Stage [2]          | Resolve merge conflicts (union strategy)     |
| `merge-reviewer`    | Stage [3]/[4]      | Post-merge DTO flow + boundary validation    |
| `refactor`          | [5a] remediation   | Fix quality gate violations                  |
| `phase-builder`     | legacy             | Implement phases from implementation roadmap |
| `orchestrator`      | review             | Build and validate pipeline orchestrator     |
| `module-builder`    | build              | Build individual pipeline modules            |
| `scaffold`          | `skeleton init`    | Validate project structure post-init         |
| `upgrade-manager`   | `skeleton upgrade` | Upgrade repos to skeleton-parallel           |
| `doctor`            | `skeleton doctor`  | Project health check                         |
| `task-sync`         | general            | Structured task execution workflow           |

### Skills (28)

`.ai/skills/<name>/SKILL.md` — canonical source (ARES). Use `ars compose --target <provider>` to compile into your provider's harness. Loaded on-demand to minimize token usage.

**Always-active:**

| Skill                         | Purpose                                     |
| ----------------------------- | ------------------------------------------- |
| `caveman`                     | Compress output ~75% when requested         |
| `brainstorming`               | Design-first gate before any implementation |
| `plan-management`             | Break work into 2–5 min tasks               |
| `subagent-driven-development` | Fresh subagent per task + 2-stage review    |
| `test-driven-development`     | RED-GREEN-REFACTOR cycle                    |
| `rtk`                         | Token-efficient CLI proxy (60–90% savings)  |

**Domain skills (loaded per agent/task):**
`dto` · `pipeline` · `modularity` · `determinism` · `idempotency` · `failure` · `config-validation` · `code-quality` · `coding-standards` · `conflict-resolution` · `docs-sync` · `database-portability` · `running-prompt` · `security-audit` · `test-generation` · `vertical-slice` · `api-design` · `project-scaffold` · `dependency-analysis` · `migration-management` · `performance-optimization` · `token-optimization`

## Architecture Principles

| Principle              | Rule                                                                         |
| ---------------------- | ---------------------------------------------------------------------------- |
| Modular monolith       | Single process, single database, no microservices                            |
| DTO communication      | Modules communicate only through immutable DTOs in `contracts/`              |
| Orchestrator authority | Only the orchestrator calls modules, manages state, accesses the DB          |
| Deterministic          | Same input + same config = identical output, always                          |
| Idempotent             | Content-addressable IDs, `ON CONFLICT DO NOTHING`                            |
| Database-agnostic      | All DB access through `database/adapter.*` — engine chosen per project       |
| Provider-agnostic      | Changing `execution.driver` is the only change needed to switch AI providers |
| Language-agnostic      | Architectural rules apply regardless of programming language                 |

## Documentation

| Document                                                                                             | Purpose                                                       |
| ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| [docs/specs/2026-06-27-agentic-loop-cli-design.md](docs/specs/2026-06-27-agentic-loop-cli-design.md) | v1.0 agentic loop CLI full specification                      |
| [docs/PARALLEL_DEV.md](docs/PARALLEL_DEV.md)                                                         | Parallel development guide + migration from `run_parallel.sh` |
| [docs/STARTER_GUIDE.md](docs/STARTER_GUIDE.md)                                                       | Step-by-step getting started walkthrough                      |
| [docs/AGENTS_AND_SKILLS.md](docs/AGENTS_AND_SKILLS.md)                                               | Agent and skill system reference                              |
| [docs/architecture.md](docs/architecture.md)                                                         | Architecture template                                         |
| [docs/implementation_roadmap.md](docs/implementation_roadmap.md)                                     | Roadmap template                                              |
| [docs/orchestrator_spec.md](docs/orchestrator_spec.md)                                               | Orchestrator spec template                                    |
| [docs/dto_contracts.md](docs/dto_contracts.md)                                                       | DTO contracts template                                        |
| [docs/db_adapter_spec.md](docs/db_adapter_spec.md)                                                   | Database adapter spec template                                |

## Contributing

Read [docs/specs/2026-06-27-agentic-loop-cli-design.md](docs/specs/2026-06-27-agentic-loop-cli-design.md) and [docs/PLAN.md](docs/PLAN.md) before changing behavior. Keep `docs/PLAN.md` as the canonical work contract and `.ai/` as the canonical knowledge source.

## License

Apache-2.0. See [LICENSE](LICENSE).
