#!/usr/bin/env python3
"""scripts/knowledge/detect_legacy.py — Scan for legacy provider knowledge files.

Checks the project root for provider-specific knowledge directories and files
that predate the ARES .ai/ convention. Used by Stage -1 to decide whether
an import is needed.

Detected sources:
  github     — .github/copilot-instructions.md, .github/agents/, .github/skills/
  claude     — CLAUDE.md, .claude/
  codex      — AGENTS.md
  cursor     — .cursor/rules/
  antigravity — .antigravity/

Output: JSON list of {source, type, files}, or [] if nothing detected.

Usage:
    python3 scripts/knowledge/detect_legacy.py [project_root]
    python3 scripts/knowledge/detect_legacy.py . --json   (default: JSON output)
"""
from __future__ import annotations

import json
import os
import sys
from typing import Any


def detect_legacy(project_root: str) -> list[dict[str, Any]]:
    """
    Scan project_root for legacy provider knowledge files.

    Returns a list of detection records:
        [{"source": str, "type": str, "files": [str, ...]}, ...]

    Empty list means no legacy sources found.
    """
    project_root = os.path.abspath(project_root)
    results: list[dict[str, Any]] = []

    # ── GitHub Copilot ────────────────────────────────────────────────────────
    github_paths = [
        ".github/copilot-instructions.md",
        ".github/agents",
        ".github/skills",
        ".github/prompts",
    ]
    github_found = [
        p for p in github_paths if os.path.exists(os.path.join(project_root, p))
    ]
    if github_found:
        results.append({
            "source": "github",
            "type":   "copilot",
            "files":  github_found,
        })

    # ── Claude Code ───────────────────────────────────────────────────────────
    claude_paths = ["CLAUDE.md", ".claude"]
    claude_found = [
        p for p in claude_paths if os.path.exists(os.path.join(project_root, p))
    ]
    if claude_found:
        results.append({
            "source": "claude",
            "type":   "claude",
            "files":  claude_found,
        })

    # ── Codex (OpenAI) ────────────────────────────────────────────────────────
    if os.path.exists(os.path.join(project_root, "AGENTS.md")):
        results.append({
            "source": "codex",
            "type":   "codex",
            "files":  ["AGENTS.md"],
        })

    # ── Cursor ────────────────────────────────────────────────────────────────
    if os.path.exists(os.path.join(project_root, ".cursor", "rules")):
        results.append({
            "source": "cursor",
            "type":   "cursor",
            "files":  [".cursor/rules"],
        })

    # ── Antigravity ───────────────────────────────────────────────────────────
    if os.path.exists(os.path.join(project_root, ".antigravity")):
        results.append({
            "source": "antigravity",
            "type":   "antigravity",
            "files":  [".antigravity"],
        })

    return results


def main() -> None:
    # Strip flag arguments; first positional arg is the project root
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    project_root = args[0] if args else "."

    results = detect_legacy(project_root)
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
