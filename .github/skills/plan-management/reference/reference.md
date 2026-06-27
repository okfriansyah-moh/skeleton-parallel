# Plan Management Reference

This reference documents the canonical PLAN.md format and the Spec-Driven Development process it supports. Every plan generated or updated by the `plan-management` skill **must** conform to this format exactly.

---

## External References

| Source                        | URL / Path                           | Purpose                                       |
| ----------------------------- | ------------------------------------ | --------------------------------------------- |
| Source blueprint              | `docs/<blueprint>.md`                | Canonical system design spec for this project |
| Spec-Driven Development (SDD) | See your team's internal SDD documentation | Engineering process governing task breakdown  |

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
# PLAN.md — {Project Name} Implementation Plan

> **Version:** 1.0
> **Date:** {YYYY-MM-DD}
> **Author:** {team name or individual}
> **Status:** {Draft | Ready for Implementation | In Progress | Completed}
> **Source of Truth:** `docs/<blueprint>.md`
```

**Rules:**

- `Source of Truth` always points to the project's canonical blueprint unless a more specific spec is provided.
- Increment `Version` each time a significant revision is made.
- `Status` must be one of the four values above.

---

## 3. Required Sections (in order)

| #   | Section                  | Required | Purpose                                                 |
| --- | ------------------------ | -------- | ------------------------------------------------------- |
| 1   | Goal                     | ✅       | One paragraph: what is being built and why              |
| 2   | Architecture Overview    | ✅       | Flow diagram + key decisions table                      |
| 3   | Tech Stack               | ✅       | Languages, frameworks, and key dependencies             |
| 4   | Project Structure        | ✅       | Directory tree                                          |
| 5   | Implementation Tasks     | ✅       | Dependency graph + individual task sections             |
| 6   | Task Summary             | ✅       | Table: task, name, files, depends-on, complexity        |
| 7   | How to Use This Plan     | ✅       | Usage instructions for implementers                     |
| 8   | Deep Knowledge Reference | ✅       | Schemas, algorithms, rules extracted from the blueprint |

Section 8 is always required — the blueprint contains canonical state models, algorithms, and rules that every task session needs.

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
| {Decision 1} | {Rationale 1} |
| {Decision 2} | {Rationale 2} |
```

Always include the decisions table — it prevents implementers from second-guessing choices already locked in the blueprint.

---

## 6. Section 5 — Implementation Tasks

### Dependency Graph

Always include a dependency graph before the first task. Use ASCII art. Example:

```
Task 1 (Project Scaffold) ─────────────────────────────────┐
    │                                                         │
    ▼                                                         │
Task 2 (Platform Layer) ──────────┐                          │
    │                              │                          │
    ▼                              ▼                          │
Task 3 (Core Types)          Task 4 (Abstraction Layer)       │
    │                              │                          │
    └──────────────┬───────────────┘                          │
                   ▼                                          │
              Task 5 (Feature Service) ◀───────────────────────┘
                   │
                   ▼
              Task 6 (Feature Modules)
                   │
                   ▼
              Task 7 (Integration Tests + Docs)
```

Adapt the graph to match the actual task list.

### Individual Task Section Format

```markdown
### Task N — {Task Name}

**Goal:** {One sentence: what this task produces.}

**Files to create:**

- `path/to/file` — short description
  - Key exports, interfaces, or functions
  - Important rules or constraints
  - Cross-references to §8.X if detail lives there

**Validation:**

- {command}: {expected outcome}

**Prompt context needed:** {Blueprint section numbers}

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

| Task | Name             | Files                  | Depends On | Est. Complexity |
| ---- | ---------------- | ---------------------- | ---------- | --------------- |
| 1    | Project Scaffold | go.mod, Makefile, …    | —          | Low             |
| 2    | Platform Layer   | internal/platform/*    | Task 1     | Medium          |
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
2. **Validate after each task** — run the validation commands listed in the task before moving to the next
3. **Update this plan** as you learn new information during implementation
4. **One task at a time** — do not attempt multiple tasks in a single session to avoid context overflow
5. **Source of truth** — always refer to `docs/<blueprint>.md` for exact design decisions. This PLAN.md is the breakdown strategy; the blueprint is the specification.
```

---

## 9. Section 8 — Deep Knowledge Reference

Always required. Its purpose is to make every task session **self-contained** — the implementer should never need to re-read the full blueprint.

### What must be in Section 8

Extract from the blueprint whatever is needed for implementation sessions. Common entries:

| §8.N | Typical content                                                    |
| ---- | ------------------------------------------------------------------ |
| 8.1  | Canonical data/state model (schema or type definitions)            |
| 8.2  | Core interfaces or contracts (service interfaces, API shapes)      |
| 8.3  | Protocol or integration contract (request/response shapes)         |
| 8.4  | Core algorithm — verbatim pseudocode                               |
| 8.5  | Merge or reconciliation strategy rules                             |
| 8.6  | Stop/convergence conditions                                        |
| 8.7  | API endpoint definitions                                           |
| 8.8  | Module responsibilities summary                                    |
| 8.9  | Frontend component tree + state shape (if applicable)              |
| 8.10 | Failure modes and mitigations                                      |
| 8.11 | Definition of Done                                                 |

### Structure

```markdown
## 8. Deep Knowledge Reference

This section contains complete schemas, business rules, algorithms, and data flows
from `docs/<blueprint>.md`. Include this section in every task session.

---

### 8.1 Canonical State Model

{Paste verbatim from blueprint}

### 8.2 Core Interfaces

{Interface definitions + request/response types}

### 8.3 Integration Contract

{Protocol or API contract shape}

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

- [ ] Every task has a single, testable **Validation** step
- [ ] No task modifies the same file as another task (or they are explicitly sequenced)
- [ ] Every task lists **Prompt context needed** (blueprint section numbers)
- [ ] Dependency graph matches the task list (no missing arrows, no phantom tasks)
- [ ] Task Summary table matches the task list (same count, same names)
- [ ] Section 8 contains all schemas, algorithms, and rules implementers need
- [ ] The last task covers: integration tests + documentation + final validation checklist
- [ ] `Source of Truth` header points to the project's canonical blueprint
- [ ] `Status` is set correctly
- [ ] Platform/infrastructure tasks precede feature module tasks in the dependency graph

---

## 12. Spec-Driven Development Alignment

| SDD Step                      | PLAN.md Section                                    |
| ----------------------------- | -------------------------------------------------- |
| Define the spec               | Source of Truth header → `docs/<blueprint>.md`     |
| Understand the system         | §1 Goal + §2 Architecture                          |
| Break into shippable tasks    | §5 Implementation Tasks                            |
| Define done criteria per task | §5 Validation steps                                |
| Track dependencies            | §5 Dependency graph                                |
| Preserve deep knowledge       | §8 Deep Knowledge Reference                        |

The key SDD principle: **the blueprint is never modified**. The plan is the working document. If the blueprint changes, a new plan version is created.
