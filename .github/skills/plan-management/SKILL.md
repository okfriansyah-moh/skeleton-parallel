---
name: plan-management
description: "Generate or update a PLAN.md implementation plan. Use for: creating a new plan from scratch from any context (spec, blueprint, Confluence link, problem statement, attachment); adding new tasks to an existing PLAN.md; reviewing a plan for completeness. Produces self-contained task breakdowns that each fit in one chat session, following the Spec-Driven Development format."
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

## Use Case 1: Create a Plan from Scratch

### Input

The user provides one or more of:

- A blueprint or spec file
- A Confluence URL or page content
- A PRD or feature description
- Any combination of the above

### Procedure

1. **Read the reference** — load `./reference/reference.md` to internalize the format rules before producing any output.

2. **Gather all context** — if the user provides a URL, fetch its content. If they provide a file, read it. Understand the full scope before decomposing.

3. **Understand the system** — identify:
   - Which layers or modules are being built
   - Key interfaces, contracts, and integration points
   - External dependencies

4. **Decompose into tasks** — apply these rules:
   - Each task must be completable in a **single focused chat session** (~1-3 source files max for code tasks)
   - Tasks must have clear dependencies (no circular deps)
   - The **first task** is always: project scaffold (config, directory structure, build skeleton)
   - The **last task** is always: integration tests + documentation + final validation checklist
   - Core interfaces and contracts come early — before any feature code
   - Number tasks sequentially: Task 1, Task 2, …Task N

5. **Write Section 8 (Deep Knowledge)** — extract from the blueprint whatever implementers need:
   - Canonical data/state model
   - Core algorithms verbatim
   - Integration contracts and API shapes
   - Failure modes and stop conditions
   - All interface definitions

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

- `path/to/file` — {description}
  - {key export, interface, or function}
  - {important rule or constraint}
  - {cross-reference to §8.X if detail lives there}

**Validation:**

- {command}: {expected outcome}

**Prompt context needed:** {Blueprint sections}

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
   - Which module or layer does this task affect?
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
   - The source blueprint referenced in the plan's `Source of Truth` header

3. **Check every section** against the quality checklist in `./reference/reference.md §11`.

4. **For each task**, verify:
   - All modules mentioned in the blueprint are covered by some task
   - No task is too large (> 3-4 source files = likely needs splitting)
   - No task depends on a file that hasn't been created yet
   - Validation steps are concrete and runnable

5. **Check Section 8** — every schema, algorithm, and rule in the blueprint should have a §8 entry covering at minimum:
   - Canonical data/state model
   - Core algorithm or iteration logic
   - Integration contracts
   - All interface definitions

6. **Report findings** — list what is covered well, what is missing, and what should be added. Offer to make updates.

---

## Output Conventions

- **File location:** `docs/PLAN.md` unless the user specifies otherwise
- **Section 8 cross-references:** use `§8.N` notation in task descriptions to point to deep knowledge entries
- **Version:** start at `1.0`; increment minor version for task additions, major for full rewrites
- **Status:** set to `Ready for Implementation` when the plan is complete and verified
- **Complexity:** Low = config/boilerplate, Medium = non-trivial logic, High = complex algorithms or integration-heavy
- **Task granularity:** aim for tasks that take 30–90 minutes in a focused session; never try to fit an entire layer in one task
