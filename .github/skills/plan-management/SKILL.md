---
name: plan-management
description: "Generate or update a PLAN.md implementation plan for the a2a-brainstorm project. Use for: creating a new plan from scratch from any context (spec, blueprint, Confluence link, problem statement, attachment); adding new tasks to an existing PLAN.md; reviewing a plan for completeness. Produces self-contained task breakdowns that each fit in one chat session, following the Mekari Spec-Driven Development format tailored for Go 1.26 + SvelteKit + A2A."
argument-hint: "create | update | review"
---

# Plan Management

## When to Use

- **create** — User provides a spec, blueprint, RFC, Confluence URL, problem statement, or any context and wants a new `PLAN.md`
- **update** — User wants to add a new task to an existing `PLAN.md` (append to the last task position)
- **review** — User wants to validate that an existing `PLAN.md` covers all details from its source spec

## Reference

Before starting any work, read the full format reference:

- [PLAN.md format + Spec-Driven Development reference](./reference/reference.md)

---

## Codebase Context (always keep in mind)

This project is a **deterministic multi-agent design system**, NOT a chatbot. Key facts:

| Concern          | Decision                                                             |
| ---------------- | -------------------------------------------------------------------- |
| Backend language | Go 1.26, modular monolith + vertical slice                           |
| Agent protocol   | A2A via `a2a-go`                                                     |
| LLM abstraction  | `LLMProvider` interface — GitHub Copilot (default), Claude (future)  |
| Frontend         | SvelteKit (latest stable) + TypeScript + TailwindCSS + Svelte stores |
| Database         | PostgreSQL via pgx / sqlc — no heavy ORM                             |
| Canonical state  | Single JSON state model passed between agents                        |
| Agent roles      | Dynamic (build ↔ review) — role injected per request, not hardcoded  |
| Output artifacts | `architecture.md`, `roadmap.md`                                      |

Directory layout:

```
backend/
  cmd/server/
  internal/platform/   ← http, a2a, llm, db, config, logger
  modules/             ← session, iteration, agent, state, convergence, markdown
agent/
  cmd/server/
  internal/handler/ llm/
frontend/
  src/
    routes/
    lib/components/    ← AgentPanel, ControlPanel, StateView, Timeline
    lib/stores/
    lib/services/
```

---

## Use Case 1: Create a Plan from Scratch

### Input

The user provides one or more of:

- The blueprint file (`docs/A2A-agent-Brainstorm.md`)
- A Confluence URL or page content
- A PRD or feature description
- Any combination of the above

### Procedure

1. **Read the reference** — load `./reference/reference.md` to internalize the format rules before producing any output.

2. **Gather all context** — if the user provides a URL, fetch its content. If they provide a file, read it. Understand the full scope before decomposing.

3. **Understand the system** — identify:
   - Which layer is being built (backend module, agent service, frontend component, platform layer, infra)
   - Which modules are affected (`session`, `iteration`, `agent`, `state`, `convergence`, `markdown`)
   - Whether the task touches the A2A protocol, LLM abstraction, or canonical state model
   - External dependencies and integration points

4. **Decompose into tasks** — apply these rules:
   - Each task must be completable in a **single focused chat session** (~1-3 source files max for code tasks)
   - Tasks must have clear dependencies (no circular deps)
   - The **first task** is always: project scaffold (go.mod, directory structure, docker-compose skeleton)
   - The **last task** is always: integration tests + documentation + final validation checklist
   - Core interfaces (`LLMProvider`, canonical state model, A2A contract) come early — before any feature code
   - Number tasks sequentially: Task 1, Task 2, …Task N

5. **Write Section 8 (Deep Knowledge)** — extract from the blueprint:
   - Canonical state JSON schema (§8 of blueprint)
   - Iteration engine algorithm verbatim (§9 of blueprint)
   - Merge strategy rules (§10 of blueprint)
   - Convergence stop conditions (§11 of blueprint)
   - A2A task contract shape (§7 of blueprint)
   - API endpoints (§12 / §16 of blueprint)
   - All Go interfaces (`LLMProvider`, etc.)

6. **Produce the PLAN.md** — following the exact structure from `./reference/reference.md`:
   - File header (version, date, author, status, source of truth)
   - §1 Goal
   - §2 Architecture Overview (flow diagram + decisions table)
   - §3 Tech Stack
   - §4 Project Structure
   - §5 Implementation Tasks (dependency graph + individual task sections)
   - §6 Task Summary table
   - §7 How to Use This Plan
   - §8 Deep Knowledge Reference

7. **Write the file** — save to `docs/PLAN.md` (or path requested by the user).

8. **Verify** — check the quality checklist from `./reference/reference.md §11` before confirming done.

### Task Section Template (apply for each task)

```markdown
### Task N — {Task Name}

**Goal:** {One sentence describing what this task produces.}

**Files to create:**

- `path/to/file.go` — {description}
  - {key export, interface, or function}
  - {important rule or constraint}
  - {cross-reference to §8.X if detail lives there}

**Validation:**

- {command}: {expected outcome}
- e.g., `go build ./...` compiles cleanly
- e.g., `go vet ./...` zero issues

**Prompt context needed:** {Blueprint sections — e.g., §8 Canonical State, §9 Iteration Engine}

---
```

---

## Use Case 2: Update a Plan — Add a New Task

### Input

The user provides:

- The existing `PLAN.md` (file path or content)
- Context for the new task (blueprint section, feature description, Confluence URL, problem statement)

### Procedure

1. **Read the reference** — load `./reference/reference.md`.

2. **Read the existing PLAN.md** — understand:
   - How many tasks exist (current last task number N?)
   - What the last task covers
   - What the dependency graph looks like
   - What §8 sub-sections already exist (avoid duplicating)

3. **Understand the new task context** — identify:
   - Which module/layer does this task affect? (`session`, `iteration`, `agent`, `state`, `convergence`, `markdown`, `frontend`, `platform`)
   - Which existing task does it depend on?
   - Does it require new deep knowledge entries in §8?

4. **Determine insertion point** — following `./reference/reference.md §10`:
   - New feature task → append after the last feature task, before the existing final validation task
   - New validation/test phase → append after the last existing task
   - In most cases: append a new `### Task N+1` after the current last task

5. **Make all edits atomically**:

   a. **Append the new task** to Section 5 after the last `---` separator.

   b. **Update the dependency graph** — add the new task node.

   c. **Update the Task Summary table** — add a new row.

   d. **Add §8.N sub-sections** if the new task requires knowledge not already in §8.

6. **Do NOT renumber or modify existing tasks** — only append.

7. **Verify** — confirm task count in the dependency graph matches §5 and the Task Summary table.

---

## Use Case 3: Review a Plan for Completeness

### Procedure

1. **Read the reference** — load `./reference/reference.md`.

2. **Read both files**:
   - The PLAN.md
   - `docs/A2A-agent-Brainstorm.md` (the source blueprint)

3. **Check every section** against the quality checklist in `./reference/reference.md §11`.

4. **For each task**, verify:
   - All modules mentioned in the blueprint are covered by some task
   - No task is too large (> 3-4 source files = likely needs splitting)
   - No task depends on a file that hasn't been created yet
   - Validation steps are concrete and runnable (`go build`, `go vet`, `go test`)

5. **Check Section 8** — every schema, algorithm, and rule in the blueprint should have a §8 entry:
   - Canonical state model (§8 of blueprint)
   - Iteration engine loop (§9 of blueprint)
   - Merge strategy rules (§10 of blueprint)
   - Convergence conditions (§11 of blueprint)
   - A2A task contract (§7 of blueprint)
   - All Go interfaces (`LLMProvider`, etc.)

6. **Report findings** — list what is covered well, what is missing, and what should be added. Offer to make updates.

---

## Output Conventions

- **File location:** `docs/PLAN.md` unless the user specifies otherwise
- **Section 8 cross-references:** use `§8.N` notation in task descriptions to point to deep knowledge entries
- **Version:** start at `1.0`; increment minor version for task additions, major for full rewrites
- **Status:** set to `Ready for Implementation` when the plan is complete and verified
- **Complexity:** Low = config/boilerplate, Medium = non-trivial logic, High = complex algorithms or integration-heavy
- **Task granularity:** aim for tasks that take 30–90 minutes in a focused session; never try to fit an entire layer in one task

## Layer-Specific Notes

### Backend tasks (Go)

- Validate with `go build ./...` + `go vet ./...`
- Each vertical slice module gets its own task(s): handler → service → repository → model
- Platform layer (http, a2a, llm, db) always precedes feature modules in the dependency graph

### Agent tasks (Go)

- Agent service is structurally identical to backend — same validation commands
- Role injection logic (`build` | `review`) must be in `internal/handler/`
- LLM call must go through the `LLMProvider` interface — never call Copilot/Claude directly

### Frontend tasks (SvelteKit)

- Validate with `pnpm check` (svelte-check) + `pnpm build`
- Svelte stores replace external state managers (no Zustand, no Redux)
- Components: `AgentPanel.svelte`, `ControlPanel.svelte`, `StateView.svelte`, `Timeline.svelte`
- API calls via `src/lib/services/api/`
