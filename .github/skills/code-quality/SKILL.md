---
name: code-quality
description: "Code quality enforcement. Use when reviewing code for style, type annotations, logging standards, and best practices. Ensures production-ready code with proper typing, structured logging, and no anti-patterns."
---

# Code Quality Skill

## Purpose

Enforce production-ready code standards: type annotations on all public interfaces, structured logging (language-appropriate), no unstructured console output, and adherence to the project's language best practices.

## Rules

### Type Annotations

- All public function/method signatures must have type annotations
- Use the language's modern type syntax (e.g., Python 3.10+ union `str | None`, TypeScript strict mode, Go explicit types)
- DTOs define all field types explicitly

### Logging

- Use structured logging (language-appropriate library) — never raw console output
- Structured fields via contextual metadata
- Log levels: DEBUG for trace, INFO for progress, WARNING for recoverable issues, ERROR for failures
- Include contextual fields: `entity_id`, `stage`, `module`

### Language Standards

- Use the project's minimum runtime version
- No wildcard imports — explicit imports only
- No mutable default arguments
- No bare exception catches — always catch specific exceptions
- Use proper path handling — never string concatenation for paths

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

- Source code under `app/`, `contracts/`, `database/`

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

- [ ] All public functions have type annotations
- [ ] No unstructured console output (use structured logging)
- [ ] No bare exception catches
- [ ] No mutable default arguments
- [ ] No wildcard imports
- [ ] Structured logging with contextual fields
- [ ] Modern language syntax used per project's minimum version
