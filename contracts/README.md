# DTO Contract Templates

> This directory holds immutable DTO definitions used to communicate between modules.
> All DTOs must be defined here — never in module code.

## Rules

- **Immutable only** — all DTOs must be immutable (language-specific: frozen dataclass, readonly interface, record, etc.)
- **Additive only** — new DTOs allowed, existing fields never modified
- **No mutable defaults** — use immutable collections, no mutable defaults
- **Type annotations required** — every field must have a type annotation

## Example (Python)

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

## Usage (Python)

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
