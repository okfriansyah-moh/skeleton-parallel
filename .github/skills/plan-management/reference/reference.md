# Plan Management Reference — a2a-brainstorm

This reference documents the canonical PLAN.md format for the `a2a-brainstorm` project and the Spec-Driven Development process it supports. Every plan generated or updated by the `plan-management` skill **must** conform to this format exactly.

---

## External References

| Source                        | URL / Path                                                                             | Purpose                                       |
| ----------------------------- | -------------------------------------------------------------------------------------- | --------------------------------------------- |
| Source blueprint              | `docs/A2A-agent-Brainstorm.md`                                                         | Canonical system design spec for this project |
| Spec-Driven Development (SDD) | https://jurnal.atlassian.net/wiki/spaces/DFS/pages/50632556624/Spec-Driven+Development | engineering process governing task breakdown  |

---

## 1. PLAN.md File Naming & Location

| Scenario              | Path                     |
| --------------------- | ------------------------ |
| Single plan (default) | `docs/PLAN.md`           |
| Feature-specific plan | `docs/PLAN-<feature>.md` |

Always use `PLAN.md` (uppercase) so it is easy to discover.

---

## 2. File Header

Every PLAN.md begins with a metadata block using blockquote syntax:

```markdown
# PLAN.md — a2a-brainstorm Implementation Plan

> **Version:** 1.0
> **Date:** {YYYY-MM-DD}
> **Author:** {team name or individual}
> **Status:** {Draft | Ready for Implementation | In Progress | Completed}
> **Source of Truth:** `docs/A2A-agent-Brainstorm.md`
```

**Rules:**

- `Source of Truth` always points to `docs/A2A-agent-Brainstorm.md` unless a more specific spec is provided.
- Increment `Version` each time a significant revision is made.
- `Status` must be one of the four values above.

---

## 3. Required Sections (in order)

| #   | Section                  | Required | Purpose                                                 |
| --- | ------------------------ | -------- | ------------------------------------------------------- |
| 1   | Goal                     | ✅       | One paragraph: what is being built and why              |
| 2   | Architecture Overview    | ✅       | Flow diagram + key decisions table                      |
| 3   | Tech Stack               | ✅       | Go, SvelteKit, A2A, PostgreSQL dependencies             |
| 4   | Project Structure        | ✅       | Directory tree                                          |
| 5   | Implementation Tasks     | ✅       | Dependency graph + individual task sections             |
| 6   | Task Summary             | ✅       | Table: task, name, files, depends-on, complexity        |
| 7   | How to Use This Plan     | ✅       | Usage instructions for implementers                     |
| 8   | Deep Knowledge Reference | ✅       | Schemas, algorithms, rules extracted from the blueprint |

Section 8 is always required for this project — the blueprint contains the canonical state model, iteration algorithm, merge strategy, and convergence rules that every task session needs.

---

## 4. Section 1 — Goal

```markdown
## 1. Goal

{One clear paragraph: what is being built, who uses it, what problem it solves.}

{Optional: phase breakdown as bullet list}

**Why:** {One sentence explaining the product need.}
```

---

## 5. Section 2 — Architecture Overview

```markdown
## 2. Architecture Overview
```

{ASCII flow diagram showing the full system}

```

**Key architectural decisions (non-negotiable):**

| Decision | Rationale |
|---|---|
| Modular monolith (backend) | Single deployable; avoids distributed complexity at MVP |
| Vertical slice per module | Each module owns handler + service + repository + model |
| Role-fluid agents | Role (build/review) injected per iteration, not hardcoded |
| LLMProvider interface | Decouples Copilot/Claude from business logic |
| Svelte stores (no external state lib) | SvelteKit-native; avoids JS bundle bloat |
| pgx / sqlc (no heavy ORM) | Performance; type-safe queries; idiomatic Go |
```

Always include the decisions table — it prevents implementers from second-guessing choices already locked in the blueprint.

---

## 6. Section 5 — Implementation Tasks

### Dependency Graph

Always include a dependency graph before the first task. Use ASCII art. Example for this project:

```
Task 1 (Project Scaffold) ─────────────────────────────────┐
    │                                                         │
    ▼                                                         │
Task 2 (Platform Layer) ──────────┐                          │
    │                              │                          │
    ▼                              ▼                          │
Task 3 (State + Types)       Task 4 (LLM Abstraction)        │
    │                              │                          │
    └──────────────┬───────────────┘                          │
                   ▼                                          │
              Task 5 (Agent Service) ◀────────────────────────┘
                   │
                   ▼
              Task 6 (Backend Modules: session/iteration/…)
                   │
                   ▼
              Task 7 (Frontend: SvelteKit)
                   │
                   ▼
              Task 8 (Integration Tests + Docs)
```

Adapt the graph to match the actual task list.

### Individual Task Section Format

```markdown
### Task N — {Task Name}

**Goal:** {One sentence: what this task produces.}

**Files to create:**

- `path/to/file.go` — short description
  - Key exports, interfaces, or functions
  - Important rules or constraints
  - Cross-references to §8.X if detail lives there

**Validation:**

- `go build ./...`: zero build errors
- `go vet ./...`: zero vet issues
- (frontend) `pnpm check`: zero svelte-check errors
- (frontend) `pnpm build`: clean production build

**Prompt context needed:** {Blueprint section numbers — e.g., §8 Canonical State, §9 Iteration Engine}

---
```

**Rules:**

- Each task must be completable in a **single focused chat session** — if it cannot, split it.
- Each task must have a **clear, testable validation step**.
- Tasks must never share files — if two tasks modify the same file, merge or sequence them.
- The last task always covers: integration tests + documentation + final validation checklist.
- **`Prompt context needed`** lists exactly which blueprint sections to attach to the session.

---

## 7. Section 6 — Task Summary Table

```markdown
## 6. Task Summary

| Task | Name             | Files                                | Depends On | Est. Complexity |
| ---- | ---------------- | ------------------------------------ | ---------- | --------------- |
| 1    | Project Scaffold | go.mod, docker-compose.yml, Makefile | —          | Low             |
| 2    | Platform Layer   | internal/platform/\*                 | Task 1     | Medium          |
```

**Complexity guide:**

- **Low:** Boilerplate or config; minimal logic
- **Medium:** Non-trivial logic; some integration points
- **High:** Complex algorithms, many integration points, or security-critical code

---

## 8. Section 7 — How to Use This Plan

Always include exactly this block (update the source of truth path):

```markdown
## 7. How to Use This Plan

1. **Start each task in a fresh chat session** — share this PLAN.md + the relevant blueprint sections listed under "Prompt context needed"
2. **Validate after each task** — run `go build ./...` + `go vet ./...` (backend/agent) or `pnpm check` + `pnpm build` (frontend) before moving to the next task
3. **Update this plan** as you learn new information during implementation
4. **One task at a time** — do not attempt multiple tasks in a single session to avoid context overflow
5. **Source of truth** — always refer to `docs/A2A-agent-Brainstorm.md` for exact design decisions. This PLAN.md is the breakdown strategy; the blueprint is the specification.
```

---

## 9. Section 8 — Deep Knowledge Reference

Always required for this project. Its purpose is to make every task session **self-contained** — the implementer should never need to re-read the full blueprint.

### What must be in Section 8 for this project

| §8.N | Content to extract from blueprint                                          |
| ---- | -------------------------------------------------------------------------- |
| 8.1  | Canonical state JSON schema (blueprint §8)                                 |
| 8.2  | Go interfaces: `LLMProvider`, `LLMRequest`, `LLMResponse` (blueprint §5.2) |
| 8.3  | A2A task contract shape (blueprint §7 — `task_id`, `role`, `state`)        |
| 8.4  | Iteration engine algorithm — verbatim pseudocode (blueprint §9)            |
| 8.5  | Merge strategy rules (blueprint §10)                                       |
| 8.6  | Convergence stop conditions (blueprint §11)                                |
| 8.7  | API endpoint definitions (blueprint §12 / §16)                             |
| 8.8  | Module responsibilities summary (blueprint §6)                             |
| 8.9  | Frontend component tree + Svelte store shape (blueprint §13–§15)           |
| 8.10 | Failure modes and mitigations (blueprint §17)                              |
| 8.11 | Definition of Done                                                         |

### Structure

```markdown
## 8. Deep Knowledge Reference

This section contains complete schemas, business rules, algorithms, and data flows
from `docs/A2A-agent-Brainstorm.md`. Include this section in every task session.

---

### 8.1 Canonical State Model

{Paste verbatim from blueprint §8}

### 8.2 Go Interfaces

{LLMProvider interface + request/response types}

### 8.3 A2A Task Contract

{JSON shape of task request/response}

...
```

---

## 10. Adding a New Task (Update Flow)

When adding a task to an existing PLAN.md:

1. **Append to Section 5** — add the new `### Task N+1` block after the last existing task.
2. **Update the dependency graph** — add the new task node and its arrow.
3. **Update Section 6 (Task Summary table)** — add a new row.
4. **Update Section 8 if needed** — add a new §8.N sub-section only if the task requires knowledge not already covered.
5. **Do NOT renumber existing tasks** — append only; existing task numbers must never change.

### Determining where to add

- New feature that extends an existing module → append after that module's task, before the final validation task
- New integration test phase → append after all feature tasks
- In most cases: append to the end of Section 5

---

## 11. Quality Checklist Before Finalising a Plan

- [ ] Every task has a single, testable **Validation** step (`go build`, `go vet`, `pnpm check`, or equivalent)
- [ ] No task modifies the same file as another task (or they are explicitly sequenced)
- [ ] Every task lists **Prompt context needed** (blueprint section numbers)
- [ ] Dependency graph matches the task list (no missing arrows, no phantom tasks)
- [ ] Task Summary table matches the task list (same count, same names)
- [ ] Section 8 contains: canonical state model, iteration algorithm, merge rules, convergence conditions, all Go interfaces, A2A contract
- [ ] The last task covers: integration tests + documentation + final validation checklist
- [ ] `Source of Truth` header points to `docs/A2A-agent-Brainstorm.md`
- [ ] `Status` is set correctly
- [ ] Platform layer tasks precede all feature module tasks in the dependency graph
- [ ] Agent service task precedes backend module tasks that call agents

---

## 12. Spec-Driven Development Alignment

| SDD Step                      | PLAN.md Section                                         |
| ----------------------------- | ------------------------------------------------------- |
| Define the spec               | Source of Truth header → `docs/A2A-agent-Brainstorm.md` |
| Understand the system         | §1 Goal + §2 Architecture                               |
| Break into shippable tasks    | §5 Implementation Tasks                                 |
| Define done criteria per task | §5 Validation steps                                     |
| Track dependencies            | §5 Dependency graph                                     |
| Preserve deep knowledge       | §8 Deep Knowledge Reference                             |

The key SDD principle: **the blueprint is never modified**. The plan is the working document. If the blueprint changes, a new plan version is created.
