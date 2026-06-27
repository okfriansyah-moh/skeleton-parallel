#!/usr/bin/env python3
"""scripts/plan/plan_validate.py — Validate plan-index.json consistency.

Checks performed:
  1. All depends_on task IDs exist in the index
  2. No circular dependencies in the dep graph
  3. All tasks have at least one validation step

Usage:
    python3 scripts/plan/plan_validate.py .skeleton-dev/plan-index.json
    python3 scripts/plan/plan_validate.py .skeleton-dev/plan-index.json --verbose
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any


def validate_plan(index_path: str) -> list[str]:
    """
    Validate plan-index.json for structural and dependency consistency.

    Returns:
        A list of error strings. Empty list means the plan is valid.
    """
    errors: list[str] = []

    with open(index_path, encoding="utf-8") as f:
        index: dict[str, Any] = json.load(f)

    tasks: dict[str, Any] = index.get("tasks", {})
    dep_graph: dict[str, list] = index.get("dep_graph", {})
    task_ids: set[str] = set(tasks.keys())

    # ── Check 1: All depends_on IDs exist in the task index ──────────────────
    for task_id, task in tasks.items():
        for dep_id in task.get("depends_on", []):
            if str(dep_id) not in task_ids:
                errors.append(
                    f"Task {task_id} ({task.get('name', '?')!r}) "
                    f"depends on Task {dep_id} which is not in the index"
                )

    # ── Check 2: No circular dependencies (iterative DFS) ────────────────────
    WHITE, GRAY, BLACK = 0, 1, 2
    color: dict[str, int] = {k: WHITE for k in dep_graph}

    def dfs(start: str) -> list[str] | None:
        """Return cycle path if a cycle is reachable from start, else None."""
        stack: list[tuple[str, list[str]]] = [(start, [start])]
        # Iterative DFS to avoid Python recursion limit on deep graphs
        visited: dict[str, int] = {}

        while stack:
            node, path = stack[-1]
            if node not in visited:
                visited[node] = GRAY
                color[node] = GRAY
                pushed_child = False
                for dep in dep_graph.get(node, []):
                    dep_str = str(dep)
                    if dep_str not in color:
                        continue
                    if color.get(dep_str) == GRAY:
                        # Cycle found
                        try:
                            cycle_start = path.index(dep_str)
                            return path[cycle_start:] + [dep_str]
                        except ValueError:
                            return path + [dep_str]
                    if color.get(dep_str, BLACK) == WHITE:
                        stack.append((dep_str, path + [dep_str]))
                        pushed_child = True
                        break
                if not pushed_child:
                    color[node] = BLACK
                    stack.pop()
            else:
                color[node] = BLACK
                stack.pop()
        return None

    for node in list(dep_graph.keys()):
        if color.get(node, BLACK) == WHITE:
            cycle = dfs(node)
            if cycle:
                errors.append(
                    f"Circular dependency: Task {' → Task '.join(cycle)}"
                )

    # ── Check 3: All tasks have non-empty validation ──────────────────────────
    for task_id, task in tasks.items():
        validation = task.get("validation", [])
        if not validation:
            errors.append(
                f"Task {task_id} ({task.get('name', '?')!r}) "
                f"has no validation steps"
            )

    return errors


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate plan-index.json for consistency"
    )
    parser.add_argument("index_path", help="Path to plan-index.json")
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Print all checks, not just failures"
    )
    args = parser.parse_args()

    errors = validate_plan(args.index_path)

    if errors:
        print(
            f"[FAIL] plan-index.json validation failed ({len(errors)} error(s)):",
            file=sys.stderr,
        )
        for err in errors:
            print(f"  ✗ {err}", file=sys.stderr)
        sys.exit(1)

    if args.verbose:
        with open(args.index_path, encoding="utf-8") as f:
            index = json.load(f)
        n = len(index.get("tasks", {}))
        print(f"[OK]  plan-index.json is valid ({n} tasks, no cycles, all validated)")
    else:
        print("[OK]  plan-index.json is valid")

    sys.exit(0)


if __name__ == "__main__":
    main()
