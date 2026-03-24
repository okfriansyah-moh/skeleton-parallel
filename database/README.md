# Database Adapter

> All database access goes through this module. No other module may import
> database drivers or execute SQL directly.

## Structure

```
database/
├── adapter.py              # Single entry point — all DB operations
├── engines/
│   ├── <engine>_engine.py  # Engine-specific implementations
│   └── ...                 # Add engines as needed for your project
├── migrations/             # Append-only migration files
│   └── YYYYMMDD000NNN_description.sql
└── schema_template.sql     # Reference schema (template)
```

## Rules

- Only `app/orchestrator/` may import from `database/`
- `app/modules/` MUST NOT import any database driver directly
- The adapter accepts and returns immutable DTOs
- All SQL uses portable syntax (ON CONFLICT DO NOTHING)
- Parameterized queries only — no string interpolation
- Engine-specific settings belong in `database/engines/` only
