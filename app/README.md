# Application Code

> Single-process modular monolith. Each pipeline stage is a module under `app/modules/`.

## Structure

```
app/
├── main.*               # Entry point (language-specific) — parses args, calls orchestrator
├── orchestrator/        # Pipeline orchestration + checkpointing
│   └── ...              # Stage execution, checkpoint/resume, DTO routing
└── modules/             # One package per pipeline stage
    └── stage_name/      # Example module
        └── ...          # Pure function: accepts DTO → returns DTO
```

## Module Rules

1. **Pure functions** — accept DTOs, return DTOs, no side effects
2. **No database access** — no imports from `database/`, no SQL, no adapter calls
3. **No cross-module imports** — only import from `contracts/`
4. **No state management** — all state lives in the database
5. **No unstructured console output** — use structured logging
6. **Deterministic** — same input = same output, no randomness
7. **Type annotations** — all public interfaces must have type annotations
