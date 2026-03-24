# Starter Guide

> Step-by-step playbook for using the skeleton-parallel framework to build a new project.

---

## 1. Prerequisites

- **Runtime environment** for the project’s chosen language installed
- **Git** with worktree support (Git 2.5+)
- **VS Code** with GitHub Copilot extension
- (Optional) **Copilot CLI** for automated parallel execution

---

## 2. Quick Start

### Step 1: Clone the Framework

```bash
git clone <skeleton-parallel-repo-url> my-project
cd my-project
git remote remove origin
git init  # Fresh history for your project
```

### Step 2: Generate Architecture

Use the architecture prompt to create your system design:

```
@workspace Use .github/prompts/architecture.prompt.md to generate docs/architecture.md
```

The prompt will guide you through:

- Defining your system goal
- Listing pipeline stages
- Defining data models
- Specifying DTO contracts

### Step 3: Generate Roadmap

Use the roadmap prompt to create your implementation plan:

```
@workspace Use .github/prompts/roadmap.prompt.md to generate docs/implementation_roadmap.md
```

This generates:

- Phase-by-phase tasks with exit criteria
- File ownership matrix for parallel development
- Priority tiers (P0/P1/P1.5/P2)

### Step 4: Generate Supporting Specs

Generate the remaining specification documents:

```
@workspace Use .github/prompts/dto.prompt.md to generate docs/dto_contracts.md
@workspace Use .github/prompts/orchestrator.prompt.md to generate docs/orchestrator_spec.md
@workspace Use .github/prompts/db_adapter.prompt.md to generate docs/db_adapter_spec.md
```

### Step 5: Implement Phase 0 (Infrastructure)

Phase 0 creates the foundation. Always implement this first:

```
@phase-builder implement Phase 0
```

This creates:

- Database schema and migrations
- Database adapter
- Configuration loader
- Entry point
- Orchestrator skeleton

### Step 6: Run Parallel Development

Once Phase 0 is complete, run remaining phases in parallel:

```bash
# Mode 3 (Hybrid) — recommended default
./scripts/run_parallel.sh start --mode=3 1 2 3 4

# Mode 1 (Full Parallel) — maximum speed
./scripts/run_parallel.sh start --mode=1 2 3 4

# Mode 2 (Token-Optimized) — minimum cost
./scripts/run_parallel.sh start --mode=2 1 2 3
```

---

## 3. Framework Structure

```
skeleton-parallel/
├── .github/
│   ├── copilot-instructions.md    # Hard architectural constraints (always loaded)
│   ├── prompts/                   # One-shot generation prompts
│   │   ├── architecture.prompt.md
│   │   ├── roadmap.prompt.md
│   │   ├── orchestrator.prompt.md
│   │   ├── dto.prompt.md
│   │   └── db_adapter.prompt.md
│   ├── agents/                    # Autonomous execution agents
│   │   ├── phase-builder.agent.md
│   │   ├── dto-guardian.agent.md
│   │   ├── integration.agent.md
│   │   ├── refactor.agent.md
│   │   ├── orchestrator.agent.md
│   │   ├── module-builder.agent.md
│   │   ├── conflict-resolver.agent.md
│   │   ├── merge-reviewer.agent.md
│   │   └── task-sync.agent.md
│   └── skills/                    # Focused knowledge modules (folder-based)
│       ├── dto/SKILL.md
│       ├── pipeline/SKILL.md
│       ├── modularity/SKILL.md
│       ├── determinism/SKILL.md
│       ├── idempotency/SKILL.md
│       ├── failure/SKILL.md
│       ├── token-optimization/SKILL.md
│       ├── config-validation/SKILL.md
│       ├── code-quality/SKILL.md
│       ├── conflict-resolution/SKILL.md
│       ├── docs-sync/SKILL.md
│       ├── database-portability/SKILL.md
│       └── running-prompt/SKILL.md
├── docs/                          # Architecture + specs (templates)
├── contracts/                     # Immutable DTO definitions
├── database/                      # DB adapter + migrations
├── config/                        # YAML configuration
├── app/                           # Application code
│   ├── main.*                     # Entry point (language-specific)
│   ├── modules/                   # One package per pipeline stage
│   └── orchestrator/              # Pipeline orchestration
├── tests/                         # Unit + integration tests
├── scripts/                       # Automation (run_parallel.sh)
└── output/                        # Generated artifacts (gitignored)
```

---

## 4. Development Workflow

### Single Phase (Manual)

```
@phase-builder implement Phase 3
```

The phase-builder agent:

1. Reads the roadmap for Phase 3 requirements
2. Creates module under `app/modules/`
3. Defines DTOs in `contracts/`
4. Writes unit tests
5. Wires into orchestrator

### Parallel Phases (Automated)

```bash
./scripts/run_parallel.sh start --mode=3 2 3 4
```

The script:

1. Groups phases by dependency
2. Creates Git worktrees per group
3. Runs agent pipeline (build → validate → integrate → fix)
4. Merges results
5. Runs global validation

### Merge & Validate

```bash
./scripts/run_parallel.sh merge
```

### Check Status

```bash
./scripts/run_parallel.sh status
```

### Cleanup

```bash
./scripts/run_parallel.sh cleanup
```

---

## 5. Key Concepts

### Modular Monolith

- Single process, single database
- Modules communicate only through DTOs
- No cross-module imports

### Deterministic Execution

- Same input + same config = identical output
- Content-addressable IDs (SHA-256)
- No randomness in processing logic

### Self-Healing Retries

- Every stage: execute → validate → fix → retry → success OR rollback
- Bounded retries (no infinite loops)
- Checkpoint before each phase (Git tags)

### Documentation-First

- Architecture document drives all implementation
- DTO contracts define module interfaces
- Roadmap defines phase boundaries and ownership

---

## 6. Customization

### Adding Pipeline Stages

1. Define the stage in `docs/architecture.md`
2. Add the DTO contract in `docs/dto_contracts.md`
3. Create the module under `app/modules/stage_name/`
4. Define DTOs in `contracts/stage_name.py`
5. Wire into `app/orchestrator/pipeline.py`
6. Add to `docs/implementation_roadmap.md`

### Adding Skills

Create a new folder at `.github/skills/<kebab-case-name>/SKILL.md` with:

- YAML frontmatter (`name`, `type: skill`, `description`)
- Purpose, Rules, Inputs, Outputs, Examples, Checklist sections
- Reference the skill in agent files that need it (under `## Skills Used`)

### Adding Agents

Create `.github/agents/new_agent.agent.md` with:

- YAML frontmatter (name, description, argument-hint, tools, model)
- Skills Used section referencing `.github/skills/<name>/SKILL.md`
- Role, Responsibilities, Constraints, Source of Truth, Output sections
