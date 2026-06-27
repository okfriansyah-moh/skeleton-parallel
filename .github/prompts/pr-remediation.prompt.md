# PR Remediation

## Use

Review a pull request diff for this repository and produce concise, actionable remediation guidance tied to repo invariants.

## Inputs

- PR title and description
- changed files and key diff snippets
- failing tests, lints, or review comments
- `docs/PLAN.md` (task ownership and acceptance expectations)
- `.github/copilot-instructions.md` (architecture invariants and protected-path rules)

## Instructions

1. Classify each issue by severity:
   - `critical`: data loss, security, broken build, invariant violation
   - `major`: functional bug, incorrect behavior, missing required tests
   - `minor`: maintainability, readability, non-blocking polish
2. Validate changes against repo rules:
   - modular monolith boundaries
   - deterministic/idempotent behavior
   - protected paths and additive-only constraints
   - PLAN task ownership and completion semantics
3. For each finding, provide:
   - exact file path
   - concise root cause
   - minimal concrete remediation step
4. Prefer smallest safe fixes; avoid broad rewrites.
5. If no blocking issues are found, explicitly state that and list residual risks.

## Output Format

1. Findings (ordered by severity)
2. Open questions / assumptions
3. Minimal remediation plan

## Check

- output is concise and actionable
- each finding references a real file/location
- recommendations map to repository invariants
- no generic advice without a concrete next action
