#!/usr/bin/env python3
"""scripts/plan/plan_parser.py — PLAN.md indexed parser for skeleton-parallel.

Builds a line-offset indexed plan-index.json from docs/PLAN.md.
Uses mmap + byte-offset index for O(1) section seeks.
Never loads the full file into memory during indexing.

Schema reference: docs/PLAN.md §8.10

Usage:
    python3 scripts/plan/plan_parser.py docs/PLAN.md
    python3 scripts/plan/plan_parser.py docs/PLAN.md --export .skeleton-dev/plan-index.json
    python3 scripts/plan/plan_parser.py docs/PLAN.md --mark-completed 5
    python3 scripts/plan/plan_parser.py docs/PLAN.md --large-file-test
"""
from __future__ import annotations

import argparse
import json
import mmap
import os
import platform
import re
import resource
import sys
import tempfile
from datetime import datetime, timezone
from typing import Any

# ── Regex constants ───────────────────────────────────────────────────────────

# ### Task N — Name  (em dash U+2014 or ASCII dash)
_TASK_HEADER_RE = re.compile(
    r"^### Task (\d+)\s*[\u2014\-]+\s*(.+)$", re.UNICODE
)

# <!-- ✅ Task N completed -->
_COMPLETED_RE = re.compile(
    r"<!--\s*✅\s*Task\s+(\d+)\s+completed\s*-->", re.UNICODE
)

# Section boundary that ends a task block
_TOP_SECTION_RE = re.compile(r"^## ")

# Files section header variants
_FILES_HEADER_RE = re.compile(
    r"^\*\*Files to (?:create|modify|create / modify|modify / create)(?:[^*]*):\*\*"
)

# ── Line offset index ─────────────────────────────────────────────────────────


def build_line_offsets(filepath: str) -> list[int]:
    """
    Build byte offsets for every line start using mmap.
    offsets[i] = byte offset where line (i+1) begins (1-indexed lines).

    Memory: mmap lets the OS page memory; Python only holds the offset list.
    """
    offsets: list[int] = [0]
    with open(filepath, "rb") as f:
        try:
            mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        except ValueError:
            return offsets  # empty file
        pos = 0
        size = mm.size()
        while pos < size:
            nl = mm.find(b"\n", pos)
            if nl == -1:
                break
            offsets.append(nl + 1)
            pos = nl + 1
        mm.close()
    return offsets


def read_section_lines(
    filepath: str,
    offsets: list[int],
    line_start: int,
    line_end: int,
) -> list[str]:
    """
    Read lines [line_start, line_end] (1-indexed, inclusive) by byte seek.
    Only reads the needed bytes — not the whole file.
    """
    n = len(offsets)
    if line_start < 1 or line_start > n:
        return []

    byte_start = offsets[line_start - 1]
    # byte_end = start of line (line_end + 1), or EOF
    if line_end >= n:
        byte_end = os.path.getsize(filepath)
    else:
        byte_end = offsets[line_end]

    if byte_end <= byte_start:
        return []

    with open(filepath, "rb") as f:
        f.seek(byte_start)
        data = f.read(byte_end - byte_start)

    return data.decode("utf-8", errors="replace").splitlines()


# ── Task header discovery (single mmap pass) ──────────────────────────────────


def scan_task_headers(
    filepath: str, offsets: list[int]
) -> dict[int, dict[str, Any]]:
    """
    Single-pass mmap scan to locate all ### Task N headers.

    Returns:
        {task_n: {line_start, line_end, name}}
    where line_start = header line (1-indexed), line_end = last line of section.
    """
    tasks: dict[int, dict[str, Any]] = {}
    task_order: list[int] = []

    with open(filepath, "rb") as f:
        try:
            mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        except ValueError:
            return {}

        pos = 0
        size = mm.size()
        line_num = 1

        while pos < size:
            nl = mm.find(b"\n", pos)
            line_end_pos = nl if nl != -1 else size

            # Read up to 512 bytes to detect the header
            chunk = mm[pos : min(pos + 512, line_end_pos + 1)]
            line_text = chunk.decode("utf-8", errors="replace").rstrip("\n")

            m = _TASK_HEADER_RE.match(line_text)
            if m:
                task_n = int(m.group(1))
                name = m.group(2).strip().strip("`").strip()
                tasks[task_n] = {
                    "line_start": line_num,
                    "line_end": None,
                    "name": name,
                }
                task_order.append(task_n)

            if nl == -1:
                break
            pos = nl + 1
            line_num += 1

        mm.close()

    total_lines = len(offsets)

    # Assign line_end: ends just before the next task header
    for i, task_n in enumerate(task_order):
        if i + 1 < len(task_order):
            tasks[task_n]["line_end"] = (
                tasks[task_order[i + 1]]["line_start"] - 1
            )
        else:
            tasks[task_n]["line_end"] = total_lines

    return tasks


# ── Per-task content parsing ──────────────────────────────────────────────────


def parse_task_content(
    filepath: str,
    offsets: list[int],
    task_n: int,
    info: dict[str, Any],
) -> dict[str, Any]:
    """
    Parse a task's byte range for goal, files, validation, status.
    Reads only the section bytes.
    """
    lines = read_section_lines(
        filepath, offsets, info["line_start"], info["line_end"]
    )

    result: dict[str, Any] = {
        "name": info["name"],
        "goal": "",
        "files": [],
        "validation": [],
        "validation_line": None,
        "status": "pending",
    }

    in_files = False
    in_validation = False
    goal_parts: list[str] = []
    collecting_goal = False

    for rel_idx, line in enumerate(lines):
        abs_line = info["line_start"] + rel_idx
        stripped = line.strip()

        # ── Completion marker ───────────────────────────────────────────────
        m = _COMPLETED_RE.search(line)
        if m and int(m.group(1)) == task_n:
            result["status"] = "completed"
            continue

        # ── Section transitions ─────────────────────────────────────────────
        if stripped.startswith("**Goal:**"):
            in_files = False
            in_validation = False
            collecting_goal = True
            inline = stripped[len("**Goal:**") :].strip()
            if inline:
                goal_parts = [inline]
                collecting_goal = False
            continue

        if _FILES_HEADER_RE.match(stripped):
            in_files = True
            in_validation = False
            collecting_goal = False
            continue

        if stripped == "**Validation:**":
            in_files = False
            in_validation = True
            collecting_goal = False
            result["validation_line"] = abs_line
            continue

        # Also handle "**Final Validation Checklist ...:**" (Task 17)
        if stripped.startswith("**") and "validation" in stripped.lower() and stripped.endswith(":**"):
            in_files = False
            in_validation = True
            collecting_goal = False
            if result["validation_line"] is None:
                result["validation_line"] = abs_line
            continue

        if stripped.startswith("**Prompt context needed:**"):
            in_files = False
            in_validation = False
            collecting_goal = False
            continue

        # Generic bold header ends sub-sections
        if (
            stripped.startswith("**")
            and stripped.endswith(":**")
            and stripped
            not in ("**Goal:**", "**Validation:**")
            and not _FILES_HEADER_RE.match(stripped)
        ):
            in_files = False
            in_validation = False
            collecting_goal = False

        # ── Goal collection ─────────────────────────────────────────────────
        if collecting_goal and stripped and not stripped.startswith("**"):
            goal_parts.append(stripped)
            collecting_goal = False  # only the first non-empty paragraph

        # ── File list ───────────────────────────────────────────────────────
        if in_files and stripped.startswith("-"):
            # Extract backtick-quoted path at start of list item
            m = re.match(r"^-\s+`([^`]+)`", stripped)
            if m:
                result["files"].append(m.group(1))

        # ── Validation list (bullet or checkbox) ───────────────────────────────
        if in_validation and stripped.startswith("-"):
            # Match: "- text" or "- [ ] text" or "- [x] text"
            m = re.match(r"^-\s+(?:\[[ xX]\]\s+)?(.+)$", stripped)
            if m:
                result["validation"].append(m.group(1).strip())

    result["goal"] = " ".join(goal_parts)
    return result


# ── Dependency table parsing (§6 table) ──────────────────────────────────────


def parse_task_summary_table(
    filepath: str, offsets: list[int]
) -> dict[int, dict[str, Any]]:
    """
    Parse the ## 6. Task Summary table for depends_on and complexity.
    Uses mmap for memory efficiency.

    Returns: {task_n: {'depends_on': [...], 'complexity': str}}
    """
    result: dict[int, dict[str, Any]] = {}

    _TABLE_SECTION = re.compile(r"^## 6\.")
    _TABLE_ROW = re.compile(r"^\|\s*(\d+)\s*\|")

    in_section = False

    with open(filepath, "rb") as f:
        try:
            mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        except ValueError:
            return result

        pos = 0
        size = mm.size()

        while pos < size:
            nl = mm.find(b"\n", pos)
            line_end = nl if nl != -1 else size

            chunk = mm[pos : min(pos + 512, line_end + 1)]
            line = chunk.decode("utf-8", errors="replace").rstrip("\n")

            if _TABLE_SECTION.match(line):
                in_section = True
            elif in_section and _TOP_SECTION_RE.match(line) and not line.startswith("## 6."):
                break

            if in_section:
                m = _TABLE_ROW.match(line)
                if m:
                    task_n = int(m.group(1))
                    cols = [c.strip() for c in line.split("|")]
                    # cols: ['', task, name, key_files, depends_on, complexity, '']
                    if len(cols) >= 6:
                        dep_raw = cols[4].strip() if len(cols) > 4 else ""
                        cplx = cols[5].strip() if len(cols) > 5 else ""
                        result[task_n] = {
                            "depends_on_raw": dep_raw,
                            "complexity": cplx,
                        }

            if nl == -1:
                break
            pos = nl + 1

        mm.close()

    return result


def parse_depends_on(
    value: str, all_task_ids: list[int] | None = None, current_n: int | None = None
) -> list[int]:
    """Resolve 'Depends On' column value into a sorted list of task numbers."""
    value = value.strip()
    if not value or value in ("—", "-", "N/A", ""):
        return []
    if value.lower() == "all":
        if all_task_ids and current_n:
            return sorted(n for n in all_task_ids if n < current_n)
        return sorted(all_task_ids) if all_task_ids else []
    return sorted(int(n) for n in re.findall(r"\d+", value))


# ── Public API ────────────────────────────────────────────────────────────────


def index_tasks(plan_path: str) -> dict[int, dict[str, Any]]:
    """
    Build the full task index from a PLAN.md file.

    Returns: {task_n: task_record}
    Each task_record follows the §8.10 schema fields.
    """
    offsets = build_line_offsets(plan_path)
    raw_sections = scan_task_headers(plan_path, offsets)
    table_data = parse_task_summary_table(plan_path, offsets)

    all_ids = sorted(raw_sections.keys())

    tasks: dict[int, dict[str, Any]] = {}
    for task_n in all_ids:
        info = raw_sections[task_n]
        content = parse_task_content(plan_path, offsets, task_n, info)
        td = table_data.get(task_n, {})

        depends_on = parse_depends_on(
            td.get("depends_on_raw", ""),
            all_task_ids=all_ids,
            current_n=task_n,
        )

        tasks[task_n] = {
            "line_start": info["line_start"],
            "line_end": info["line_end"],
            "name": content["name"],
            "goal": content["goal"],
            "files": content["files"],
            "depends_on": depends_on,
            "complexity": td.get("complexity", ""),
            "status": content["status"],
            "validation": content["validation"],
            "validation_line": content["validation_line"],
        }

    return tasks


def parse_dep_graph(tasks: dict[int, dict[str, Any]]) -> dict[int, list[int]]:
    """Return {task_n: [dep_n, ...]} dependency graph."""
    return {n: t["depends_on"] for n, t in tasks.items()}


def extract_file_ownership(task: dict[str, Any]) -> list[str]:
    """Return the list of files declared in the task's 'Files to create' section."""
    return task.get("files", [])


def check_parallel_safety(
    task_a: dict[str, Any], task_b: dict[str, Any]
) -> bool:
    """
    Return True if both tasks can run in parallel (no file ownership overlap).
    Return False if they declare any of the same files.
    """
    files_a = set(extract_file_ownership(task_a))
    files_b = set(extract_file_ownership(task_b))
    return len(files_a & files_b) == 0


def is_completed(task: dict[str, Any]) -> bool:
    """Return True if the task carries a completion marker."""
    return task.get("status") == "completed"


def mark_completed(plan_path: str, task_n: int) -> None:
    """
    Insert <!-- ✅ Task N completed --> after the task header in PLAN.md.
    Idempotent: no-op if the marker is already present.
    This is the ONLY write operation allowed on PLAN.md by the pipeline.
    """
    tasks = index_tasks(plan_path)
    task = tasks.get(task_n)
    if task is None:
        raise ValueError(f"Task {task_n} not found in {plan_path}")

    if is_completed(task):
        return  # already marked

    # Read the full file (required for targeted line insertion)
    with open(plan_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    header_line_idx = task["line_start"] - 1  # 0-indexed

    # Find the insertion point: after the header line + any immediately
    # following blank lines
    insert_at = header_line_idx + 1
    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1

    marker = f"<!-- ✅ Task {task_n} completed -->\n"
    lines.insert(insert_at, "\n")
    lines.insert(insert_at, marker)

    with open(plan_path, "w", encoding="utf-8") as f:
        f.writelines(lines)


# ── Export ────────────────────────────────────────────────────────────────────


def export_index(plan_path: str, output_path: str) -> dict[str, Any]:
    """
    Build and write plan-index.json per the §8.10 schema.
    Creates the output directory if needed.
    """
    tasks = index_tasks(plan_path)
    dep_graph = parse_dep_graph(tasks)

    # Build file_ownership: {file_path: [task_n, ...]}
    file_ownership: dict[str, list[int]] = {}
    for task_n, task in tasks.items():
        for fp in task["files"]:
            file_ownership.setdefault(fp, []).append(task_n)

    index: dict[str, Any] = {
        "plan_path": os.path.relpath(plan_path) if os.path.isabs(plan_path) else plan_path,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "tasks": {str(n): t for n, t in sorted(tasks.items())},
        "dep_graph": {str(n): deps for n, deps in sorted(dep_graph.items())},
        "file_ownership": file_ownership,
    }

    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(index, f, indent=2, ensure_ascii=False)
        f.write("\n")

    return index


# ── Large-file test ───────────────────────────────────────────────────────────


def large_file_test() -> None:
    """
    Create a 100k-line synthetic PLAN.md, run the parser, and verify that
    memory usage (measured via resource.getrusage) stays below 100 MB.
    """
    target_lines = 100_000
    num_tasks = 5
    filler_per_task = (target_lines - 50) // num_tasks

    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".md", delete=False, encoding="utf-8"
    )
    try:
        with tmp:
            tmp.write("# PLAN.md — Large-file Test\n\n")
            tmp.write("## 5. Implementation Tasks\n\n")
            for t in range(1, num_tasks + 1):
                dep_col = "—" if t == 1 else f"Task {t - 1}"
                tmp.write(f"### Task {t} — Synthetic Task {t}\n\n")
                tmp.write(f"**Goal:** Synthetic goal for task {t}.\n\n")
                tmp.write("**Files to create:**\n\n")
                tmp.write(f"- `scripts/synthetic/task{t}.sh` — script\n\n")
                tmp.write("**Validation:**\n\n")
                tmp.write(f"- `bash -n scripts/synthetic/task{t}.sh`: OK\n\n")
                tmp.write("**Prompt context needed:** None\n\n---\n\n")
                for i in range(filler_per_task):
                    tmp.write(f"<!-- filler {t}-{i} -->\n")

            tmp.write("## 6. Task Summary\n\n")
            tmp.write(
                "| Task | Name | Key Files | Depends On | Est. Complexity |\n"
            )
            tmp.write(
                "| ---- | ---- | --------- | ---------- | --------------- |\n"
            )
            for t in range(1, num_tasks + 1):
                dep = "—" if t == 1 else f"Task {t - 1}"
                tmp.write(
                    f"| {t}    | Synthetic Task {t} "
                    f"| `scripts/synthetic/task{t}.sh` | {dep} | Low |\n"
                )

        # ── Measure ──────────────────────────────────────────────────────────
        before_rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss

        tasks = index_tasks(tmp.name)

        after_rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss

        file_size = os.path.getsize(tmp.name)
        line_count = sum(1 for _ in open(tmp.name, encoding="utf-8"))

        # macOS: ru_maxrss in bytes; Linux: in kilobytes
        divisor = 1024 * 1024 if platform.system() == "Darwin" else 1024
        rss_mb = after_rss / divisor

        print("Large-file test:")
        print(f"  File: {file_size:,} bytes, {line_count:,} lines")
        print(f"  Tasks indexed: {len(tasks)}")
        print(f"  RSS after parse: {rss_mb:.1f} MB")
        ok = rss_mb < 100
        print(f"  Memory < 100 MB: {'OK' if ok else 'FAIL'}")

        if len(tasks) != num_tasks:
            print(f"FAIL: expected {num_tasks} tasks, got {len(tasks)}", file=sys.stderr)
            sys.exit(1)
        if not ok:
            print(f"FAIL: RSS {rss_mb:.1f} MB exceeds 100 MB", file=sys.stderr)
            sys.exit(1)

        print("PASS")

    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


# ── CLI ───────────────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Parse PLAN.md and produce plan-index.json"
    )
    parser.add_argument("plan_path", nargs="?", help="Path to PLAN.md")
    parser.add_argument(
        "--export", metavar="OUTPUT", help="Write plan-index.json to this path"
    )
    parser.add_argument(
        "--mark-completed",
        metavar="N",
        type=int,
        help="Mark Task N as completed in PLAN.md",
    )
    parser.add_argument(
        "--large-file-test",
        action="store_true",
        help="Run memory-bounded large-file test (100k lines)",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Print a summary of indexed tasks",
    )
    args = parser.parse_args()

    if args.large_file_test:
        large_file_test()
        return

    if not args.plan_path:
        parser.print_help()
        sys.exit(1)

    if args.mark_completed is not None:
        mark_completed(args.plan_path, args.mark_completed)
        print(f"[OK] Task {args.mark_completed} marked completed in {args.plan_path}")
        return

    if args.export:
        index = export_index(args.plan_path, args.export)
        n = len(index["tasks"])
        print(f"[OK] Exported {n} task(s) to {args.export}")
        if args.summary:
            for task_id, task in sorted(index["tasks"].items(), key=lambda x: int(x[0])):
                status = "✅" if task["status"] == "completed" else "⏳"
                deps = task["depends_on"]
                print(
                    f"  {status} Task {task_id}: {task['name']} "
                    f"(deps: {deps or '—'}, complexity: {task['complexity']})"
                )
    else:
        tasks = index_tasks(args.plan_path)
        n = len(tasks)
        print(f"[OK] Indexed {n} task(s) from {args.plan_path}")
        if args.summary:
            for task_n, task in sorted(tasks.items()):
                status = "✅" if is_completed(task) else "⏳"
                print(
                    f"  {status} Task {task_n}: {task['name']} "
                    f"(deps: {task['depends_on'] or '—'})"
                )


if __name__ == "__main__":
    main()
