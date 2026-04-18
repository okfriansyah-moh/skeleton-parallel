# Skeleton Parallel

> A generic, reusable, language-agnostic development framework for building deterministic
> pipeline systems with AI-assisted parallel development. Database-agnostic, technology-flexible,
> and ready for any project from scratch.

---

## What This Is

A **production-grade project skeleton** that provides:

- **Agent-first CLI** (`skeleton`) — Every command spawns a Copilot CLI agent that validates, fixes, and commits automatically; no human approval needed
- **AI-assisted development framework** — 14 agents, 28 skills, and 5 prompts loaded by GitHub Copilot on demand
- **6 language templates** — `go`, `python`, `typescript`, `nodejs`, `rust`, `java` with modular monolith architecture built-in
- **Intelligent upgrade system** — Detects existing mechanisms, prompts Replace/Hybrid/Skip to safely merge frameworks
- **3-mode parallel development** — Full parallel, token-optimized, and hybrid agent execution via `run_parallel.sh`
- **Fully autonomous pipeline** — One command runs agents → union merge → review → PR creation, end-to-end
- **Deterministic pipeline architecture** — Same input + same config = identical output
- **Database-agnostic design** — Choose any engine; modules never touch SQL directly
- **Self-healing retry system** — Bounded retries with checkpoint/rollback at every stage

## Quick Start

### Option A: Using the Skeleton CLI (Recommended)

```bash
# 1. Install the framework
git clone <this-repo>
export PATH="$PWD/skeleton-parallel/bin:$PATH"

# 2. Create a new project — spawns Copilot agent to validate structure automatically
skeleton init go --name=my-service
cd my-service

# 3. Verify setup (auto-fix via agent if issues found)
skeleton doctor

# 4. Auto-install skills for your tech stack
skeleton autoskills

# 5. Generate your architecture
@workspace Use .github/prompts/architecture.prompt.md to generate docs/architecture.md

# 6. Generate your roadmap
@workspace Use .github/prompts/roadmap.prompt.md to generate docs/implementation_roadmap.md

# 7. Generate supporting specs
@workspace Use .github/prompts/dto.prompt.md to generate docs/dto_contracts.md
@workspace Use .github/prompts/orchestrator.prompt.md to generate docs/orchestrator_spec.md
@workspace Use .github/prompts/db_adapter.prompt.md to generate docs/db_adapter_spec.md

# 8. Implement Phase 0 (infrastructure)
@phase-builder implement Phase 0

# 9. Run parallel development
./scripts/run_parallel.sh start --mode=3 1 2 3 4
```

### Option B: Manual Setup

```bash
# 1. Clone and initialize
git clone <this-repo> my-project
cd my-project && git remote remove origin

# 2. Follow steps 4-8 above
```

### Option C: Upgrade Existing Repository

```bash
cd existing-project
skeleton upgrade            # Detects existing mechanisms, prompts Replace/Hybrid/Skip
skeleton upgrade --mode=hybrid  # Force hybrid (merge additively, preserve custom files)
skeleton doctor
```

See [docs/STARTER_GUIDE.md](docs/STARTER_GUIDE.md) for the full walkthrough.

## Repository Structure

```
skeleton-parallel/
├── bin/
│   └── skeleton                   # CLI: init, upgrade, doctor, add, list, sync, autoskills (v1.1.0)
├── templates/                     # Language-specific project templates
│   ├── common/                    # Shared files (README, .gitignore)
│   ├── go/                        # Go vertical slice template
│   ├── python/                    # Python modular monolith template
│   ├── typescript/                # TypeScript template
│   ├── nodejs/                    # Node.js (JavaScript) template
│   ├── rust/                      # Rust template
│   └── java/                      # Java template
├── .github/
│   ├── copilot-instructions.md    # Architectural constraints (always loaded)
│   ├── prompts/                   # One-shot generation prompts (5 files)
│   ├── agents/                    # Autonomous execution agents (14 agents)
│   │   ├── phase-builder          # Core: implement phases from roadmap
│   │   ├── dto-guardian           # Core: validate DTO contracts
│   │   ├── integration            # Core: wire modules, detect coupling
│   │   ├── orchestrator           # Core: build/validate pipeline
│   │   ├── refactor               # Core: improve without behavior change
│   │   ├── module-builder         # Core: build individual modules
│   │   ├── conflict-resolver      # Core: resolve merge conflicts
│   │   ├── merge-reviewer         # Core: post-merge validation
│   │   ├── task-sync              # Core: structured task execution
│   │   ├── scaffold               # Framework: project initialization
│   │   ├── security-auditor       # Framework: OWASP security review
│   │   ├── test-builder           # Framework: generate tests
│   │   ├── upgrade-manager        # Framework: upgrade existing repos
│   │   └── doctor                 # Framework: health check
│   └── skills/                    # Knowledge modules (28 skills)
│       ├── dto/                   # Core: DTO registry and validation
│       ├── pipeline/              # Core: stage ordering/dependencies
│       ├── modularity/            # Core: module boundary enforcement
│       ├── determinism/           # Core: no-randomness enforcement
│       ├── idempotency/           # Core: content-addressable IDs
│       ├── failure/               # Core: retry, abort, degradation
│       ├── token-optimization/    # Core: context compression
│       ├── config-validation/     # Core: config-driven parameters
│       ├── code-quality/          # Core: type annotations, logging
│       ├── conflict-resolution/   # Core: git merge resolution
│       ├── docs-sync/             # Core: documentation drift detection
│       ├── database-portability/  # Core: engine-agnostic SQL
│       ├── running-prompt/        # Core: structured task execution
│       ├── security-audit/        # Framework: OWASP auditing
│       ├── test-generation/       # Framework: test patterns/coverage
│       ├── vertical-slice/        # Framework: feature-per-folder
│       ├── api-design/            # Framework: REST/gRPC patterns
│       ├── project-scaffold/      # Framework: init validation
│       ├── dependency-analysis/   # Framework: import graph analysis
│       ├── migration-management/  # Framework: DB migration practices
│       ├── performance-optimization/ # Framework: profiling patterns
│       ├── caveman/               # Token compression: ~75% fewer output tokens
│       ├── brainstorming/         # Design-first gate before implementation
│       ├── writing-plans/         # Task decomposition into bite-sized steps
│       ├── subagent-driven-development/ # Fresh subagent per task + 2-stage review
│       ├── test-driven-development/ # RED-GREEN-REFACTOR cycle enforcement
│       └── rtk/                   # Token-efficient CLI proxy (60-90% savings)
├── docs/                          # Architecture + specs (templates)
├── contracts/                     # Immutable DTO definitions
├── database/                      # DB adapter + engine implementations + migrations
├── config/                        # YAML configuration
├── app/                           # Application code
│   ├── main.*                     # Entry point (language-specific)
│   ├── modules/                   # One package per pipeline stage
│   └── orchestrator/              # Pipeline orchestration
├── tests/                         # Unit + integration tests
├── scripts/
│   └── run_parallel.sh            # 3-mode parallel development orchestrator
└── output/                        # Generated artifacts (gitignored)
```

## Architecture Principles

| Principle              | Rule                                                                     |
| ---------------------- | ------------------------------------------------------------------------ |
| Modular monolith       | Single process, single database, no microservices                        |
| DTO communication      | Modules communicate only through immutable DTOs in `contracts/`          |
| Orchestrator authority | Only the orchestrator calls modules, manages state, accesses the DB      |
| Deterministic          | Same input + same config = identical output, always                      |
| Idempotent             | Content-addressable IDs, `ON CONFLICT DO NOTHING`                        |
| Database-agnostic      | All DB access through `database/adapter.*` — engine chosen per project   |
| Technology-flexible    | Forbidden-by-default tech can be overridden when the project requires it |
| Language-agnostic      | Architectural rules don’t mandate any specific programming language      |

## Parallel Development System

The `run_parallel.sh` orchestrator runs multiple implementation phases simultaneously using
autonomous AI agents, each with bounded retries and automatic rollback on failure.

### Execution Modes

| Mode | Name             | Speed    | Cost   | Heavy Model         | Best For                                |
| ---- | ---------------- | -------- | ------ | ------------------- | --------------------------------------- |
| 1    | Full Parallel    | Fastest  | High   | `claude-opus-4.6`   | Independent phases, deadline pressure   |
| 2    | Token-Optimized  | Slowest  | Low    | `claude-sonnet-4.6` | Sequential dependencies, cost-sensitive |
| 3    | Hybrid (default) | Balanced | Medium | `claude-sonnet-4.6` | Most development sessions               |

All other phases rotate through: `sonnet-4.6 → sonnet-4.5 → gpt-5.3-codex → gpt-5.4`

```bash
./scripts/run_parallel.sh start --mode=1 2 3 4           # Full parallel (opus for heaviest)
./scripts/run_parallel.sh start --mode=2 1 2 3           # Sequential (sonnet only)
./scripts/run_parallel.sh start --mode=3 1 2 3 4         # Hybrid (default, sonnet for heaviest)
./scripts/run_parallel.sh start --no-auto-merge 1 2 3    # Run agents only, skip auto-merge
./scripts/run_parallel.sh status                         # Check progress
./scripts/run_parallel.sh merge                          # Merge, validate, and create PR manually
./scripts/run_parallel.sh cleanup                        # Remove worktrees and branches
```

### Fully Autonomous Pipeline

A single `start` command runs the **entire pipeline** end-to-end without human intervention:

```
./scripts/run_parallel.sh start <phases>
         │
         ▼
[1] Per phase/group: phase-builder → dto-guardian → integration → refactor
         │  (bounded retries per stage; auto-rollback to checkpoint on exceed)
         ▼
[2] Union merge — conflict-resolver agent resolves all conflicts (5 retries)
         │  (preserves ALL implementations from every phase)
         ▼
[3] Post-merge review — merge-reviewer agent
         │  (DTO flow integrity · module boundaries · orchestrator authority)
         ▼
[4] Documentation sync — merge-reviewer agent  [advisory, non-blocking]
         │
         ▼
[5] Global validation + orchestrator authority check
         │  (refactor agent remediates if needed, up to 5 retries)
         ▼
[6] git push + gh pr create ──────────────────────────────► PR ready for review
```

The only human step is reviewing and merging the PR.

To opt out of auto-merge and inspect before integrating:

```bash
./scripts/run_parallel.sh start --no-auto-merge 1 2 3
# inspect, then:
./scripts/run_parallel.sh merge
```

### Resilience

- **Checkpoint/rollback** — Git tag before each phase; auto-rollback on failure
- **Bounded retries** — Every stage has a max retry limit; guaranteed termination
- **Union merge** — `conflict-resolver` agent combines all implementations; nothing is discarded
- **Post-merge review** — `merge-reviewer` agent validates DTO flow, boundaries, and orchestrator authority
- **Resource control** — Max 3 concurrent agents (configurable)
- **No human intervention** — All agents run with `--no-ask-user --autopilot`
- **Workspace confinement** — All agent prompts include an explicit constraint preventing writes to `/tmp` or paths outside the project; temporary artifacts go to `.parallel-dev/`, generated files to `output/`

### Status Display

`./scripts/run_parallel.sh status` shows a live view of the full pipeline:

```
  Branch Progress:
    phase-2 (ingestion-scene-splitter)   2 commits   — feat(phase-2): implement ingestion
    phase-3 (processing)                 running     — (no commits yet)

  Agent Status:
    Phase/Group                  State       Model               Exit  Updated
    ──────────────────────────── ─────────── ─────────────────── ───── ────────────────────
    phase-2 (ingestion...)       complete    claude-opus-4.6     0     2026-03-24T10:30:00Z
    phase-3 (processing)         running     claude-sonnet-4.5   —     2026-03-24T10:15:00Z
    ─────────────── Post-Phase Pipeline ─────────────────────────────────────────────────
    post-merge-review            complete    claude-sonnet-4.6   0     2026-03-24T10:35:00Z
    docs-sync                    advisory_failed  claude-sonnet-4.5  1  2026-03-24T10:36:00Z
    global-validation            complete    N/A                 0     2026-03-24T10:37:00Z

  Log files:
    phase-2-phase-builder-1.log -> /path (12,345 bytes)
    post-merge-review-1.log     -> /path (8,901 bytes)
```

Phase/group rows and post-phase pipeline stages (`post-merge-review`, `docs-sync`, `global-validation`, `remediation`) are tracked separately in `.parallel-dev/phase-status.json`.

## Agent System

### All Agents

| Agent | Purpose |
| ----- | ------- |

### Agents (14)

`.github/agents/<name>.md` — invoked as `@<name>` in GitHub Copilot chat.

#### Core Pipeline Agents

| Agent             | Purpose                                        |
| ----------------- | ---------------------------------------------- |
| phase-builder     | Implement any phase from the roadmap           |
| dto-guardian      | Validate DTO contracts in `contracts/`         |
| integration       | Wire modules together, detect coupling         |
| orchestrator      | Build and validate the pipeline orchestrator   |
| refactor          | Improve code structure without behavior change |
| module-builder    | Build individual pipeline modules from specs   |
| conflict-resolver | Resolve Git merge conflicts (union strategy)   |
| merge-reviewer    | Post-merge validation and quality review       |
| task-sync         | Structured task execution workflow             |

#### Framework Agents

| Agent            | Purpose                                                        |
| ---------------- | -------------------------------------------------------------- |
| scaffold         | Init projects, generate boilerplate, validate structure        |
| security-auditor | OWASP-aware security assessment with severity ratings          |
| test-builder     | Generate unit/integration tests, enforce coverage              |
| upgrade-manager  | Upgrade repos to skeleton-parallel; install scripts and skills |
| doctor           | Project health check; validate skills, agents, config          |

### Skills (28)

Folder-based knowledge modules at `.github/skills/<name>/SKILL.md` — loaded on-demand by agents to minimize token usage while maintaining constraint enforcement.

#### Core Pipeline Skills

| Skill                | Purpose                                    |
| -------------------- | ------------------------------------------ |
| dto                  | DTO registry, validation, anti-patterns    |
| pipeline             | Stage ordering, DTO flow, parallelism      |
| modularity           | Module boundaries, import rules            |
| determinism          | No-randomness enforcement                  |
| idempotency          | Content-addressable IDs, ON CONFLICT       |
| failure              | Retry policies, degradation, thresholds    |
| token-optimization   | Context compression, progressive loading   |
| config-validation    | Config-driven parameters, YAML enforcement |
| code-quality         | Type annotations, logging, code standards  |
| coding-standards     | Naming, function design, language idioms   |
| conflict-resolution  | Git merge conflict resolution              |
| docs-sync            | Documentation drift detection              |
| database-portability | Engine-agnostic SQL, adapter patterns      |
| running-prompt       | Structured task execution workflow         |

#### Framework Skills

| Skill                    | Purpose                                       |
| ------------------------ | --------------------------------------------- |
| security-audit           | OWASP vulnerability detection and remediation |
| test-generation          | Test patterns, coverage, AAA structure        |
| vertical-slice           | Feature-per-folder architecture enforcement   |
| api-design               | REST/gRPC endpoint and contract patterns      |
| project-scaffold         | Project initialization validation             |
| dependency-analysis      | Import graph and coupling analysis            |
| migration-management     | Database migration best practices             |
| performance-optimization | Profiling and throughput improvement          |

#### Always-Active Skills (Superpowers)

| Skill                       | Always On | Purpose                                                   |
| --------------------------- | --------- | --------------------------------------------------------- |
| caveman                     | ✅        | Compress output ~75% on demand — no filler, full accuracy |
| brainstorming               | ✅        | Design-first gate — never write code without a spec       |
| writing-plans               | ✅        | Break work into 2-5 min tasks before implementing         |
| subagent-driven-development | ✅        | Fresh subagent per task with 2-stage quality review       |
| test-driven-development     | ✅        | RED-GREEN-REFACTOR — no production code without a test    |
| rtk                         | ✅        | Token-efficient CLI proxy (60-90% output savings)         |

## Skeleton CLI (v1.1.0)

The `skeleton` CLI is **agent-first** — every file-modifying command spawns a Copilot CLI agent that validates, auto-fixes, and commits the result. Human approval is not required.

### Key Capabilities

| Feature                  | Description                                                                 |
| ------------------------ | --------------------------------------------------------------------------- |
| **Agent spawning**       | Every command invokes a Copilot agent to validate the output automatically  |
| **Replace/Hybrid/Skip**  | `skeleton upgrade` detects existing mechanisms and prompts upgrade strategy |
| `--no-agent`             | Skip agent invocation for one-off commands or offline use                   |
| `COPILOT_MODEL`          | Choose any model: `export COPILOT_MODEL=claude-sonnet-4.6`                  |
| `SKIP_AGENT=true`        | Globally disable agent spawning across all commands                         |
| **Tech-stack detection** | `skeleton autoskills` reads config/src files and installs matching skills   |
| **Idempotent upgrades**  | Re-running `skeleton upgrade` on an already-upgraded repo is safe           |

### Upgrade Modes

| Mode      | Behavior                                                           |
| --------- | ------------------------------------------------------------------ |
| `replace` | Full replacement: overwrites all framework files unconditionally   |
| `hybrid`  | Additive merge: adds missing files, preserves customized ones      |
| `skip`    | Validation only: reports what's missing without making any changes |

```bash
skeleton upgrade               # interactive mode — prompts for Replace/Hybrid/Skip
skeleton upgrade --mode=hybrid # force hybrid (safe for existing custom configs)
skeleton init typescript --no-agent  # skip agent validation this time
```

## Documentation

| Document                                                         | Purpose                        |
| ---------------------------------------------------------------- | ------------------------------ |
| [docs/STARTER_GUIDE.md](docs/STARTER_GUIDE.md)                   | How to use this framework      |
| [docs/PARALLEL_DEV.md](docs/PARALLEL_DEV.md)                     | Parallel development guide     |
| [docs/AGENTS_AND_SKILLS.md](docs/AGENTS_AND_SKILLS.md)           | Agent/skill system reference   |
| [docs/architecture.md](docs/architecture.md)                     | Architecture template          |
| [docs/implementation_roadmap.md](docs/implementation_roadmap.md) | Roadmap template               |
| [docs/orchestrator_spec.md](docs/orchestrator_spec.md)           | Orchestrator spec template     |
| [docs/dto_contracts.md](docs/dto_contracts.md)                   | DTO contracts template         |
| [docs/db_adapter_spec.md](docs/db_adapter_spec.md)               | Database adapter spec template |
| [docs/PROGRESS_REPORT.md](docs/PROGRESS_REPORT.md)               | Progress tracking template     |

## Requirements

- **Bash 4+** — Required for `run_parallel.sh` (macOS ships 3.2; install via `brew install bash`)
- **Git 2.5+** — Worktree support for parallel development
- **Python 3** — YAML config parser and validation checks
- **VS Code + GitHub Copilot** — Agent and skill system
- **Copilot CLI** — Required for agent spawning in `skeleton` commands (`--no-agent` to bypass)
- **GitHub CLI (`gh`)** — PR creation (auto-installed if absent; run `gh auth login` once)
- (Optional) Language-specific lint/test tools — place in `scripts/hooks/quality-gates.sh`

## License

Apache-2.0. See [LICENSE](LICENSE).
