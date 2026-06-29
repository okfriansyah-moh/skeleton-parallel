#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scripts/lib/config.sh — Load and validate skeleton-parallel configuration
# ─────────────────────────────────────────────────────────────────────────────
# Implements the identity/runtime split:
#   .ai/manifest.yaml     → identity (provider, domain, plan, skills.always)
#   config/skeleton.yaml  → runtime  (driver, router, retries, acceptance)
#
# Manifest wins on any identity conflict.
#
# Exports after load_config():
#   SKELETON_DRIVER         — execution.driver from skeleton.yaml
#   SKELETON_PROVIDER       — defaults.provider from manifest (or cli.provider from skeleton.yaml)
#   SKELETON_PLAN           — defaults.plan from manifest
#   SKELETON_SKILLS_ALWAYS  — skills.always list (space-separated) from manifest
#   SKELETON_MODEL          — execution.cli.model or execution.cursor.model
#
# Usage:
#   source "${SKELETON_ROOT}/scripts/lib/config.sh"
#   load_config "${PROJECT_ROOT}"
#   validate_config
#   echo "${SKELETON_DRIVER}"
# ─────────────────────────────────────────────────────────────────────────────

# Guard: idempotent sourcing
[[ -n "${CONFIG_LOADED:-}" ]] && return 0
CONFIG_LOADED=1

# Depend on common utilities
_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${_CONFIG_LIB_DIR}/common.sh"

# ── _config_yaml_get ──────────────────────────────────────────────────────────
# Extract a single scalar value at a dotted YAML path using Python stdlib.
# Returns empty string when the file is missing or the key is not found.
#
# Usage: _config_yaml_get <yaml_file> <dotted.key>
_config_yaml_get() {
    local yaml_file="$1"
    local dotted_key="$2"

    [[ -f "${yaml_file}" ]] || { echo ""; return 0; }

    python3 - "${yaml_file}" "${dotted_key}" <<'PYEOF'
import sys, re

def parse_yaml(filepath):
    """
    Minimal YAML parser for nested scalar mappings and simple lists.
    Returns a flat dict of dotted_key -> value for scalars
    and a dict of dotted_key -> [items] for lists.
    """
    scalars = {}
    lists   = {}
    # key_stack: list of (indent_level, key_name) pairs
    key_stack = []
    # list tracking
    current_list_dotted = None
    current_list_indent = -1

    with open(filepath) as f:
        for raw_line in f:
            line = raw_line.rstrip('\n')
            stripped = line.rstrip()
            if not stripped:
                continue
            content = stripped.lstrip()
            if content.startswith('#'):
                continue
            indent = len(stripped) - len(content)

            # ── List item ─────────────────────────────────────────────
            m = re.match(r'^-\s+(.*)$', content)
            if m:
                val = m.group(1).strip().strip('"\'')
                if current_list_dotted and indent > current_list_indent:
                    lists.setdefault(current_list_dotted, []).append(val)
                continue

            # ── Key: [value] ──────────────────────────────────────────
            m = re.match(r'^([^:#\[{]+?):\s*(.*)$', content)
            if not m:
                continue
            k = m.group(1).strip()
            v = m.group(2).strip().strip('"\'')
            # Strip inline comments (only after whitespace)
            v = re.sub(r'\s+#.*$', '', v).strip()

            # Pop key_stack to correct indent level
            while key_stack and indent <= key_stack[-1][0]:
                key_stack.pop()

            key_stack.append((indent, k))
            dotted = '.'.join(item[1] for item in key_stack)

            if v:
                scalars[dotted] = v
                current_list_dotted = None
            else:
                # Could be a nested mapping or a list; track for list items
                current_list_dotted = dotted
                current_list_indent = indent

    return scalars, lists

filepath   = sys.argv[1]
target_key = sys.argv[2]

try:
    scalars, lists = parse_yaml(filepath)
    if target_key in scalars:
        print(scalars[target_key])
    elif target_key in lists:
        print(' '.join(lists[target_key]))
    else:
        print('')
except Exception:
    print('')
PYEOF
}

# ── load_config ───────────────────────────────────────────────────────────────
# Load both config files and export all SKELETON_* env vars.
# Missing files are tolerated; defaults are applied.
#
# Usage: load_config [project_root]
load_config() {
    local project_root="${1:-${PROJECT_ROOT}}"

    local skeleton_yaml="${project_root}/config/skeleton.yaml"
    local manifest_yaml="${project_root}/.ai/manifest.yaml"

    # ── Read from config/skeleton.yaml (runtime) ─────────────────────────────
    local _driver
    _driver="$(_config_yaml_get "${skeleton_yaml}" "execution.driver")"

    local _cli_provider
    _cli_provider="$(_config_yaml_get "${skeleton_yaml}" "execution.cli.provider")"

    local _cli_model
    _cli_model="$(_config_yaml_get "${skeleton_yaml}" "execution.cli.model")"

    local _cursor_model
    _cursor_model="$(_config_yaml_get "${skeleton_yaml}" "execution.cursor.model")"

    # ── Read from .ai/manifest.yaml (identity — overrides on conflict) ────────
    local _manifest_provider
    _manifest_provider="$(_config_yaml_get "${manifest_yaml}" "defaults.provider")"

    local _manifest_plan
    _manifest_plan="$(_config_yaml_get "${manifest_yaml}" "defaults.plan")"

    local _manifest_skills
    _manifest_skills="$(_config_yaml_get "${manifest_yaml}" "skills.always")"

    # ── Resolve final values (manifest wins on identity fields) ───────────────
    # SKELETON_DRIVER — from skeleton.yaml only (runtime); NO default applied here.
    # An absent key leaves SKELETON_DRIVER empty so validate_config() can catch it.
    SKELETON_DRIVER="${_driver}"

    # SKELETON_PROVIDER — manifest.defaults.provider wins; fallback to cli.provider
    SKELETON_PROVIDER="${_manifest_provider:-${_cli_provider:-copilot}}"

    # SKELETON_PLAN — from manifest; fallback to docs/PLAN.md
    SKELETON_PLAN="${_manifest_plan:-docs/PLAN.md}"

    # SKELETON_SKILLS_ALWAYS — from manifest skills.always (space-separated)
    SKELETON_SKILLS_ALWAYS="${_manifest_skills:-}"

    # SKELETON_MODEL — driver-specific model
    case "${SKELETON_DRIVER}" in
        sdk_cursor)
            SKELETON_MODEL="${_cursor_model:-composer-2.5}"
            ;;
        *)
            SKELETON_MODEL="${_cli_model:-claude-sonnet-4-6}"
            ;;
    esac

    export SKELETON_DRIVER SKELETON_PROVIDER SKELETON_PLAN \
           SKELETON_SKILLS_ALWAYS SKELETON_MODEL

    log_ok "Config loaded — driver: ${SKELETON_DRIVER}, provider: ${SKELETON_PROVIDER}, plan: ${SKELETON_PLAN}"
}

# ── validate_config ───────────────────────────────────────────────────────────
# Validate the loaded config. Must be called after load_config().
# Exits non-zero on any violation.
#
# Checks:
#   1. execution.driver is a valid value
#   2. cli_subscription + cli.provider=cursor → die with fix hint
#   3. sdk_cursor + Node.js version ≥ 22.13 (deferred check — see Task 11)
#
# Usage: validate_config
validate_config() {
    local driver="${SKELETON_DRIVER:-}"

    # ── Guard 1: driver must be a known value ─────────────────────────────────
    case "${driver}" in
        router_http|cli_subscription|sdk_cursor)
            # valid
            ;;
        "")
            die "Missing required config key 'execution.driver' in config/skeleton.yaml.
  Valid values: router_http | cli_subscription | sdk_cursor
  Run 'skeleton doctor' for a full config health check."
            ;;
        *)
            die "Invalid execution.driver '${driver}' in config/skeleton.yaml.
  Valid values: router_http | cli_subscription | sdk_cursor
  Run 'skeleton doctor' for a full config health check."
            ;;
    esac

    # ── Guard 2: cli_subscription + cursor is INVALID ─────────────────────────
    # Cursor requires the sdk_cursor driver; it cannot be invoked via CLI subscription.
    if [[ "${driver}" == "cli_subscription" ]]; then
        local provider="${SKELETON_PROVIDER:-}"
        if [[ "${provider}" == "cursor" ]]; then
            die "Invalid configuration: execution.driver=cli_subscription cannot use provider=cursor.
  Cursor requires the Cursor SDK driver. Fix:
    execution:
      driver: sdk_cursor        # change from cli_subscription
  Run 'skeleton doctor' for more details."
        fi
    fi

    # ── Guard 3: sdk_cursor requires Node.js ≥ 22.13 (deferred to Task 11) ───
    if [[ "${driver}" == "sdk_cursor" ]]; then
        if command -v node &>/dev/null; then
            local node_ver
            node_ver="$(node --version 2>/dev/null | sed 's/^v//')"
            local node_major node_minor
            node_major="$(echo "${node_ver}" | cut -d. -f1)"
            node_minor="$(echo "${node_ver}" | cut -d. -f2)"
            if (( node_major < 22 )) || ( (( node_major == 22 )) && (( node_minor < 13 )) ); then
                die "execution.driver=sdk_cursor requires Node.js ≥ 22.13.
  Found: v${node_ver}
  Upgrade: https://nodejs.org or use nvm/fnm to install Node.js 22.13+
  Run 'skeleton doctor' for more details."
            fi
        else
            die "execution.driver=sdk_cursor requires Node.js ≥ 22.13 but node is not installed.
  Install: https://nodejs.org or use nvm/fnm
  Run 'skeleton doctor' for more details."
        fi
    fi

    log_ok "Config validated — driver: ${driver}"
    return 0
}

# ── get_driver ────────────────────────────────────────────────────────────────
# Return the current execution driver. load_config() must have been called.
#
# Usage: driver=$(get_driver)
get_driver() {
    echo "${SKELETON_DRIVER:-cli_subscription}"
}

# ── get_manifest_provider ─────────────────────────────────────────────────────
# Return the resolved provider. load_config() must have been called.
#
# Usage: provider=$(get_manifest_provider)
get_manifest_provider() {
    echo "${SKELETON_PROVIDER:-copilot}"
}
