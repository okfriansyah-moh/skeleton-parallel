# Parallel Development Guide — `run_parallel.sh`

> Operator guide for running multiple implementation phases simultaneously using
> autonomous AI agents. Supports 3 execution modes that balance speed, cost, and
> merge complexity.

---

## 1. Overview

This framework supports parallel development of pipeline phases. Most phases own isolated
modules under `app/modules/` and communicate only through immutable DTOs in `contracts/`.
This isolation enables parallel development — multiple phases implemented at the same time
by independent AI agents.

However, parallelism has tradeoffs:

| Dimension      | More Parallelism              | Less Parallelism        |
| -------------- | ----------------------------- | ----------------------- |
| **Speed**      | Faster wall-clock time        | Slower (sequential)     |
| **Token cost** | Higher (each agent re-reads)  | Lower (shared context)  |
| **Merge risk** | More conflicts at integration | Fewer conflicts         |
| **Debugging**  | Harder (concurrent sessions)  | Easier (single session) |

Three execution modes let the operator choose the right balance for the situation.

---

## 2. Mode Definitions

### Mode 1 — Full Parallel (Maximum Speed)

Each phase runs in a **separate Git worktree** with a **dedicated Copilot CLI agent**.
All phases execute simultaneously.

**How it works:**

```text
main
 ├─ track/phase-2   ← worktree 1, checkpoint + agent pipeline (bounded retries)
 ├─ track/phase-3   ← worktree 2, checkpoint + agent pipeline (bounded retries)
 └─ track/phase-4   ← worktree 3, checkpoint + agent pipeline (bounded retries)
```

1. Creates a branch per phase from `main`
2. Creates a Git worktree per branch (sibling directories)
3. Generates a `PHASE_TASK.md` instruction file in each worktree
4. Creates **checkpoint** (`git tag checkpoint-phase-N-pre`) in each worktree
5. Runs the **agent pipeline** per worktree with **bounded retries**:
   - `phase-builder` — implements the phase (up to 5 retries)
   - `dto-guardian` — validates DTO contracts (up to 5 retries)
   - `integration` — validates module wiring (up to 5 retries)
   - `refactor` — fixes quality gate failures (up to 3 retries)
   - If any stage exceeds retry limit → rollback to checkpoint
6. Resource control: max `MAX_PARALLEL_AGENTS` (default 3) concurrent pipelines
7. Waits for all agent pipelines to finish
8. Merges all branches into an integration branch (bounded merge retries)
9. Runs global validation + creates PR

**When to use:**

- Deadline pressure — need maximum throughput
- All phases in the batch are independent (no shared file ownership)

---

### Mode 2 — Token-Optimized (Serial Grouping)

Multiple phases run **sequentially in a single Copilot CLI session**. No worktrees.
Context is shared across phases.

**How it works:**

```text
main
 └─ track/group-2-3-4  ← single branch, checkpoint + agent pipeline (bounded retries)
     Phase 2 → commit → Phase 3 → commit → Phase 4 → commit
     dto-guardian → integration → refactor (bounded retries) → global validation
```

1. Creates a single branch from `main`
2. Generates a single `PHASE_TASK.md` with all phases listed in order
3. Creates **checkpoint** (`git tag checkpoint-group-X-pre`)
4. Runs the **agent pipeline** with **bounded retries**
5. Each phase is committed before starting the next
6. Runs global validation + creates PR

**When to use:**

- Cost-sensitive development (limited premium requests)
- Phases have sequential dependencies
- Debugging a specific pipeline section end-to-end

**Grouping rules:**

- Maximum **3 phases per session** (beyond this, context window saturates)
- Phases must be in dependency order (earlier phases first)
- DTO-producing phases go before DTO-consuming phases

---

### Mode 3 — Hybrid (Balanced) — DEFAULT

Groups of phases run **in parallel across groups**, but **sequentially within each group**.
Combines the isolation of Mode 1 with the context sharing of Mode 2.

**How it works:**

```text
main
 ├─ track/group-a  ← worktree 1, checkpoint + agent pipeline (bounded retries)
 └─ track/group-b  ← worktree 2, checkpoint + agent pipeline (bounded retries)
```

1. Groups phases by dependency and file ownership
2. Creates a branch + worktree per group
3. Creates **checkpoint** per group
4. Each group runs the **agent pipeline** with **bounded retries**
5. Groups execute in parallel (independent worktrees)
6. Merges all group branches into integration branch
7. Runs global validation + creates PR

**When to use:**

- Default choice for most development sessions
- Balance between speed and cost
- Phases have natural groupings by pipeline section

---

## 3. Mode Selection Strategy

```text
                        ┌─────────────────────┐
                        │  How many phases?    │
                        └─────────┬───────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼              ▼
               1 phase      2–3 phases      4+ phases
                    │             │              │
                    ▼             ▼              ▼
              Mode 2         Mode 2          ┌──────┐
           (single session)  (single session)│ Are   │
                                             │ they  │
                                             │ indep?│
                                             └──┬───┘
                                           yes  │  no
                                            ┌───┘───┐
                                            ▼       ▼
                                         Mode 1   Mode 3
                                       (full par) (hybrid)
```

| Scenario                                    | Recommended Mode |
| ------------------------------------------- | ---------------- |
| Single phase implementation                 | Mode 2           |
| 2–3 phases with sequential dependency       | Mode 2           |
| 2–3 fully independent phases                | Mode 1           |
| 4+ phases, mix of dependent and independent | Mode 3           |
| Cost-constrained (limited premium requests) | Mode 2           |
| Deadline pressure, all phases independent   | Mode 1           |
| Default / unsure                            | Mode 3           |

---

## 4. Phase Grouping Rules

### Safe Parallel Combinations

Phases can run simultaneously when they own **different files**:

```text
✅ Phase A ‖ Phase C  — different modules, no shared files
✅ Phase B ‖ Phase D  — independent inputs
```

### Unsafe Combinations

```text
❌ Phase 0 ‖ anything   — Phase 0 creates shared infrastructure
❌ DTO changes ‖ module changes — Module depends on DTO definition
❌ orchestrator ‖ any module  — Concurrent changes conflict
```

### File Ownership

Each phase owns specific directories. Parallel phases MUST NOT share file ownership.
Define your ownership matrix in `docs/implementation_roadmap.md`.

---

## 5. Token Cost Optimization Strategy

### Skill-First Loading

All agents use the skills system from `.github/skills/` instead of re-reading full documentation:

| Full Doc                    | Tokens | Equivalent Skill              | Tokens | Savings |
| --------------------------- | ------ | ----------------------------- | ------ | ------- |
| `docs/architecture.md`      | ~5000  | pipeline + modularity skills  | ~600   | 88%     |
| `docs/dto_contracts.md`     | ~6000  | dto skill                     | ~400   | 93%     |
| `docs/orchestrator_spec.md` | ~4000  | pipeline + idempotency skills | ~500   | 88%     |

### Token Optimization Rules

1. **Reuse context within session** — Never re-read a document already loaded
2. **Skills first, docs second** — Load skills before falling back to raw documentation
3. **Prefer grouped execution** — Use Mode 2 or Mode 3 to share context
4. **No full-doc reads** — Load the relevant skill, then deep-dive into specific doc sections only if needed
5. **Progressive loading** — Skill discovery → skill body → doc section (only if needed)
6. **Skill injection is automatic** — `run_parallel.sh` injects skill references into every Copilot call

---

## 6. Resilience Framework

### Universal Retry Pattern

ALL stages follow the same deterministic execution pattern:

```text
execute → validate → fix → re-validate → bounded retry → success OR rollback
```

Every code path terminates in a defined state — **no infinite loops, no undefined state**.

### Retry Configuration

```bash
MAX_RETRIES_PHASE_BUILDER=5
MAX_RETRIES_DTO=5
MAX_RETRIES_INTEGRATION=5
MAX_RETRIES_MERGE=5
MAX_RETRIES_GLOBAL_VALIDATION=5
MAX_REMEDIATION_RETRIES=3          # quality gate remediation within pipeline
MAX_PARALLEL_AGENTS=3              # resource control
```

All retry limits are bounded. The system is **guaranteed to terminate**.

### Checkpoint & Rollback

Before each phase/group, a Git tag checkpoint is created:

```bash
git tag checkpoint-${phase_label}-pre
```

If any stage exceeds its retry limit:

```bash
git reset --hard checkpoint-${phase_label}-pre
```

On success, the checkpoint is cleaned up:

```bash
git tag -d checkpoint-${phase_label}-pre
```

### Agent Pipeline (per phase/group)

```text
phase-builder (up to 5 retries)
  → dto-guardian (up to 5 retries)
    → integration (up to 5 retries)
      → refactor/quality gates (up to 3 retries)
        → success OR rollback
```

### Stage-Specific Validation

#### Phase Builder

- **Execute:** Copilot `phase-builder` agent implements phase
- **Validate:** Module compiles, no syntax errors, imports valid
- **Fix:** `refactor` agent fixes compilation issues
- **On failure:** Rollback to checkpoint

#### DTO Guardian (STRICT)

- **Execute:** Copilot `dto-guardian` agent validates `contracts/`
- **Validate:** All DTOs immutable, no missing/extra fields, no mutable defaults
- **Fix:** `dto-guardian` agent fixes DTO issues
- **On failure:** Rollback to checkpoint

#### Integration Agent

- **Execute:** Copilot `integration` agent validates cross-module wiring
- **Validate:** No cross-module imports, no DB in modules, deterministic ordering
- **Fix:** `refactor` agent removes violations
- **On failure:** Rollback to checkpoint

#### Global Validation (CRITICAL)

- **Checks:** All quality gates + DTO flow + orchestrator authority
- **Fix:** `refactor` agent (up to 5 remediation attempts)
- **On failure:** System enters `remediation_failed` state — operator intervention required

### Per-Mode Recovery

| Mode   | Failure Scope          | Recovery Action                                         |
| ------ | ---------------------- | ------------------------------------------------------- |
| Mode 1 | Single agent fails     | Rollback that phase. Other agents continue.             |
| Mode 1 | Merge conflict         | Integration agent with bounded retry (up to 5).         |
| Mode 2 | Agent fails mid-group  | Rollback to checkpoint. Earlier commits preserved.      |
| Mode 2 | Context window full    | Split remaining phases into new session.                |
| Mode 3 | Single group fails     | Rollback that group. Other groups continue.             |
| Mode 3 | Merge conflict         | Integration agent with bounded retry.                   |
| All    | Global validation fail | Refactor agent (up to 5). Then: defined `failed` state. |

### Quality Gate Checks (All Modes)

1. **Import check** — Project compiles/imports successfully
2. **Lint check** — No lint errors in modified files
3. **Test check** — Test suite passes
4. **SQL check** — No database driver imports in `app/modules/`
5. **Cross-module check** — No cross-module imports between `app/modules/` packages
6. **Console check** — No unstructured console output in `app/modules/`
7. **DTO validation** — All DTOs in `contracts/` are immutable
8. **Orchestrator integrity** — No database imports in `app/modules/`
9. **Protected files** — Warns if `contracts/`, `database/`, or `docs/` were modified
10. **Deterministic ordering** — No unordered iteration of collections without explicit sorting

Gates 1–8 are **blocking** (cause failure). Gates 9–10 are **advisory**.
