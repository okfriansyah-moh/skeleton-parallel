# {{PROJECT_NAME}}

> Built with [skeleton-parallel](https://github.com/skeleton-parallel/skeleton-parallel) framework.

## Quick Start

```bash
# Generate architecture
@workspace Use .github/prompts/architecture.prompt.md to generate docs/architecture.md

# Generate roadmap
@workspace Use .github/prompts/roadmap.prompt.md to generate docs/implementation_roadmap.md

# Generate supporting specs
@workspace Use .github/prompts/dto.prompt.md to generate docs/dto_contracts.md
@workspace Use .github/prompts/orchestrator.prompt.md to generate docs/orchestrator_spec.md
@workspace Use .github/prompts/db_adapter.prompt.md to generate docs/db_adapter_spec.md

# Implement Phase 0
@phase-builder implement Phase 0

# Run parallel development
./scripts/run_parallel.sh start --mode=3 1 2 3
```

## Project Structure

See `docs/architecture.md` for the full system design.

## Development

- **Skills:** `.github/skills/` — Pre-digested knowledge modules
- **Agents:** `.github/agents/` — Autonomous execution roles
- **Parallel Dev:** `./scripts/run_parallel.sh` — 3-mode parallel orchestrator

## License

MIT
