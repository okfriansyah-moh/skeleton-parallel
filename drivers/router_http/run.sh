#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# drivers/router_http/run.sh — HTTP harness driver (Driver A) for skeleton-parallel
# ─────────────────────────────────────────────────────────────────────────────
# Implements the run_driver() ExecutionDriver contract per spec §8.2.
#
# Assembles a system prompt from 4 components per §8.2:
#   1. SKELETON_ROOT/framework/ instructions (*.md files)
#   2. Framework skills CSV (all 28)
#   3. Project .ai/skills/ SKILL.md name+description only (trimmed)
#   4. TASK_PROMPT.md content + stage template variable substitution
#
# Then calls 9router's OpenAI-compatible /v1/chat/completions via curl.
# Implementation stages use tool calling (agentic loop); assessment stages
# use streaming (existing behaviour).
#
# Usage:
#   bash drivers/router_http/run.sh [--print-prompt] \
#       <driver> <stage> <work_dir> <prompt_file> <model> <log_file>
#
# Flags:
#   --print-prompt   Assemble and print system prompt JSON; skip HTTP call
#
# Exit codes (per spec §8.2):
#   0 — success
#   1 — agent error (non-200 response, content error)
#   2 — quota/429 exhausted → caller applies quota_retry policy
#   3 — fatal (missing dependency, bad config, curl not found)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

_DRIVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKELETON_ROOT="$(cd "${_DRIVER_DIR}/../.." && pwd)"

# Source shared utilities
# shellcheck source=scripts/lib/common.sh
source "${_SKELETON_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/agent.sh
source "${_SKELETON_ROOT}/scripts/lib/agent.sh"
# shellcheck source=scripts/lib/config.sh
source "${_SKELETON_ROOT}/scripts/lib/config.sh"

# ── Router defaults (overridable via env / config) ────────────────────────────
_ROUTER_DEFAULT_ENDPOINT="http://localhost:20128/v1/chat/completions"
_ROUTER_TIMEOUT="${NINE_ROUTER_TIMEOUT:-300}"

# ── _stage_uses_tools ─────────────────────────────────────────────────────────
# Returns 0 (true) if the stage should use tool calling + non-streaming mode.
# Assessment stages keep the existing streaming behaviour (returns 1).
_stage_uses_tools() {
    local stage="$1"
    case "${stage}" in
        post-merge-review|docs-sync|test-sufficiency|acceptance-llm|security-auditor)
            return 1 ;;
        *)
            return 0 ;;
    esac
}

# ── _assemble_system_prompt ───────────────────────────────────────────────────
# Build the 4-component system prompt per §8.2.
# Writes result to stdout.
#
# Component 3 change: only emit name + description frontmatter from each
# SKILL.md, not the full content — keeps the prompt well under token limits.
#
# Usage: system_prompt=$(_assemble_system_prompt <stage> <work_dir> [extra_skills])
_assemble_system_prompt() {
    local stage="$1"
    local work_dir="$2"
    local extra_skills="${3:-}"

    local parts=()

    # ── Component 1: Framework instructions ───────────────────────────────────
    local framework_dir="${_SKELETON_ROOT}/framework"
    if [[ -d "${framework_dir}" ]]; then
        local md_content=""
        while IFS= read -r -d '' md_file; do
            local content
            content="$(cat "${md_file}" 2>/dev/null || true)"
            [[ -n "${content}" ]] && md_content+="${content}"$'\n'
        done < <(find "${framework_dir}" -maxdepth 1 -name "*.md" -print0 2>/dev/null | sort -z)
        [[ -n "${md_content}" ]] && parts+=("## Framework Instructions"$'\n'"${md_content}")
    fi

    # ── Component 2: Framework skills CSV ────────────────────────────────────
    local skills_csv
    skills_csv="$(build_skills_csv "${extra_skills}")"
    parts+=("## Skills"$'\n'"MANDATORY: Use the following skills as primary knowledge sources:"$'\n'"${skills_csv}")

    # ── Component 3: Project .ai/skills/ — name + description only ───────────
    # We intentionally omit full SKILL.md bodies to avoid 191KB+ context bloat.
    # The model only needs the skill name and a one-line description to act on them.
    local ai_skills_dir="${work_dir}/.ai/skills"
    if [[ -d "${ai_skills_dir}" ]]; then
        local skill_summary=""
        while IFS= read -r -d '' skill_file; do
            # Extract name: and description: from YAML frontmatter (first 20 lines)
            local name="" desc=""
            name="$(head -20 "${skill_file}" 2>/dev/null | grep -m1 '^name:' | sed 's/^name:[[:space:]]*//' | tr -d '"'"'" || true)"
            desc="$(head -20 "${skill_file}" 2>/dev/null | grep -m1 '^description:' | sed 's/^description:[[:space:]]*//' | tr -d '"'"'" || true)"
            if [[ -n "${name}" ]]; then
                skill_summary+="- ${name}"
                [[ -n "${desc}" ]] && skill_summary+=": ${desc}"
                skill_summary+=$'\n'
            fi
        done < <(find "${ai_skills_dir}" -name "SKILL.md" -print0 2>/dev/null | sort -z)
        if [[ -n "${skill_summary}" ]]; then
            parts+=("## Project Skills"$'\n'"${skill_summary}")
        fi
    fi

    # ── Component 4: Stage context + workspace constraint ────────────────────
    parts+=(
        "## Stage Context"
        "Stage: ${stage}"
        "${AGENT_WORKSPACE_CONSTRAINT}"
        "Follow constraints in the ARES-composed harness file for the configured provider (see .ai/manifest.yaml)."
    )

    # Print all parts joined with newlines
    local IFS=$'\n'
    printf '%s\n' "${parts[@]}"
}

# ── _apply_file_changes ───────────────────────────────────────────────────────
# Extract fenced code blocks with file paths from the LLM response and write
# them to disk. Supports two annotation formats:
#   ```python path/to/file.py        ← inline path after language
#   # path/to/file.py                ← first comment line inside block
#
# Skips assessment/review stages where file writes are not expected.
# Also skips when tool calling was used (files already written during loop).
#
# Usage: _apply_file_changes <log_file> <work_dir> <stage>
_apply_file_changes() {
    local log_file="$1"
    local work_dir="$2"
    local stage="$3"

    # Stages that only produce text reports — never write files
    case "${stage}" in
        post-merge-review|docs-sync|test-sufficiency|acceptance-llm|security-auditor)
            return 0 ;;
    esac

    [[ -f "${log_file}" ]] || return 0

    python3 - "${log_file}" "${work_dir}" "${stage}" <<'PYEOF' 2>/dev/null || true
import sys, json, re, os, pathlib

log_path  = sys.argv[1]
work_dir  = sys.argv[2]
stage     = sys.argv[3]

# ── Decode SSE stream → plain text ───────────────────────────────────────────
text_parts = []
for line in open(log_path, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if line.startswith("data:"):
        payload = line[5:].strip()
        if payload in ("", "[DONE]"):
            continue
        try:
            chunk = json.loads(payload)
            for choice in chunk.get("choices", []):
                content = (choice.get("delta") or choice.get("message") or {}).get("content") or ""
                text_parts.append(content)
        except Exception:
            pass
    else:
        text_parts.append(line + "\n")

full_text = "".join(text_parts)

# ── Extract fenced code blocks ────────────────────────────────────────────────
# Pattern: ```<lang> [optional/path.py]\n<code>\n```
FENCE_RE = re.compile(
    r"```(?P<lang>[a-zA-Z0-9_+-]*)[ \t]*(?P<inline_path>[^\n`]*?)\n"
    r"(?P<body>.*?)"
    r"```",
    re.DOTALL,
)

written = 0
for m in FENCE_RE.finditer(full_text):
    lang        = m.group("lang").strip()
    inline_path = m.group("inline_path").strip()
    body        = m.group("body")

    # Determine file path
    file_path = inline_path

    # Fallback: first line of block if it looks like a comment with a path
    if not file_path:
        first_line = body.split("\n", 1)[0].strip()
        comment_path = re.match(r'^[#/]{1,2}\s*([\w./\-]+\.\w+)', first_line)
        if comment_path:
            file_path = comment_path.group(1)
            # Remove the comment line from body
            body = body.split("\n", 1)[1] if "\n" in body else body

    if not file_path:
        continue

    # Security: reject absolute paths, path traversal, or paths outside work_dir
    if file_path.startswith("/") or ".." in file_path:
        continue

    # Only write known source extensions (never overwrite config/docs/PLAN.md)
    allowed_exts = {".py", ".toml", ".cfg", ".ini", ".yaml", ".yml",
                    ".sh", ".txt", ".md", ".json", ".env.example"}
    if pathlib.Path(file_path).suffix not in allowed_exts:
        continue
    if file_path in ("docs/PLAN.md", "config/skeleton.yaml", ".ai/manifest.yaml"):
        continue

    dest = pathlib.Path(work_dir) / file_path
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(body, encoding="utf-8")
    written += 1
    print(f"[router_http] wrote: {file_path}")

if written:
    print(f"[router_http] {stage}: applied {written} file(s) from LLM response")
PYEOF
}

# ── _run_agentic_loop ─────────────────────────────────────────────────────────
# Run an OpenAI-compatible agentic tool-calling loop in Python.
# Handles write_file / read_file / list_directory / run_bash tools locally.
# Writes all output (text + tool summaries) to log_file.
#
# Usage: _run_agentic_loop <endpoint> <token> <model> \
#                          <sys_tmp> <usr_tmp> <work_dir> <stage> <log_file>
# Exit codes: 0=ok  1=error  2=rate-limited
_run_agentic_loop() {
    local endpoint="$1"
    local token="$2"
    local model="$3"
    local sys_tmp="$4"
    local usr_tmp="$5"
    local work_dir="$6"
    local stage="$7"
    local log_file="$8"

    python3 - \
        "${endpoint}" "${token}" "${model}" \
        "${sys_tmp}" "${usr_tmp}" \
        "${work_dir}" "${stage}" "${log_file}" \
        "${_ROUTER_TIMEOUT}" <<'PYEOF'
import sys, json, os, pathlib, subprocess, urllib.request, urllib.error

endpoint  = sys.argv[1]
token     = sys.argv[2]
model     = sys.argv[3]
sys_file  = sys.argv[4]
usr_file  = sys.argv[5]
work_dir  = sys.argv[6]
stage     = sys.argv[7]
log_file  = sys.argv[8]
timeout   = int(sys.argv[9])

# ── Read prompt content ───────────────────────────────────────────────────────
with open(sys_file, encoding="utf-8") as f:
    system_content = f.read()
with open(usr_file, encoding="utf-8") as f:
    user_content = f.read()

os.unlink(sys_file)
os.unlink(usr_file)

# ── Tool definitions ──────────────────────────────────────────────────────────
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Write content to a file in the project. Creates parent directories as needed.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path":    {"type": "string", "description": "Relative path from project root"},
                    "content": {"type": "string", "description": "File content to write"},
                },
                "required": ["path", "content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read a file from the project.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Relative path from project root"},
                },
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "list_directory",
            "description": "List files in a directory.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Relative path from project root (default: .)"},
                },
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "run_bash",
            "description": "Run a bash command in the project directory. Use for git commit, running tests, etc.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "Bash command to run"},
                    "timeout": {"type": "integer", "description": "Timeout in seconds (default: 60)"},
                },
                "required": ["command"],
            },
        },
    },
]

# ── Security helpers ──────────────────────────────────────────────────────────
ALLOWED_EXTS = {
    ".py", ".toml", ".cfg", ".ini", ".yaml", ".yml",
    ".sh", ".txt", ".md", ".json", ".env.example",
    ".gitignore", ".dockerignore",
}
PROTECTED_FILES = {"docs/PLAN.md", "config/skeleton.yaml", ".ai/manifest.yaml"}

def _safe_path(rel_path, work_dir, check_write=False):
    """Return resolved absolute path inside work_dir or raise ValueError."""
    if not rel_path or rel_path.startswith("/") or ".." in rel_path:
        raise ValueError(f"Unsafe path: {rel_path!r}")
    resolved = (pathlib.Path(work_dir) / rel_path).resolve()
    work_resolved = pathlib.Path(work_dir).resolve()
    if not str(resolved).startswith(str(work_resolved)):
        raise ValueError(f"Path escapes work_dir: {rel_path!r}")
    if check_write:
        suffix = pathlib.Path(rel_path).suffix
        # Files without extension (Makefile, Dockerfile, etc.) are allowed
        if suffix and suffix not in ALLOWED_EXTS:
            raise ValueError(f"Extension not allowed for write: {suffix!r}")
        if rel_path in PROTECTED_FILES:
            raise ValueError(f"Protected file, write not allowed: {rel_path!r}")
    return resolved

# ── Tool executor ─────────────────────────────────────────────────────────────
def execute_tool(name, args):
    if name == "write_file":
        rel  = args.get("path", "")
        body = args.get("content", "")
        # Special case: allow appending task completion markers to PLAN.md only
        if rel == "docs/PLAN.md":
            marker_only = body.strip().startswith("<!--") and "completed" in body and body.strip().endswith("-->")
            if marker_only:
                try:
                    dest = (pathlib.Path(work_dir) / rel).resolve()
                    with open(dest, "a", encoding="utf-8") as f:
                        f.write("\n" + body.strip() + "\n")
                    return f"OK: appended completion marker to docs/PLAN.md"
                except Exception as e:
                    return f"ERROR: {e}"
            return "ERROR: docs/PLAN.md is protected — only completion markers may be appended"
        try:
            dest = _safe_path(rel, work_dir, check_write=True)
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(body, encoding="utf-8")
            return f"OK: wrote {len(body)} bytes to {rel}"
        except Exception as e:
            return f"ERROR: {e}"

    elif name == "read_file":
        rel = args.get("path", "")
        try:
            src = _safe_path(rel, work_dir)
            return src.read_text(encoding="utf-8", errors="replace")
        except Exception as e:
            return f"ERROR: {e}"

    elif name == "list_directory":
        rel = args.get("path", ".") or "."
        try:
            d = _safe_path(rel, work_dir)
            if not d.is_dir():
                return f"ERROR: not a directory: {rel}"
            entries = sorted(str(p.relative_to(pathlib.Path(work_dir).resolve()))
                             for p in d.iterdir())
            return "\n".join(entries) if entries else "(empty)"
        except Exception as e:
            return f"ERROR: {e}"

    elif name == "run_bash":
        cmd     = args.get("command", "")
        t_out   = int(args.get("timeout", 60))
        try:
            result = subprocess.run(
                cmd, shell=True, cwd=work_dir,
                capture_output=True, text=True, timeout=t_out,
            )
            out = (result.stdout or "") + (result.stderr or "")
            return f"exit={result.returncode}\n{out}"
        except subprocess.TimeoutExpired:
            return f"ERROR: command timed out after {t_out}s"
        except Exception as e:
            return f"ERROR: {e}"

    else:
        return f"ERROR: unknown tool {name!r}"

# ── HTTP helper ───────────────────────────────────────────────────────────────
def chat_request(messages):
    body = {
        "model":      model,
        "messages":   messages,
        "tools":      TOOLS,
        "stream":     False,
        "max_tokens": 16384,
    }
    data = json.dumps(body, ensure_ascii=False).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(endpoint, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = resp.status
            raw    = resp.read().decode("utf-8", errors="replace")
            return status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        return e.code, raw
    except Exception as e:
        return 0, str(e)

# ── Agentic loop ──────────────────────────────────────────────────────────────
messages = [
    {"role": "system", "content": system_content},
    {"role": "user",   "content": user_content},
]

MAX_ITER  = 20
log_lines = []

def emit(line):
    log_lines.append(line)
    print(line, flush=True)

rate_limited = False
error_exit   = False

for iteration in range(MAX_ITER):
    emit(f"[router_http] iteration {iteration + 1}/{MAX_ITER} — calling {endpoint}")
    status, raw = chat_request(messages)

    # ── Rate-limit check ──────────────────────────────────────────────────────
    if status == 429:
        emit(f"[router_http] HTTP 429 rate-limited")
        rate_limited = True
        break

    # ── Quota pattern inside body ─────────────────────────────────────────────
    import re as _re
    if _re.search(r"rate.limit|quota.exceeded|token.limit|billing_hard_limit|insufficient_quota",
                  raw, _re.IGNORECASE):
        emit(f"[router_http] quota/rate-limit pattern in body")
        rate_limited = True
        break

    if status not in (200, 201):
        emit(f"[router_http] HTTP {status} error: {raw[:500]}")
        error_exit = True
        break

    # ── Parse response ────────────────────────────────────────────────────────
    try:
        resp_json = json.loads(raw)
    except Exception as e:
        emit(f"[router_http] JSON parse error: {e}\nRaw: {raw[:500]}")
        error_exit = True
        break

    choices = resp_json.get("choices", [])
    if not choices:
        emit(f"[router_http] no choices in response")
        break

    choice  = choices[0]
    message = choice.get("message", {})
    finish  = choice.get("finish_reason", "")

    # Emit text content to log
    text_content = message.get("content") or ""
    if text_content:
        emit(text_content)

    tool_calls = message.get("tool_calls") or []

    # Append assistant turn
    messages.append({
        "role":       "assistant",
        "content":    text_content or None,
        "tool_calls": tool_calls if tool_calls else None,
    })
    # Clean None values
    messages[-1] = {k: v for k, v in messages[-1].items() if v is not None}

    # ── Execute tool calls ────────────────────────────────────────────────────
    if tool_calls:
        for tc in tool_calls:
            tc_id   = tc.get("id", "")
            tc_name = tc.get("function", {}).get("name", "")
            tc_args_raw = tc.get("function", {}).get("arguments", "{}")
            try:
                tc_args = json.loads(tc_args_raw)
            except Exception:
                tc_args = {}

            emit(f"[router_http] tool_call: {tc_name}({json.dumps(tc_args, ensure_ascii=False)[:200]})")
            result = execute_tool(tc_name, tc_args)
            emit(f"[router_http] tool_result: {str(result)[:500]}")

            messages.append({
                "role":         "tool",
                "tool_call_id": tc_id,
                "content":      str(result),
            })
        # Continue loop to send tool results back
        continue

    # ── No tool calls → done ──────────────────────────────────────────────────
    if finish in ("stop", "end_turn", ""):
        emit(f"[router_http] finish_reason={finish!r} — done after {iteration + 1} iteration(s)")
        break

    # Unexpected finish reason — stop anyway
    emit(f"[router_http] unexpected finish_reason={finish!r} — stopping")
    break

else:
    emit(f"[router_http] reached max iterations ({MAX_ITER})")

# ── Write log file ────────────────────────────────────────────────────────────
os.makedirs(os.path.dirname(os.path.abspath(log_file)), exist_ok=True)
with open(log_file, "w", encoding="utf-8") as fh:
    fh.write("\n".join(log_lines) + "\n")

if rate_limited:
    sys.exit(2)
if error_exit:
    sys.exit(1)
sys.exit(0)
PYEOF
}

# ── run_driver ────────────────────────────────────────────────────────────────
# Main driver entry point implementing the ExecutionDriver contract (spec §8.2).
#
# Usage: run_driver <driver> <stage> <work_dir> <prompt_file> <model> <log_file>
run_driver() {
    local driver="${1:?driver required}"
    local stage="${2:?stage required}"
    local work_dir="${3:?work_dir required}"
    local prompt_file="${4:?prompt_file required}"
    local model="${5:?model required}"
    local log_file="${6:?log_file required}"

    # ── Guard: required dependencies ──────────────────────────────────────────
    if [[ ! -f "${prompt_file}" ]]; then
        log_error "[${stage}] Prompt file not found: ${prompt_file}"
        return 3
    fi
    if ! command -v curl &>/dev/null; then
        log_error "[${stage}] curl is required for driver=router_http but not installed"
        log_info "  Install curl: brew install curl  or  apt-get install curl"
        return 3
    fi
    if ! command -v python3 &>/dev/null; then
        log_error "[${stage}] python3 is required for driver=router_http but not installed"
        return 3
    fi

    mkdir -p "$(dirname "${log_file}")"

    # ── Read router config ────────────────────────────────────────────────────
    local endpoint="${NINE_ROUTER_ENDPOINT:-${_ROUTER_DEFAULT_ENDPOINT}}"
    local token="${NINE_ROUTER_TOKEN:-}"

    local skeleton_yaml="${work_dir}/config/skeleton.yaml"
    if [[ -f "${skeleton_yaml}" ]]; then
        local _ep; _ep="$(_config_yaml_get "${skeleton_yaml}" "router.endpoint")"
        if [[ -n "${_ep}" ]]; then
            # Ensure endpoint has /chat/completions path
            endpoint="${_ep%/}/chat/completions"
        fi
    fi

    # ── Template variable substitution in prompt file ─────────────────────────
    local task_number="${SKELETON_TASK_NUMBER:-0}"
    local plan_path="${SKELETON_PLAN:-docs/PLAN.md}"
    local skills_csv; skills_csv="$(build_skills_csv)"
    local workspace_constraint="${AGENT_WORKSPACE_CONSTRAINT}"

    local task_prompt
    task_prompt="$(cat "${prompt_file}")"

    # Substitute {{TEMPLATE_VARS}} in the user prompt
    task_prompt="${task_prompt//\{\{TASK_NUMBER\}\}/${task_number}}"
    task_prompt="${task_prompt//\{\{PLAN_PATH\}\}/${plan_path}}"
    task_prompt="${task_prompt//\{\{SKILLS_CSV\}\}/${skills_csv}}"
    task_prompt="${task_prompt//\{\{WORKSPACE_CONSTRAINT\}\}/${workspace_constraint}}"
    task_prompt="${task_prompt//\{\{STAGE_NAME\}\}/${stage}}"

    # ── Assemble system prompt (4 components) ─────────────────────────────────
    local system_prompt
    system_prompt="$(_assemble_system_prompt "${stage}" "${work_dir}")"

    # ── Write prompts to temp files ───────────────────────────────────────────
    local sys_tmp usr_tmp
    sys_tmp="$(mktemp)"
    usr_tmp="$(mktemp)"

    printf '%s' "${system_prompt}" > "${sys_tmp}"
    printf '%s' "${task_prompt}"   > "${usr_tmp}"

    log_step "[${stage}] router_http → ${endpoint} (model: ${model})"

    # ── Decide mode: tool calling vs streaming ────────────────────────────────
    if _stage_uses_tools "${stage}"; then
        # ── Agentic tool-calling loop (non-streaming) ─────────────────────────
        log_step "[${stage}] using agentic tool-calling loop"
        local loop_exit=0
        _run_agentic_loop \
            "${endpoint}" "${token}" "${model}" \
            "${sys_tmp}" "${usr_tmp}" \
            "${work_dir}" "${stage}" "${log_file}" || loop_exit=$?

        # sys_tmp / usr_tmp are deleted inside the Python script
        case "${loop_exit}" in
            0)
                log_ok "[${stage}] router_http agentic loop completed"
                return 0
                ;;
            2)
                log_warn "[${stage}] Quota/rate-limit — exit 2 for quota_retry"
                return 2
                ;;
            *)
                log_error "[${stage}] Agentic loop failed (exit ${loop_exit})"
                return 1
                ;;
        esac
    fi

    # ── Assessment stage: one-shot streaming (original behaviour) ─────────────
    local body_tmp
    body_tmp="$(mktemp)"

    python3 - "${model}" "${sys_tmp}" "${usr_tmp}" > "${body_tmp}" <<'PYEOF'
import sys, json, os

model        = sys.argv[1]
sys_file     = sys.argv[2]
usr_file     = sys.argv[3]

with open(sys_file, encoding="utf-8") as f:
    system_content = f.read()
with open(usr_file, encoding="utf-8") as f:
    user_content = f.read()

os.unlink(sys_file)
os.unlink(usr_file)

body = {
    "model":    model,
    "messages": [
        {"role": "system", "content": system_content},
        {"role": "user",   "content": user_content},
    ],
    "stream":     True,
    "max_tokens": 16384,
}
print(json.dumps(body, ensure_ascii=False))
PYEOF

    # ── HTTP request (streaming) ──────────────────────────────────────────────
    local http_status_tmp
    http_status_tmp="$(mktemp)"
    local curl_exit=0

    local curl_args=(
        --silent
        --no-buffer
        --write-out "%{http_code}"
        --output "${log_file}"
        --max-time "${_ROUTER_TIMEOUT}"
        -H "Content-Type: application/json"
        -d "@${body_tmp}"
    )
    [[ -n "${token}" ]] && curl_args+=(-H "Authorization: Bearer ${token}")
    curl_args+=("${endpoint}")

    curl "${curl_args[@]}" > "${http_status_tmp}" 2>&1 || curl_exit=$?

    local http_status
    http_status="$(cat "${http_status_tmp}" 2>/dev/null | tr -d '[:space:]' || echo "000")"
    rm -f "${body_tmp}" "${http_status_tmp}"

    # ── Handle curl failure ───────────────────────────────────────────────────
    if [[ ${curl_exit} -ne 0 ]]; then
        log_error "[${stage}] curl failed (exit ${curl_exit}) — network/connection error"
        printf '[%s] curl_exit=%s endpoint=%s\n' "${stage}" "${curl_exit}" "${endpoint}" >> "${log_file}"
        return 3
    fi

    # ── Check response body for quota/rate-limit patterns ────────────────────
    # Some APIs embed 429-type errors inside a 200 streaming response
    if grep -qi "rate.limit\|quota.exceeded\|token.limit\|billing_hard_limit\|insufficient_quota" \
            "${log_file}" 2>/dev/null; then
        log_warn "[${stage}] Quota/rate-limit pattern in response body — exit 2"
        return 2
    fi

    # ── Parse HTTP status ─────────────────────────────────────────────────────
    case "${http_status}" in
        200|201)
            log_ok "[${stage}] router_http completed (HTTP ${http_status})"
            # Apply file changes from the LLM response (extract code blocks → write to disk)
            _apply_file_changes "${log_file}" "${work_dir}" "${stage}"
            return 0
            ;;
        429)
            log_warn "[${stage}] HTTP 429 rate-limited — exit 2 for quota_retry"
            return 2
            ;;
        401|403)
            log_error "[${stage}] HTTP ${http_status} authorization error — check NINE_ROUTER_TOKEN"
            return 1
            ;;
        400)
            log_error "[${stage}] HTTP 400 bad request — check prompt or model name"
            return 1
            ;;
        5*)
            log_error "[${stage}] HTTP ${http_status} server error"
            return 1
            ;;
        000)
            log_error "[${stage}] No HTTP response — is 9router running?"
            log_info "  Start: skeleton router start"
            return 3
            ;;
        *)
            log_error "[${stage}] Unexpected HTTP status: ${http_status}"
            return 1
            ;;
    esac
}

# ── Main entry point ──────────────────────────────────────────────────────────
main() {
    # Handle --print-prompt flag: assemble system prompt without HTTP call
    # Used by the prompt assembly unit test.
    if [[ "${1:-}" == "--print-prompt" ]]; then
        shift
        local _driver="${1:-router_http}"
        local _stage="${2:-task-runner}"
        local _work_dir="${3:-$(pwd)}"
        local _prompt_file="${4:-}"
        local _model="${5:-claude-sonnet-4.6}"

        log_info "[${_stage}] --print-prompt: assembling system prompt (no HTTP call)"

        local _system_prompt
        _system_prompt="$(_assemble_system_prompt "${_stage}" "${_work_dir}")"
        echo "=== SYSTEM PROMPT ==="
        echo "${_system_prompt}"
        echo "=== END SYSTEM PROMPT ==="

        if [[ -n "${_prompt_file}" && -f "${_prompt_file}" ]]; then
            echo "=== TASK PROMPT (from ${_prompt_file}) ==="
            cat "${_prompt_file}"
            echo "=== END TASK PROMPT ==="
        fi
        return 0
    fi

    run_driver "$@"
}

# Only execute main when run directly (not when sourced as a library)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
