# Application Code

> Single-process modular monolith. Each pipeline stage is a module under `app/modules/`.

## Structure

```
app/
├── main.py              # Entry point — parses args, calls orchestrator
├── orchestrator/        # Pipeline orchestration + checkpointing
│   ├── __init__.py
│   └── pipeline.py      # Stage execution, checkpoint/resume, DTO routing
└── modules/             # One package per pipeline stage
    ├── __init__.py
    └── stage_name/      # Example module
        ├── __init__.py
        └── processor.py # Pure function: accepts DTO → returns DTO
```

## Module Rules

1. **Pure functions** — accept DTOs, return DTOs, no side effects
2. **No database access** — no imports from `database/`, no SQL, no adapter calls
3. **No cross-module imports** — only import from `contracts/`
4. **No state management** — all state lives in the database
5. **No print()** — use `logging` module
6. **Deterministic** — same input = same output, no randomness
7. **Type hints** — all public interfaces must have type annotations
