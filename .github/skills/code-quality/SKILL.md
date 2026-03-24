---
name: code-quality
type: skill
description: "Code quality enforcement. Use when reviewing code for style, type hints, logging standards, and Python best practices. Ensures production-ready code with proper typing, structured logging, and no anti-patterns."
---

# Code Quality Skill

## Purpose

Enforce production-ready code standards: type hints on all public interfaces, structured logging via stdlib `logging`, no print statements, and adherence to Python 3.10+ best practices.

## Rules

### Type Hints

- All public function signatures must have PEP 484 type hints
- Use `str | None` syntax (Python 3.10+), not `Optional[str]`
- Use `list[str]` not `List[str]` (lowercase generics)
- DTOs define all field types explicitly

### Logging

- Use stdlib `logging` — never `print()`
- Structured fields via `extra={}` dict
- Log levels: DEBUG for trace, INFO for progress, WARNING for recoverable issues, ERROR for failures
- Include contextual fields: `entity_id`, `stage`, `module`

### Python Standards

- Python 3.10+ minimum
- No `import *` — explicit imports only
- No mutable default arguments (`def f(items=[])`)
- No bare `except:` — always catch specific exceptions
- Use `pathlib.Path` or `os.path` — never string concatenation for paths

### Forbidden Patterns

```python
# ❌ print statements
print("Processing...")

# ❌ Bare except
try: ...
except: ...

# ❌ Mutable default
def process(items=[]):  ...

# ❌ import *
from os import *
```

## Inputs

- Python source code under `app/`, `contracts/`, `database/`

## Outputs

- Code that passes linting (ruff/flake8)
- Properly typed public interfaces
- Structured logging throughout

## Examples

### Correct Logging

```python
import logging

logger = logging.getLogger(__name__)

def process(input_dto: InputDTO, config: dict) -> OutputDTO:
    logger.info(
        "Processing entity",
        extra={"entity_id": input_dto.entity_id, "stage": "processing"}
    )
    ...
```

### Correct Type Hints

```python
def compute_score(
    items: list[ItemDTO],
    weights: dict[str, float],
    threshold: float | None = None,
) -> float:
    ...
```

## Checklist

- [ ] All public functions have type hints
- [ ] No `print()` statements (use `logging`)
- [ ] No bare `except:` clauses
- [ ] No mutable default arguments
- [ ] No `import *`
- [ ] Structured logging with `extra={}` fields
- [ ] Python 3.10+ syntax used (union types, lowercase generics)
