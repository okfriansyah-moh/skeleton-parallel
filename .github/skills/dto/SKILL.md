---
name: dto
type: skill
description: "DTO interpretation and validation. Use when creating, modifying, reviewing, or consuming frozen dataclass DTOs from contracts/. Provides the DTO registry pattern, field types, constraints, producer/consumer mapping, and anti-patterns."
---

# DTO Interpretation Skill

## Purpose

Enforce frozen dataclass DTO contracts across the entire codebase. Ensures all cross-module data exchange uses typed, immutable DTOs defined in `contracts/`.

## Rules

### All DTOs

- Must be `@dataclass(frozen=True)`
- No methods, no properties, no `__post_init__` logic
- All fields typed (PEP 484)
- JSON-serializable only: `str`, `int`, `float`, `bool`, `None`, `list`, `tuple`, nested DTOs
- Forbidden types: `datetime`, `Path`, `bytes`, `set`, `complex`, class instances

### Versioning

- **Additive only**: new fields may be added (with defaults)
- **Never remove or rename** existing fields
- DTO changes merge to `main` BEFORE module changes that depend on them

### ID Formats

- Content-addressable: `entity_id = SHA256(content_signature)[:16]`
- 16 hexadecimal characters
- Deterministic: same content = same ID, always

## Inputs

- `contracts/` directory — frozen dataclass definitions
- `docs/dto_contracts.md` — DTO registry with fields, types, constraints

## Outputs

- Validated DTOs in `contracts/` with correct structure
- Compatibility report listing any DTO mismatches

## DTO Registry Pattern

Each project defines its DTOs in `docs/dto_contracts.md`. The registry follows this structure:

| DTO             | File                     | Producer | Consumers          | Key Constraints           |
| --------------- | ------------------------ | -------- | ------------------ | ------------------------- |
| `EntityResult`  | `contracts/entity.py`    | module_a | module_b, module_c | `entity_id`: 16 hex chars |
| `ProcessedData` | `contracts/processed.py` | module_b | module_d           | all scores in [0.0–1.0]   |

Populate this table from your project's `docs/dto_contracts.md`.

## Anti-Patterns

```python
# ❌ Raw dict instead of DTO
result = {"entity_id": "abc123", "status": "done"}

# ❌ Mutable dataclass
@dataclass  # Missing frozen=True
class MyDTO: ...

# ❌ Logic in DTO
@dataclass(frozen=True)
class MyDTO:
    def validate(self): ...  # No methods allowed

# ❌ Cross-module type
from app.modules.processing.internal import ProcessResult  # Forbidden

# ✅ Correct usage
from contracts.processing import ProcessedData
result: ProcessedData = processing.process(input_dto, config)
```

## Examples

### Creating a new DTO

```python
# contracts/entity.py
from dataclasses import dataclass

@dataclass(frozen=True)
class EntityResult:
    entity_id: str       # SHA256(content)[:16]
    name: str
    status: str          # created | queued | processed | completed | failed
    score: float         # 0.0–1.0
```

### Consuming a DTO in a module

```python
# app/modules/processing/__init__.py
from contracts.entity import EntityResult
from contracts.processed import ProcessedData

def process(input_dto: EntityResult, config: dict) -> ProcessedData:
    ...
```

## Checklist

- [ ] All DTOs use `@dataclass(frozen=True)`
- [ ] All fields have type hints
- [ ] No methods or properties in DTOs
- [ ] No forbidden types (`datetime`, `Path`, `bytes`, `set`)
- [ ] All IDs are content-addressable (SHA-256 based)
- [ ] No raw dicts crossing module boundaries
- [ ] All imports from `contracts.*` package
