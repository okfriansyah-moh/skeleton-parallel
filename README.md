# Skeleton Parallel

> A generic, reusable, language-agnostic development framework for building deterministic
> pipeline systems with AI-assisted parallel development. Database-agnostic, technology-flexible,
> and ready for any project from scratch.

---

## What This Is

A **production-grade project skeleton** that provides:

- **AI-assisted development framework** — 9 agents, 13 skills, and 5 prompts for GitHub Copilot
- **3-mode parallel development system** — Full parallel, token-optimized, and hybrid execution
- **Deterministic pipeline architecture** — Same input + same config = identical output
- **Database-agnostic design** — Choose any engine; modules never touch SQL directly
- **Self-healing retry system** — Bounded retries with checkpoint/rollback at every stage
- **Language-agnostic architecture** — Works with Python, TypeScript, Go, or any language

## Quick Start

```bash
# 1. Clone and initialize
git clone <this-repo> my-project
cd my-project && git remote remove origin

# 2. Generate your architecture
# Use the prompts in .github/prompts/ with GitHub Copilot:
@workspace Use .github/prompts/architecture.prompt.md to generate docs/architecture.md

# 3. Generate your roadmap
@workspace Use .github/prompts/roadmap.prompt.md to generate docs/implementation_roadmap.md

# 4. Generate supporting specs
@workspace Use .github/prompts/dto.prompt.md to generate docs/dto_contracts.md
@workspace Use .github/prompts/orchestrator.prompt.md to generate docs/orchestrator_spec.md
@workspace Use .github/prompts/db_adapter.prompt.md to generate docs/db_adapter_spec.md

# 5. Implement Phase 0 (infrastructure)
@phase-builder implement Phase 0

# 6. Run parallel development
./scripts/run_parallel.sh start --mode=3 1 2 3 4
```

See [docs/STARTER_GUIDE.md](docs/STARTER_GUIDE.md) for the full walkthrough.

## Repository Structure

```
skeleton-parallel/
├── .github/
│   ├── copilot-instructions.md    # Architectural constraints (always loaded)
│   ├── prompts/                   # One-shot generation prompts (5 files)
│   ├── agents/                    # Autonomous execution agents (9 agents)
│   │   ├── phase-builder          # Implement any phase from the roadmap
│   │   ├── dto-guardian           # Validate DTO contracts
│   │   ├── integration            # Wire modules, detect coupling
│   │   ├── orchestrator           # Build/validate pipeline orchestrator
│   │   ├── refactor               # Improve code without behavior change
│   │   ├── module-builder         # Build individual pipeline modules
│   │   ├── conflict-resolver      # Resolve merge conflicts (union strategy)
│   │   ├── merge-reviewer         # Post-merge validation and review
│   │   └── task-sync              # Structured task execution workflow
│   └── skills/                    # Folder-based knowledge modules (13 skills)
│       ├── dto/SKILL.md           # DTO registry and validation
│       ├── pipeline/SKILL.md      # Stage ordering and dependencies
│       ├── modularity/SKILL.md    # Module boundary enforcement
│       ├── determinism/SKILL.md   # No-randomness enforcement
│       ├── idempotency/SKILL.md   # Content-addressable IDs
│       ├── failure/SKILL.md       # Retry, abort, degradation
│       ├── token-optimization/    # Context compression
│       ├── config-validation/     # Config-driven parameters
│       ├── code-quality/          # Type annotations, logging, standards
│       ├── conflict-resolution/   # Git merge conflict resolution
│       ├── docs-sync/             # Documentation drift detection
│       ├── database-portability/  # Engine-agnostic SQL
│       └── running-prompt/        # Structured task execution
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

## Parallel Development Modes

| Mode | Name             | Speed    | Cost   | Best For                                |
| ---- | ---------------- | -------- | ------ | --------------------------------------- |
| 1    | Full Parallel    | Fastest  | High   | Independent phases, deadline pressure   |
| 2    | Token-Optimized  | Slowest  | Low    | Sequential dependencies, cost-sensitive |
| 3    | Hybrid (default) | Balanced | Medium | Most development sessions               |

```bash
./scripts/run_parallel.sh start --mode=1 2 3 4    # Full parallel
./scripts/run_parallel.sh start --mode=2 1 2 3    # Sequential
./scripts/run_parallel.sh start --mode=3 1 2 3 4  # Hybrid (default)
```

## Agent System

### Pipeline Agents (automated)

Every phase runs through this mandatory chain with bounded retries:

```
phase-builder (5 retries) → dto-guardian (5 retries) → integration (5 retries) → refactor (3 retries)
```

On failure: automatic rollback to Git checkpoint. No infinite loops.

### All Agents

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

### Skills (13)

Folder-based knowledge modules at `.github/skills/<name>/SKILL.md` — loaded on-demand by agents to minimize token usage while maintaining constraint enforcement.

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
| conflict-resolution  | Git merge conflict resolution              |
| docs-sync            | Documentation drift detection              |
| database-portability | Engine-agnostic SQL, adapter patterns      |
| running-prompt       | Structured task execution workflow         |

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

- Git 2.5+ (worktree support)
- VS Code + GitHub Copilot
- Runtime environment for the project’s chosen language
- (Optional) Copilot CLI for automated parallel execution

## License

MIT
