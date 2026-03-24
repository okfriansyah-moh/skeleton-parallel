# Skeleton Parallel — Copilot Instructions

> These instructions enforce the architectural constraints for any project built on this framework.
> Violations are not acceptable and must not be introduced, even partially.

---

## Reference Documents

| Document                         | Purpose                                                                                                   |
| -------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `docs/architecture.md`           | Master reference — system architecture, module breakdown, pipeline flow, data model                       |
| `docs/implementation_roadmap.md` | Phase-based implementation roadmap with schemas, algorithms, exit criteria, priority layers               |
| `docs/orchestrator_spec.md`      | Orchestrator specification — execution model, checkpointing, resume, idempotency, failure handling        |
| `docs/dto_contracts.md`          | DTO definitions with all fields/types/constraints, cross-module dependency matrix, validation rules       |
| `docs/db_adapter_spec.md`        | Database abstraction layer — adapter interface, SQL compatibility, migration strategy, engine portability |
| `docs/PARALLEL_DEV.md`           | Parallel development orchestration guide — 3-mode execution system, phase grouping, token optimization    |
| `docs/AGENTS_AND_SKILLS.md`      | Agent/skill system — agents, skills, composition matrices, token optimization, parallel dev integration   |
| `docs/STARTER_GUIDE.md`          | Getting started playbook — setup, architecture generation, roadmap generation, parallel system usage      |
| `docs/PROGRESS_REPORT.md`        | Implementation status — completed work, test results, remaining items, phase-by-phase progress tracking   |
| `contracts/`                     | Frozen dataclass DTO definitions — all modules MUST use these, not upstream sources or raw dicts          |
| `config/`                        | YAML configuration files — all thresholds, paths, and tunable parameters live here                        |

When generating code, refer to these documents for exact schemas, DTO definitions, interfaces, and algorithms. Do not invent new structures that contradict them.

---

## Architecture Invariants

### Modular Monolith

- Single process, single repo, single database
- Entry point: `app/main.py` (or project-specific entry point)
- No microservices, no inter-process communication, no network calls between modules

### Module Communication

- Modules communicate **only** through frozen dataclass DTOs defined in `contracts/`
- No direct imports between module internals — only public contracts
- No raw dicts, no untyped data crossing module boundaries
- See `docs/dto_contracts.md` for DTO definitions and validation rules

### Pipeline Architecture

Stages execute in **strict sequential order** — never reorder, skip, or parallelize stages at runtime:

```
[Define your pipeline stages in docs/architecture.md]
stage_1 → stage_2 → stage_3 → ... → stage_N
```

### Determinism

- Same input + same config = identical output. Always.
- No `random`, no non-deterministic model inference, no network-dependent behavior
- All IDs are content-addressable (derived from content, not timestamps or random values)

### Idempotency

- Running the pipeline twice on the same input produces no duplicates and no corruption
- All IDs are content-addressable:
  - `entity_id = SHA256(content_signature)[:16]`
- All SQL uses portable `INSERT ... ON CONFLICT DO NOTHING` semantics

### State Authority

- **The database is the single source of truth** for all pipeline state
- Define tables per domain in `docs/architecture.md`
- Pipeline run states: `started → processing → completed | partial | failed`
- Entity states: `created → queued → processed → completed | failed`
- No in-memory-only state that isn't backed by the database

### Database Adapter

- **All database access goes through `database/adapter.py`** — the single entry point
- Modules under `app/modules/` **MUST NOT** import `sqlite3`, `psycopg2`, or any database driver
- Modules **MUST NOT** contain SQL strings or execute queries
- The adapter accepts and returns frozen dataclass DTOs — no raw rows, no dicts
- Only the orchestrator calls the adapter — modules never touch the database
- All SQL uses portable syntax (`ON CONFLICT DO NOTHING`, not `INSERT OR IGNORE`)
- See `docs/db_adapter_spec.md` for the full adapter interface and migration strategy

### Orchestrator Rules

- The orchestrator is the **only** component that calls modules — modules never call each other
- Checkpoint after every stage completion (write to database)
- Resume from last successful checkpoint on restart
- See `docs/orchestrator_spec.md` for the full execution model

### Orchestrator Authority Rule

The orchestrator is the **ONLY** component that:

- Calls modules (modules never call each other)
- Manages execution order (the pipeline stage sequence)
- Performs checkpointing (writes `last_completed_stage` after each stage)
- Writes to the database (via `database/adapter.py`)
- Routes DTOs between modules (passes output of stage N as input to stage N+1)
- Handles failures (decides retry, skip, or abort)

Modules MUST:

- Be **pure functions** — accept DTOs, return DTOs, no side effects on shared state
- **Not call the database** — no imports from `database/`, no SQL, no adapter calls
- **Not call other modules** — no imports from `app.modules.*` (only `contracts/`)
- **Not manage their own state** — all state lives in the database, managed by the orchestrator
- **Not perform checkpointing** — only the orchestrator decides when to persist progress

---

## Forbidden Technologies

Do not introduce any of these unless the project explicitly requires them:

| Category     | Default Forbidden                                                   | Override             |
| ------------ | ------------------------------------------------------------------- | -------------------- |
| Architecture | Microservices, Kafka, RabbitMQ, Kubernetes, Docker orchestration    | Unless project needs |
| Databases    | MongoDB, Redis, any distributed database                            | Unless project needs |
| AI/ML        | OpenAI API, Anthropic API, LangChain, AutoGPT, CrewAI, any paid LLM | Unless project needs |
| Cloud        | AWS, GCP, Azure, any cloud compute or storage                       | Unless project needs |
| Runtime      | Agent loops, autonomous planners, event-driven architectures        | Unless project needs |

> **Override policy:** If your project legitimately requires a forbidden technology (e.g., Redis for caching, Docker for deployment, OpenAI for an LLM-powered feature), document the justification in `docs/architecture.md` and proceed. The defaults exist to prevent accidental complexity, not to block valid requirements.

### Database Engine Policy

- **The database engine is project-specific.** Choose the appropriate engine when setting up a new project.
- **Supported engines are configured via `database/adapter.py`.** See `docs/db_adapter_spec.md`.
- **Modules MUST remain database-agnostic.** No module may reference any specific database engine.
- Direct use of any database driver (`sqlite3`, `psycopg2`, `asyncpg`, etc.) in `app/modules/` is forbidden.
- The adapter is the **sole abstraction boundary** — switching engines requires changes only in `database/`.

---

## Repository Structure

```
skeleton-parallel/
├── app/
│   ├── main.py              # Single entry point
│   ├── modules/             # Domain modules (one package per stage)
│   │   ├── module_a/
│   │   ├── module_b/
│   │   └── ...
│   └── orchestrator/        # Pipeline orchestration + checkpointing
├── contracts/               # DTO definitions (frozen dataclasses)
├── database/                # DB adapter + engine implementations + migrations
├── config/                  # YAML configuration
├── tests/                   # Unit + integration tests
├── output/                  # Generated artifacts (gitignored)
├── docs/                    # Architecture + specs
├── scripts/                 # Automation scripts
└── .github/                 # Agent + skill + prompt definitions
```

**Placement rules:**

- New module logic goes in the appropriate `app/modules/` subdirectory
- New DTO definitions go in `contracts/` — never duplicate in a module
- Database migrations go in `database/migrations/`
- Tests mirror the `app/modules/` structure under `tests/`
- Configuration defaults go in `config/` YAML files — never hardcode
- Never put module-specific logic in `app/orchestrator/` or `contracts/`

---

## Development Rules

1. **Python 3.10+** — Use type hints on all public interfaces
2. **Frozen dataclasses** for all DTOs — no mutable state crossing module boundaries
3. **Each module** gets its own package under `app/modules/` with `__init__.py` exposing only the public contract
4. **No module may import another module's internals** — only `contracts/` types
5. **Database access** through `database/adapter.py` only — no raw SQL in modules, no ORM, no SQLAlchemy
6. **Tests** must be runnable without GPU, without network, and without real data files
7. **Config** via YAML files — no hardcoded paths, thresholds, or magic numbers
8. **Logging** via stdlib `logging` — structured, leveled, no print statements

---

## Skill System

Skills are pre-digested knowledge packages that agents load on-demand. They live in `.github/skills/<name>/SKILL.md`.

### Skill Structure

```
.github/skills/
├── dto/SKILL.md                 # DTO validation and registry
├── pipeline/SKILL.md            # Stage ordering and dependencies
├── modularity/SKILL.md          # Module boundary enforcement
├── determinism/SKILL.md         # No-randomness enforcement
├── idempotency/SKILL.md         # Content-addressable IDs, ON CONFLICT
├── failure/SKILL.md             # Retry, abort, degradation
├── token-optimization/SKILL.md  # Context loading optimization
├── config-validation/SKILL.md   # Config-driven parameters
├── code-quality/SKILL.md        # Type hints, logging, standards
├── conflict-resolution/SKILL.md # Git merge conflict resolution
├── docs-sync/SKILL.md           # Documentation drift detection
├── database-portability/SKILL.md # Engine-agnostic SQL
└── running-prompt/SKILL.md      # Structured task execution workflow
```

### Skill Loading Rules

- **Load skills before raw docs** — skills are pre-digested, cheaper than full documents
- **Reference, don't repeat** — say "per dto skill" instead of re-stating rules
- **Progressive disclosure** — skill → doc section → full doc (only when needed)
- Each skill has standardized format: frontmatter (`name`, `type`, `description`) + Purpose, Rules, Inputs, Outputs, Examples, Checklist

### Agent–Skill Composition

Each agent declares its skills in a `## Skills Used` section. Core skills used by most agents:

| Skill                | dto-guardian | integration | orchestrator | phase-builder | module-builder | refactor | conflict-resolver | merge-reviewer |
| -------------------- | ------------ | ----------- | ------------ | ------------- | -------------- | -------- | ----------------- | -------------- |
| dto                  | ✅           | ✅          |              | ✅            | ✅             |          | ✅                | ✅             |
| pipeline             |              | ✅          | ✅           | ✅            |                |          | ✅                | ✅             |
| modularity           | ✅           | ✅          |              | ✅            | ✅             | ✅       | ✅                | ✅             |
| determinism          | ✅           |             |              | ✅            | ✅             | ✅       |                   |                |
| idempotency          |              | ✅          | ✅           | ✅            | ✅             |          |                   | ✅             |
| failure              |              | ✅          | ✅           | ✅            |                |          |                   |                |
| config-validation    |              |             |              | ✅            | ✅             |          |                   |                |
| code-quality         |              |             |              | ✅            | ✅             | ✅       |                   | ✅             |
| database-portability |              | ✅          | ✅           | ✅            |                |          |                   | ✅             |
| token-optimization   |              |             |              | ✅            |                |          |                   |                |
| docs-sync            | ✅           | ✅          |              |               |                |          |                   | ✅             |
| conflict-resolution  |              |             |              |               |                |          | ✅                |                |

---

## Protected Files

These files/directories have strict modification rules during parallel development:

| Path          | Rule                                                                 |
| ------------- | -------------------------------------------------------------------- |
| `contracts/*` | **Additive only** — new DTOs allowed, existing fields never modified |
| `database/*`  | **Phase 0 only** — only infrastructure phase may modify              |
| `docs/*`      | **Read-only** — no agent may modify documentation                    |
| `config/*`    | **Append-only** — new keys allowed, existing keys never removed      |

---

## Migration-Safe Database Rules

1. Migration files follow naming: `YYYYMMDD000NNN_description.sql`
2. Migrations are **append-only** — never modify existing migration files
3. All schema changes go through migrations — no ad-hoc ALTER TABLE
4. All SQL uses **portable syntax** compatible with all supported engines
5. Use `ON CONFLICT DO NOTHING` (not engine-specific variants like `INSERT OR IGNORE`)
6. Use parameterized queries only — no string interpolation in SQL
7. Use `CURRENT_TIMESTAMP` for defaults — no engine-specific date/time functions
8. Engine-specific settings (e.g., WAL mode, connection pooling) belong in `database/engines/` only
