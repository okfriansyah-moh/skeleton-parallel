# Skeleton Parallel

> Provider-agnostic agentic loop CLI for building deterministic pipeline systems with AI-assisted parallel development. One `docs/PLAN.md` → Copilot, Claude, Codex, Cursor — any driver, any language.

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

**5. Onboard an existing repo** · `skeleton integrate`

Your repo already has `.github/copilot-instructions.md`, agents, or hooks. Import everything into `.ai/`, wire the router, and regenerate hooks.

```sh
cd existing-repo
skeleton integrate           # runs full Appendix A checklist
skeleton integrate --dir=./path/to/repo
```

**6. Validate project health** · `skeleton doctor`

Check that all required tools, config keys, hooks, and `.ai/` structure are wired correctly.

```sh
skeleton doctor              # checks current directory
skeleton doctor --dir=../my-project
```

**7. Upgrade an existing project** · `skeleton upgrade`

Pull the latest framework files (scripts, templates, agents) into a project without overwriting your customizations.

```sh
skeleton upgrade                        # auto-detect mode
skeleton upgrade --mode=hybrid          # merge new + keep custom
skeleton upgrade --mode=replace         # full replacement
skeleton upgrade --dir=../my-project --no-agent
```

**8. Auto-detect stack and install matching skills** · `skeleton autoskills`

Scans the project's language, frameworks, and tools, then installs the matching skill modules into `.github/skills/`.

```sh
skeleton autoskills                     # current directory
skeleton autoskills --dir=../my-project
skeleton autoskills --dry-run           # preview only
skeleton autoskills -y                  # skip confirmation prompts
```

**9. Add a skill or agent to a project** · `skeleton add`

Install a single named skill or agent from the skeleton-parallel registry into the current project.

```sh
skeleton add skill security-audit
skeleton add skill test-generation
skeleton add agent test-builder
skeleton add agent conflict-resolver
```

**10. Browse available resources** · `skeleton list`

List all skills, agents, or language templates available in the registry.

```sh
skeleton list skills
skeleton list agents
skeleton list templates
```

**11. Sync skills and agents from upstream** · `skeleton sync`

Force-sync all skills, agents, and scripts from the skeleton-parallel upstream into the current project.

```sh
skeleton sync                     # current directory
skeleton sync --dir=../my-project
```

**12. Regenerate hook templates** · `skeleton hooks regenerate`

Copy the language-appropriate hook templates (`quality-gates.sh`, `acceptance-gates.sh`) into `scripts/hooks/`.

```sh
skeleton hooks regenerate
skeleton hooks regenerate --dir=../my-project
```

**13. Check pipeline state** · `skeleton status`

Print the current run state from `.skeleton-dev/run-status.json` — which stages passed, failed, or are in progress.

```sh
skeleton status
```

**14. Clean up worktrees and branches** · `skeleton cleanup`

Remove all parallel worktrees, stale task branches, and reset `.skeleton-dev/` state after a run.

```sh
skeleton cleanup             # prompt before removing
skeleton cleanup --force     # no prompts
```

**15. CI with bounded retries and automatic rollback** · `skeleton run --full`

Each task gets a git checkpoint before execution. On retry exhaustion the branch rolls back automatically.

```sh
skeleton run --full
# On task failure:        auto-rollback to checkpoint-task-N-pre
# On quality gate fail:   refactor cycles up to MAX_REFACTOR_CYCLES
# On acceptance fail:     feedback router re-routes to the correct fix path
```

**16. Migrate from `run_parallel.sh` + `config/phases.yaml`** · `skeleton run`

The old phase-based orchestrator still works via a compatibility shim. Migrate when ready.

```sh
# Still works in v1.0 (shim active for one release):
./scripts/run_parallel.sh start --mode=3 1 2 3

# New equivalent:
skeleton run 1 2 3
```

**17. Check version or get help** · `skeleton version` · `skeleton help`

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
| `skeleton init <lang> [--name=NAME] [--dir=DIR]` | Scaffold a new project from a language template          |
| `skeleton run [tasks…] [flags]`                  | Execute PLAN.md tasks through the full pipeline          |
| `skeleton run --dry-run`                         | Print execution plan without invoking any agents         |
| `skeleton run --parallel`                        | One worktree per task (max speed)                        |
| `skeleton run --sequential`                      | Strict dependency order, single branch (min cost)        |
| `skeleton integrate [--dir=DIR]`                 | Brownfield onboarding: import legacy → .ai/ → hooks      |
| `skeleton doctor [--dir=DIR]`                    | Validate project health; check all required tools        |
| `skeleton autoskills [--dir=DIR]`                | Detect language and install matching skill modules       |
| `skeleton hooks regenerate [--dir=DIR]`          | Copy hook templates for detected stack                   |
| `skeleton upgrade [--mode=hybrid]`               | Update framework files in an existing project            |
| `skeleton status`                                | Show pipeline state from `.skeleton-dev/run-status.json` |
| `skeleton cleanup [--force]`                     | Remove worktrees, branches, clear state                  |
| `skeleton version`                               | Print version                                            |
| `skeleton help`                                  | Full usage reference                                     |

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
| `ars` (ARES CLI)               | Stage −1 knowledge sync          | [install ars](https://github.com/okfriansyah-moh/ares) |
| `9router`                      | `driver: router_http`            | `npm install -g @9router/server`                       |
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
| `COPILOT_MODEL` env                       | `execution.cli.model` in `config/skeleton.yaml`           |
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

`.github/skills/<name>/SKILL.md` — loaded on-demand to minimize token usage.

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
