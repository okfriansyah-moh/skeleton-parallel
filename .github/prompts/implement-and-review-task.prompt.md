# Implement And Review Task

## Use

Implement, self-review, remediate, and report one task from `docs/PLAN.md` in a single run.

## Inputs

- `.github/agents/task-runner.agent.md`
- `docs/PLAN.md`
- relevant docs listed under the task's `Prompt context needed`
- task number: `{{TASK_NUMBER}}`

## Instructions

1. Read `docs/PLAN.md` and extract `### Task {{TASK_NUMBER}}` only.
2. Build an ownership checklist from that task's `Files to create` section.
3. Load only relevant deep-knowledge references (`§8.X`) needed for this task.
4. Implement task scope fully in owned files only.
5. Run all task validation commands exactly as listed.
6. Self-review for:
   - PLAN compliance
   - file ownership violations
   - security and secrets safety
   - lint/build/test health
7. Fix findings immediately if in scope.
8. Re-run validation after fixes.
9. Mark task complete in `docs/PLAN.md` using:
   - `<!-- ✅ Task {{TASK_NUMBER}} completed -->`
10. Report:

- changed files
- validations run + outcomes
- blockers or deferred items

## Check

- single-task scope respected
- no edits outside owned files
- validation commands executed and passing (or blocker documented)
- completion marker added to `docs/PLAN.md`
