# DTO Contract Templates

> This directory holds frozen dataclass definitions used to communicate between modules.
> All DTOs must be defined here — never in module code.

## Rules

- **Frozen only** — all dataclasses use `@dataclass(frozen=True)`
- **Additive only** — new DTOs allowed, existing fields never modified
- **No mutable defaults** — use `tuple` instead of `list`, no `dict` defaults
- **Type hints required** — every field must have a type annotation

## Example

```python
from dataclasses import dataclass
from typing import Optional

@dataclass(frozen=True)
class ExampleDTO:
    entity_id: str          # Content-addressable: SHA256(content)[:16]
    name: str
    score: float
    status: str             # "created" | "queued" | "processed" | "completed" | "failed"
    metadata: Optional[str] = None
```

## Usage

```python
# In contracts/example.py — define the DTO
from dataclasses import dataclass

@dataclass(frozen=True)
class ExampleOutput:
    entity_id: str
    result: str

# In app/modules/example_module/processor.py — import only from contracts
from contracts.example import ExampleOutput

def process(input_dto) -> ExampleOutput:
    return ExampleOutput(entity_id="abc123", result="done")
```
