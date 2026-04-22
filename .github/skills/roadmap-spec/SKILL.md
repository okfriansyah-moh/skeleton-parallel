---
name: roadmap-spec
type: skill
description: >
  Execution-grade implementation roadmap standard. Enforces a canonical section
  structure for every phase spec: Objective, BLOCKERS, Scope, Event Types,
  File Structure, Function Contracts, DTO Flow, Worker Flow, Adapter Calls,
  Failure Handling, and Exit Criteria. Use when writing or reviewing any phase
  specification under docs/implementation_roadmap.md or docs/specs/.
  Language-agnostic: works for Python, Go, TypeScript, Node.js, Rust, and Java.
---

# Roadmap Spec — Execution-Grade Standard

Every phase specification MUST contain exactly the eleven sections below, in
order. Missing sections block implementation. Incomplete sections block review.

This skill is **language-agnostic**. All file path placeholders, function
signatures, and test commands are expressed in generic form with a
**Language Reference Table** (see section below) for substitution.

---

## Relationship to the Pipeline

| Component             | How it uses this skill                                                                                                                           |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `phase-builder` agent | Reads `docs/implementation_roadmap.md` and extracts the 11 sections per phase before implementing                                                |
| `run_parallel.sh`     | Dispatches `AGENT_PIPELINE` (phase-builder → dto-guardian → integration → security-auditor → test-builder) per phase; respects `PROTECTED_PATHS` |
| `config/phases.yaml`  | Phase `name`, `complexity`, `group`, and `skills` must match the Objective and Scope in the spec                                                 |
| `PROTECTED_PATHS`     | `contracts/` is additive-only — BLOCKERS may only add new contract files, never modify existing ones                                             |

---

## Canonical Section Order

```
1.  Objective
2.  BLOCKERS
3.  Scope
4.  Event Types
5.  File Structure
6.  Function Contracts
7.  DTO Flow
8.  Worker Flow
9.  Adapter Calls
10. Failure Handling
11. Exit Criteria
```

All eleven sections are **mandatory**. If a section genuinely has no content,
write `N/A — <one-line reason>` rather than omitting it.

---

## Language Reference Table

Use this table to substitute the generic placeholders `{contracts}`, `{module-dir}`,
`{module-entry}`, `{test-file}`, `{test-cmd}`, `{dto-pattern}`, and `{no-random}`
throughout all section templates below.

| Concept             | Python                                   | Go                                       | TypeScript                       | Node.js                                | Rust                                                     | Java                                             |
| ------------------- | ---------------------------------------- | ---------------------------------------- | -------------------------------- | -------------------------------------- | -------------------------------------------------------- | ------------------------------------------------ |
| `{contracts}`       | `contracts/<name>.py`                    | `contracts/contracts.go`                 | `contracts/index.ts`             | `contracts/index.js`                   | `src/contracts/mod.rs`                                   | `src/main/java/com/app/contracts/<Name>DTO.java` |
| `{module-dir}`      | `app/modules/<name>/`                    | `internal/modules/<name>/`               | `src/modules/<name>/`            | `src/modules/<name>/`                  | `src/modules/<name>/`                                    | `src/main/java/com/app/modules/<name>/`          |
| `{module-entry}`    | `__init__.py`                            | `<name>.go`                              | `index.ts`                       | `index.js`                             | `mod.rs`                                                 | `<Name>Service.java`                             |
| `{test-file}`       | `tests/<name>/test_<name>.py`            | `internal/modules/<name>/<name>_test.go` | `tests/<name>.test.ts`           | `tests/<name>.test.js`                 | inline `#[cfg(test)]` in `mod.rs`                        | `src/test/java/…/<Name>Test.java`                |
| `{test-cmd}`        | `pytest tests/ -q`                       | `go test ./...`                          | `npm test`                       | `npm test`                             | `cargo test`                                             | `mvn test`                                       |
| `{dto-pattern}`     | `@dataclass(frozen=True)`                | `struct` (no pointer mutation)           | `readonly interface`             | `Object.freeze({})` / JSDoc `@typedef` | `#[derive(Debug, Clone, Serialize, Deserialize)]` struct | `record` (Java 16+) or `final` fields            |
| `{no-random}`       | no `random`, `uuid4()`, `datetime.now()` | no `rand.Int()`, `time.Now()`            | no `Math.random()`, `Date.now()` | no `Math.random()`, `Date.now()`       | no `rand::random()`                                      | no `new Random()`, `System.currentTimeMillis()`  |
| `{immutable-check}` | `frozen=True` on dataclass               | no pointer receivers on DTOs             | all fields `readonly`            | no property reassignment               | no `&mut` on DTO structs                                 | `record` or all-`final` fields                   |
| `{config-file}`     | `config/pipeline.yaml`                   | `config/pipeline.yaml`                   | `config/pipeline.yaml`           | `config/pipeline.yaml`                 | `config/pipeline.yaml`                                   | `config/pipeline.yaml`                           |
| `{migration-path}`  | `database/migrations/`                   | `database/migrations/`                   | `database/migrations/`           | `database/migrations/`                 | `database/migrations/`                                   | `database/migrations/`                           |

> **Rule:** Pick one language per project. Use that column throughout **all** phases in the roadmap.
> Never mix paths from different language columns in the same spec.

---

## Section Definitions

### 1. Objective

One paragraph. State:

- What this phase builds
- Why it exists in the pipeline (what problem it solves)
- What the downstream consumer receives

**Anti-patterns:**

- Vague goals ("improve the system")
- Referencing implementation details (defer to Function Contracts)
- Listing tasks (defer to Worker Flow)

> **phases.yaml alignment:** The `name` field in `config/phases.yaml` for this
> phase must clearly derive from the Objective's module name (kebab-case).

**Template:**

```markdown
### Objective

Implement [module/stage name] that [verb: processes / validates / transforms / persists]
[input description] into [output description]. This stage exists to [pipeline purpose].
The downstream [consumer name] receives [OutputDTO name].
```

---

### 2. BLOCKERS

Explicit hard dependencies that MUST exist before implementation starts.
List each blocker as a checkbox. The `phase-builder` agent treats unchecked
blockers as a hard gate — it will not implement the phase until all are resolved.

**Include:**

- Upstream DTOs that must be defined first (`contracts/` — additive-only protected path)
- Database migrations that must be applied
- Config keys that must exist in `{config-file}`
- Other phases that must reach exit criteria

> `contracts/` is a **protected path** in `run_parallel.sh`. New DTOs may be
> added but existing fields MUST NOT be modified.

**Template:**

```markdown
### BLOCKERS

- [ ] `{contracts}` — `UpstreamDTO` must be defined (additive-only — do not modify existing fields)
- [ ] `{migration-path}YYYYMMDD000NNN_<name>.sql` — table `<name>` must exist
- [ ] `{config-file}` — key `<section>.<key>` must be present
- [ ] Phase 0 complete — database adapter must be operational
```

---

### 3. Scope

Define the boundary of this phase. State what is IN scope and what is
explicitly OUT of scope. Prevents scope creep and sets reviewer expectations.

> **phases.yaml alignment:** The `group` field determines which phases may run
> in parallel. Scopes within the same group must own **disjoint file sets**.

**Template:**

```markdown
### Scope

**In scope:**

- [Behavior A this phase owns]
- [Behavior B this phase owns]

**Out of scope:**

- [Thing that belongs to Phase N — different group]
- [Thing that belongs to a future enhancement]
```

---

### 4. Event Types

List every domain event, message type, trigger condition, or signal that this
phase produces or consumes. If the phase has no events, write `N/A`.

For sequential batch pipelines (no event bus): list the DTO status transitions
that act as implicit "events" (e.g., state machine transitions written to DB
by the orchestrator after this phase completes).

**Template:**

```markdown
### Event Types

| Event / Trigger      | Direction | Description                             |
| -------------------- | --------- | --------------------------------------- |
| `<EventName>`        | Consumed  | Triggers processing when received       |
| `<OutputDTO>.status` | Produced  | Status transition written to DB by orch |
| `<OutputDTO>`        | Produced  | Passed to downstream stage              |
```

---

### 5. File Structure

Exact file tree for every file this phase creates or modifies.
Use `(create)` or `(modify)` annotations.
Substitute `{module-dir}`, `{module-entry}`, `{contracts}`, and `{test-file}`
from the **Language Reference Table** (above).

**Template (language-agnostic — substitute paths from table):**

```markdown
### File Structure

{module-dir} (create)
├── {module-entry} (create) — public process() entry point
└── <core-logic>.<ext> (create) — main processing logic

{contracts} (create) — OutputDTO definition

{migration-path}YYYYMMDD000NNN\_<name>.sql (create) — new table if needed

{test-file} (create) — unit tests
{test-file (integration variant)} (create) — integration tests
```

**Per-language examples:**

<details>
<summary>Python</summary>

```
app/modules/<name>/
├── __init__.py          (create) — exposes process()
└── <name>.py            (create) — core logic
contracts/<name>.py      (create) — OutputDTO
database/migrations/
└── YYYYMMDD000NNN_<name>.sql    (create)
tests/<name>/
├── test_<name>.py       (create)
└── integration/
    └── test_<name>_integration.py  (create)
```

</details>

<details>
<summary>Go</summary>

```
internal/modules/<name>/
├── <name>.go            (create) — exposes Process()
└── internal/
    └── <logic>.go       (create) — private helpers
contracts/contracts.go   (modify, additive) — add OutputDTO struct
database/migrations/
└── YYYYMMDD000NNN_<name>.sql    (create)
internal/modules/<name>/<name>_test.go  (create)
```

</details>

<details>
<summary>TypeScript</summary>

```
src/modules/<name>/
├── index.ts             (create) — exposes process()
└── feature/<name>/
    └── index.ts         (create) — core logic
contracts/index.ts       (modify, additive) — add OutputDTO interface
database/migrations/
└── YYYYMMDD000NNN_<name>.sql    (create)
tests/<name>.test.ts     (create)
```

</details>

<details>
<summary>Node.js</summary>

```
src/modules/<name>/
├── index.js             (create) — exposes process()
└── feature/<name>/
    └── index.js         (create) — core logic
contracts/index.js       (modify, additive) — export OutputDTO shape
database/migrations/
└── YYYYMMDD000NNN_<name>.sql    (create)
tests/<name>.test.js     (create)
```

</details>

<details>
<summary>Rust</summary>

```
src/modules/<name>/
└── mod.rs               (create) — exposes pub fn process()
src/contracts/mod.rs     (modify, additive) — add OutputDTO struct
database/migrations/
└── YYYYMMDD000NNN_<name>.sql    (create)
(tests inline in src/modules/<name>/mod.rs via #[cfg(test)])
```

</details>

<details>
<summary>Java</summary>

```
src/main/java/com/app/modules/<name>/
├── <Name>Service.java   (create) — exposes process()
└── <Name>Handler.java   (create) — optional HTTP handler
src/main/java/com/app/contracts/<Name>OutputDTO.java   (create)
database/migrations/
└── YYYYMMDD000NNN_<name>.sql    (create)
src/test/java/com/app/modules/<name>/<Name>ServiceTest.java  (create)
```

</details>

---

### 6. Function Contracts

Public-facing function signatures for every exported function in this phase.
Include: name, parameters (with types), return type, and one-line docstring.
No implementation details — only the interface.

All parameters and return types MUST use DTO types from `{contracts}`.
No raw maps, dicts, `Any`, or untyped parameters on public functions.

**Template — pick the block matching the project language:**

<details>
<summary>Python</summary>

```python
def process(
    input: InputDTO,
    config: PipelineConfig,
) -> OutputDTO:
    """Transform InputDTO into OutputDTO. Raises ValueError on invalid input."""

def validate(input: InputDTO) -> None:
    """Raise ValueError if input violates constraints. No-op if valid."""
```

</details>

<details>
<summary>Go</summary>

```go
// Process transforms InputDTO into OutputDTO.
// Returns error if input violates constraints.
func Process(ctx context.Context, input contracts.InputDTO, cfg config.Config) (contracts.OutputDTO, error)

// Validate returns error if input violates constraints, nil otherwise.
func Validate(input contracts.InputDTO) error
```

</details>

<details>
<summary>TypeScript</summary>

```typescript
// Transforms InputDTO into OutputDTO. Throws on invalid input.
export function process(input: InputDTO, config: PipelineConfig): OutputDTO;

// Throws if input violates constraints. No-op if valid.
export function validate(input: InputDTO): void;
```

</details>

<details>
<summary>Node.js</summary>

```javascript
/**
 * @param {InputDTO} input
 * @param {PipelineConfig} config
 * @returns {OutputDTO}
 */
function process(input, config) {}

/**
 * @param {InputDTO} input
 * @throws {Error} if input violates constraints
 */
function validate(input) {}
```

</details>

<details>
<summary>Rust</summary>

```rust
/// Transform InputDTO into OutputDTO.
/// Returns Err if input violates constraints.
pub fn process(input: InputDTO, cfg: &Config) -> Result<OutputDTO, ProcessError>;

/// Returns Err if input violates constraints, Ok(()) otherwise.
pub fn validate(input: &InputDTO) -> Result<(), ValidationError>;
```

</details>

<details>
<summary>Java</summary>

```java
/**
 * Transforms InputDTO into OutputDTO.
 * @throws IllegalArgumentException if input violates constraints
 */
public OutputDTO process(InputDTO input, PipelineConfig config);

/**
 * @throws IllegalArgumentException if input violates constraints
 */
public void validate(InputDTO input);
```

</details>

---

### 7. DTO Flow

Show exactly which DTO enters and which DTO exits this phase.
Trace field-level mapping: input field → transformation → output field.
Identify which fields are computed vs. passed through.

All DTOs MUST be immutable per `{dto-pattern}` for the project language.

**Template:**

```markdown
### DTO Flow

**Input:** `InputDTO` (from `{contracts}` — upstream module)
**Output:** `OutputDTO` (defined in `{contracts}` — this module)

| Input Field        | Transformation              | Output Field          |
| ------------------ | --------------------------- | --------------------- |
| `input.entity_id`  | pass-through                | `output.entity_id`    |
| `input.raw_data`   | parse + normalize           | `output.items[]`      |
| `input.source_url` | SHA256(url)[:16]            | `output.source_id`    |
| —                  | computed: `"completed"`     | `output.status`       |
| —                  | computed: CURRENT_TIMESTAMP | `output.processed_at` |
```

> `entity_id` MUST be content-addressable: `SHA256(content_signature)[:16]`.
> Never use random UUIDs, timestamps, or auto-increment for entity identity.

---

### 8. Worker Flow

Step-by-step execution sequence inside the module. Written as numbered
pseudocode steps — **language-agnostic**.

This section is intentionally language-neutral. The `phase-builder` agent
translates these steps into the project language when implementing.

**Template:**

```markdown
### Worker Flow

1. Receive `InputDTO` from orchestrator
2. Validate input fields — raise error on constraint violation (see Failure Handling)
3. [Core processing step A]
4. [Core processing step B — e.g., parse, transform, enrich]
5. Build `OutputDTO` from processed results
6. Return `OutputDTO` to orchestrator — do NOT write to DB here

> Modules are pure functions: DTO in → DTO out → no side effects on shared state.
> The orchestrator calls the adapter AFTER receiving the output DTO.
```

---

### 9. Adapter Calls

List every database adapter call the **orchestrator** makes for this phase.
Modules themselves make **zero** adapter calls.
All calls route through `database/adapter.<ext>` — the single adapter boundary.

**Template:**

```markdown
### Adapter Calls

| Timing        | Method                          | Purpose                             |
| ------------- | ------------------------------- | ----------------------------------- |
| Before module | `adapter.get_entity(entity_id)` | Load entity state to build InputDTO |
| Before module | `adapter.update_run_stage()`    | Checkpoint: mark stage as started   |
| After module  | `adapter.upsert_<result>()`     | Persist OutputDTO fields to DB      |
| After module  | `adapter.update_run_stage()`    | Checkpoint: mark stage as completed |

> All writes use `ON CONFLICT (<pk>) DO NOTHING` / upsert semantics.
> Every call is idempotent — safe to retry on failure.
```

---

### 10. Failure Handling

Define behavior for every failure mode in this phase. Specify: what fails,
what the orchestrator does, whether to retry, and what state is written.

Retry limits come from `run_parallel.sh` environment variables:

| Variable                    | Default | Applies to                         |
| --------------------------- | ------- | ---------------------------------- |
| `MAX_RETRIES_PHASE_BUILDER` | 5       | phase-builder agent retries        |
| `MAX_RETRIES_INTEGRATION`   | 5       | integration agent retries          |
| `MAX_REMEDIATION_RETRIES`   | 3       | refactor/remediation agent retries |

**Template:**

```markdown
### Failure Handling

| Failure                    | Orchestrator Action    | Retry | State Written               |
| -------------------------- | ---------------------- | ----- | --------------------------- |
| Validation error (input)   | Abort run              | No    | `run.status = "failed"`     |
| Timeout (> threshold)      | Retry up to N times    | Yes   | `run.status = "processing"` |
| Unexpected exception       | Abort, log full trace  | No    | `run.status = "failed"`     |
| Partial output (N/M items) | Mark partial, continue | —     | `run.status = "partial"`    |

> On abort: orchestrator writes error message to `run.error_detail`.
> On restart: orchestrator reads `last_completed_stage` and skips already-completed
> stages — idempotent checkpoint-resume.
> Timeout threshold must come from `{config-file}` — never hardcoded.
```

---

### 11. Exit Criteria

Checklist of verifiable conditions that define "this phase is done".
Every item must be binary (pass/fail). No vague qualitative items.

The `phase-builder` agent marks a phase complete only when all items are checked.
The `dto-guardian`, `integration`, `security-auditor`, and `test-builder` agents
validate these criteria before the phase is merged.

**Template:**

```markdown
### Exit Criteria

**Correctness**

- [ ] Module accepts `InputDTO`, returns `OutputDTO` with all fields populated
- [ ] All DTO fields match types defined in `{contracts}`
- [ ] DTOs are immutable: `{dto-pattern}` applied to all new DTOs

**Boundaries**

- [ ] No cross-module imports — module imports only from `contracts/` and stdlib
- [ ] No database access inside module code
- [ ] No direct import of any DB driver inside `{module-dir}`

**Idempotency**

- [ ] Re-running on same input produces identical output
- [ ] No duplicate rows after two identical runs (`ON CONFLICT DO NOTHING`)
- [ ] `entity_id` is content-addressable: `SHA256(content_signature)[:16]`

**Determinism**

- [ ] Same input + same config = byte-identical output DTO
- [ ] `{no-random}` — none present in module code

**Tests**

- [ ] Unit tests pass without network, GPU, or real data files
- [ ] Integration test covers happy path end-to-end
- [ ] All new tests pass: `{test-cmd}`

**Config**

- [ ] All thresholds, timeouts, and paths sourced from `{config-file}`
- [ ] No hardcoded magic numbers in module code

**Parallel Safety** (if phase runs in a parallel group per `config/phases.yaml`)

- [ ] Phase owns only the files listed in File Structure — no writes to other modules' paths
- [ ] No modification to existing DTO fields in `contracts/` (additive only)
```

---

## Complete Phase Template

Copy this block when writing a new phase spec. Substitute `{…}` with values
from the **Language Reference Table** (above).

> **phases.yaml:** After writing this spec, add the corresponding entry to
> `config/phases.yaml` with matching `name`, `complexity`, `group`, and `skills`.

````markdown
## Phase N — [Stage Name]

**Priority:** P1
**Owns:** `{module-dir}`, `{contracts}`

### Objective

<!-- One paragraph: what it builds, why it exists, what downstream consumer receives -->

### BLOCKERS

- [ ] `{contracts}` — `UpstreamDTO` must be defined (additive-only)
- [ ] `{migration-path}YYYYMMDD000NNN_<name>.sql` — table `<name>` must exist
- [ ] `{config-file}` — key `<section>.<key>` must be present
- [ ] Phase 0 complete — adapter must be operational

### Scope

**In scope:**

- <!-- behavior A -->

**Out of scope:**

- <!-- belongs to Phase N or future enhancement -->

### Event Types

| Event / Trigger    | Direction | Description               |
| ------------------ | --------- | ------------------------- |
| `InputDTO`         | Consumed  | Passed in by orchestrator |
| `OutputDTO.status` | Produced  | Written to DB by orch     |

### File Structure

```
{module-dir}
├── {module-entry}                  (create) — public process() entry point
└── <core-logic>.<ext>              (create) — main processing logic
{contracts}                         (create) — OutputDTO definition
{migration-path}YYYYMMDD000NNN_<name>.sql   (create)
{test-file}                         (create) — unit tests
```

### Function Contracts

```
process(input: InputDTO, config: PipelineConfig) -> OutputDTO
    // Transform input into output. Raise/return error on invalid input.

validate(input: InputDTO) -> void / None / error
    // Validate constraints. No-op / return nil if valid.
```

### DTO Flow

**Input:** `InputDTO` (from `{contracts}` — Phase N-1)
**Output:** `OutputDTO` (defined in `{contracts}` — this phase)

| Input Field | Transformation | Output Field |
| ----------- | -------------- | ------------ |
|             |                |              |

### Worker Flow

1. Receive `InputDTO` from orchestrator
2. Validate — raise error on constraint violation
3. [Core logic]
4. Build and return `OutputDTO`

### Adapter Calls

| Timing        | Method                       | Purpose                    |
| ------------- | ---------------------------- | -------------------------- |
| Before module | `adapter.get_*()`            | Load state, build InputDTO |
| Before module | `adapter.update_run_stage()` | Checkpoint: started        |
| After module  | `adapter.upsert_*()`         | Persist OutputDTO          |
| After module  | `adapter.update_run_stage()` | Checkpoint: completed      |

### Failure Handling

| Failure              | Orchestrator Action                 | Retry | State Written               |
| -------------------- | ----------------------------------- | ----- | --------------------------- |
| Validation error     | Abort                               | No    | `run.status = "failed"`     |
| Unexpected exception | Abort, log trace                    | No    | `run.status = "failed"`     |
| Timeout              | Retry ≤ `MAX_RETRIES_PHASE_BUILDER` | Yes   | `run.status = "processing"` |

### Exit Criteria

- [ ] Module accepts `InputDTO`, returns `OutputDTO`
- [ ] DTOs immutable: `{dto-pattern}`
- [ ] No cross-module imports — only `contracts/` and stdlib
- [ ] No DB access inside module
- [ ] Idempotent: re-run produces no duplicates
- [ ] Deterministic: same input + same config = same output; `{no-random}`
- [ ] All tests pass: `{test-cmd}`
- [ ] All thresholds from `{config-file}` — no magic numbers
````

---

## phases.yaml Alignment Checklist

After writing a phase spec, verify the corresponding `config/phases.yaml` entry:

```yaml
phases:
  N:
    name: "<matches Objective's module name — kebab-case>"
    complexity: <1-10, higher = assigned heavier model in parallel mode>
    group: "<A-Z — same group = sequential; different group = parallel-safe>"
    skills: "<comma-separated skills this phase requires>"
```

- [ ] `name` matches the phase title in `docs/implementation_roadmap.md`
- [ ] `group` reflects the BLOCKERS dependency chain (phases with shared blockers in same group)
- [ ] `skills` includes all skills referenced in this phase's spec
- [ ] `complexity` reflects the scope (Phase 0 infrastructure = 8+, simple transform = 3-5)

---

## Checklist — Before Handing Off to `phase-builder`

- [ ] All 11 sections present, none omitted
- [ ] No `TBD` or `TODO` placeholders remain
- [ ] BLOCKERS are resolved or tracked as open issues
- [ ] Language column chosen from the **Language Reference Table** (above) and applied consistently
- [ ] DTO Flow table has no empty rows
- [ ] Adapter Calls table names exact method signatures
- [ ] Exit Criteria items are all binary (pass/fail verifiable)
- [ ] File Structure uses `(create)` / `(modify)` annotations
- [ ] Function Contracts use typed signatures with DTO types only (no raw dicts/maps/Any)
- [ ] `config/phases.yaml` entry added or updated for this phase
- [ ] No existing `contracts/` fields modified (additive-only protected path)
