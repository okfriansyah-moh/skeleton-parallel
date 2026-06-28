#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# router/wrap.sh — skeleton-wrapped 9router daemon management
# ─────────────────────────────────────────────────────────────────────────────
# Manages the 9router daemon lifecycle: install, start, stop, status, health.
# Invoked via: skeleton router <subcommand>
#
# Subcommands:
#   install   — install 9router via npm or docker (per 9router-pin.json)
#   start     — start daemon on port 20128; write PID to .skeleton-dev/router.pid
#   stop      — stop daemon using .skeleton-dev/router.pid
#   status    — print running/stopped state (safe even if daemon not installed)
#   health    — HTTP GET /health → exit 0 if healthy, 1 if not
#   check     — silent health check → exit 0 if up, 1 if down (no crash)
#   oauth     — print OAuth connection instructions
#
# Usage:
#   skeleton router install
#   skeleton router start
#   skeleton router status
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Resolve skeleton root ─────────────────────────────────────────────────────
_WRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SKELETON_ROOT="$(cd "${_WRAP_DIR}/.." && pwd)"

# Source common utilities
# shellcheck source=scripts/lib/common.sh
source "${_SKELETON_ROOT}/scripts/lib/common.sh"

# ── Constants (from 9router-pin.json) ─────────────────────────────────────────
_PIN_FILE="${_WRAP_DIR}/9router-pin.json"
_ROUTER_PORT="${NINE_ROUTER_PORT:-20128}"
_ROUTER_HEALTH_URL="http://localhost:${_ROUTER_PORT}/api/health"
_ROUTER_DASHBOARD_URL="http://localhost:${_ROUTER_PORT}/dashboard"

# PID file location (inside project's .skeleton-dev/)
_router_pid_file() {
    local project_root="${PROJECT_ROOT:-$(pwd)}"
    echo "${project_root}/.skeleton-dev/router.pid"
}

# ── router_install ────────────────────────────────────────────────────────────
# Detect or install 9router. Checks for an existing binary first, then reads
# router/9router-pin.json for a custom npm package or docker image override.
# Falls back to a manual install guide if nothing is found.
router_install() {
    log_step "[router] Checking 9router installation..."

    # Already in PATH — nothing to do
    if command -v 9router &>/dev/null; then
        log_ok "[router] 9router already installed: $(command -v 9router)"
        _generate_inject_env_stub
        return 0
    fi

    # Read npm package / docker image from pin file; default to known package name
    local npm_pkg="9router" docker_image=""
    if command -v python3 &>/dev/null && [[ -f "${_PIN_FILE}" ]]; then
        local _pin_npm _pin_docker
        _pin_npm="$(python3 -c "
import json
d = json.load(open('${_PIN_FILE}'))
v = d.get('npm', '').strip()
if v and v != '@9router/server':
    print(v)
" 2>/dev/null || true)"
        _pin_docker="$(python3 -c "
import json
d = json.load(open('${_PIN_FILE}'))
v = d.get('docker', '').strip()
if v and v != '9router/server:latest':
    print(v)
" 2>/dev/null || true)"
        [[ -n "${_pin_npm}" ]]    && npm_pkg="${_pin_npm}"
        [[ -n "${_pin_docker}" ]] && docker_image="${_pin_docker}"
    fi

    # npm install (preferred — real package: github.com/decolua/9router)
    if command -v npm &>/dev/null; then
        log_info "[router] Installing via npm: ${npm_pkg}"
        if npm install -g "${npm_pkg}"; then
            log_ok "[router] 9router installed (npm install -g ${npm_pkg})"
            _generate_inject_env_stub
            return 0
        fi
        log_warn "[router] npm install failed, trying next method..."
    else
        log_warn "[router] npm not found — install Node.js first: https://nodejs.org"
    fi

    # Docker fallback (only if an image is pinned in 9router-pin.json)
    if [[ -n "${docker_image}" ]] && command -v docker &>/dev/null; then
        log_info "[router] Pulling docker image: ${docker_image}"
        if docker pull "${docker_image}"; then
            log_ok "[router] 9router docker image pulled: ${docker_image}"
            _generate_inject_env_stub
            return 0
        fi
        log_warn "[router] docker pull failed"
    fi

    # Nothing worked
    log_error "[router] 9router could not be installed automatically."
    echo ""
    echo "  Manual install:"
    echo "    npm install -g 9router"
    echo "    9router                  # starts the daemon"
    echo ""
    echo "  GitHub: https://github.com/decolua/9router"
    echo ""
    echo "  Once installed, run:"
    echo "    skeleton router start"
    echo "    skeleton router status"
    return 1
}

# ── _generate_inject_env_stub ─────────────────────────────────────────────────
# Write a stub router/inject-env.sh that sources provider-specific tokens.
# This file is meant to be populated after running: skeleton router oauth
_generate_inject_env_stub() {
    local inject_file="${_WRAP_DIR}/inject-env.sh"
    if [[ -f "${inject_file}" ]]; then
        log_info "[router] inject-env.sh already exists — skipping"
        return 0
    fi
    cat > "${inject_file}" <<'EOF'
#!/usr/bin/env bash
# router/inject-env.sh — Provider env vars injected into CLI drivers
# Generated by: skeleton router install
# Populated by: skeleton router oauth
#
# Set provider tokens/endpoints here after running 'skeleton router oauth'.
# This file is sourced by router.sh inject_cli_env() when router.inject=true.
# ─────────────────────────────────────────────────────────────────────────────

# ── Copilot proxy settings (set after: skeleton router oauth copilot) ─────────
# export COPILOT_PROXY_URL="http://localhost:20128/v1"
# export COPILOT_GITHUB_TOKEN="<token-from-oauth>"

# ── Claude proxy settings (set after: skeleton router oauth claude) ───────────
# export CLAUDE_PROXY_URL="http://localhost:20128/v1"
# export ANTHROPIC_BASE_URL="http://localhost:20128/v1"

# ── Codex proxy settings (set after: skeleton router oauth codex) ─────────────
# export OPENAI_BASE_URL="http://localhost:20128/v1"
# export OPENAI_API_KEY="<token-from-oauth>"

# ─────────────────────────────────────────────────────────────────────────────
# End of inject-env.sh
EOF
    chmod 600 "${inject_file}"  # restrict permissions — may contain tokens
    log_ok "[router] Created: router/inject-env.sh"
    log_info "[router] Run 'skeleton router oauth' to configure provider tokens"
}

# ── router_start ──────────────────────────────────────────────────────────────
# Start the 9router daemon on the configured port.
# Writes PID to .skeleton-dev/router.pid.
router_start() {
    local pid_file
    pid_file="$(_router_pid_file)"

    # Check if already running
    if _router_pid_alive; then
        local existing_pid
        existing_pid="$(cat "${pid_file}" 2>/dev/null || echo "?")"
        log_warn "[router] 9router already running (PID: ${existing_pid})"
        return 0
    fi

    # Check 9router binary
    if ! command -v 9router &>/dev/null && ! command -v npx &>/dev/null; then
        die "[router] 9router not installed. Run: skeleton router install"
    fi

    mkdir -p "$(dirname "${pid_file}")"

    # Log file so startup errors are visible
    local log_file
    log_file="$(dirname "${pid_file}")/9router.log"

    log_step "[router] Starting 9router on port ${_ROUTER_PORT}..."

    if command -v 9router &>/dev/null; then
        # -p  port   -n  no-browser (headless daemon mode)
        9router -p "${_ROUTER_PORT}" -n > "${log_file}" 2>&1 &
    else
        npx 9router -p "${_ROUTER_PORT}" -n > "${log_file}" 2>&1 &
    fi

    local pid=$!
    echo "${pid}" > "${pid_file}"

    # Wait up to 5 seconds for health check to pass
    local attempts=0
    while (( attempts < 10 )); do
        sleep 0.5
        if _router_http_healthy; then
            log_ok "[router] 9router started (PID: ${pid}, port: ${_ROUTER_PORT})"
            log_info "[router] Dashboard: ${_ROUTER_DASHBOARD_URL}"
            log_info "[router] Logs:      ${log_file}"
            return 0
        fi
        (( attempts++ ))
    done

    log_warn "[router] 9router process launched (PID: ${pid}) but health check not responding yet"
    log_info "[router] Check logs: cat ${log_file}"
    log_info "[router] Check: skeleton router health"
    return 0
}

# ── _find_router_pid_by_port ──────────────────────────────────────────────────
# Fallback: find the PID of whatever process is listening on the router port.
_find_router_pid_by_port() {
    lsof -iTCP:"${_ROUTER_PORT}" -sTCP:LISTEN -nP 2>/dev/null \
        | awk 'NR>1 {print $2}' | head -1
}

# ── router_stop ───────────────────────────────────────────────────────────────
# Stop the 9router daemon. Tries PID file first; falls back to port lookup
# so stale PID files never block a running daemon from being stopped.
router_stop() {
    local pid_file
    pid_file="$(_router_pid_file)"

    local pid=""

    # Try PID file first
    if [[ -f "${pid_file}" ]]; then
        pid="$(cat "${pid_file}" 2>/dev/null || true)"
        if [[ -n "${pid}" ]] && ! kill -0 "${pid}" 2>/dev/null; then
            log_warn "[router] PID file stale (${pid} not running) — checking port ${_ROUTER_PORT}..."
            pid=""
        fi
    fi

    # Fallback: find by port
    if [[ -z "${pid}" ]]; then
        pid="$(_find_router_pid_by_port)"
        if [[ -n "${pid}" ]]; then
            log_info "[router] Found 9router via port ${_ROUTER_PORT} (PID: ${pid})"
        fi
    fi

    if [[ -z "${pid}" ]]; then
        log_warn "[router] 9router is not running on port ${_ROUTER_PORT}"
        rm -f "${pid_file}"
        return 0
    fi

    log_step "[router] Stopping 9router (PID: ${pid})..."
    kill -TERM "${pid}" 2>/dev/null || true

    # Wait up to 5 seconds for graceful shutdown
    local attempts=0
    while (( attempts < 10 )); do
        sleep 0.5
        if ! kill -0 "${pid}" 2>/dev/null; then
            break
        fi
        (( attempts++ ))
    done

    # Force kill if still running
    if kill -0 "${pid}" 2>/dev/null; then
        kill -KILL "${pid}" 2>/dev/null || true
    fi

    rm -f "${pid_file}"
    log_ok "[router] 9router stopped"
}

# ── router_status ─────────────────────────────────────────────────────────────
# Print human-readable running/stopped state.
# Safe: never crashes even if daemon or npm is not installed.
router_status() {
    local pid_file
    pid_file="$(_router_pid_file)"

    echo ""
    echo -e "${BOLD}9router Daemon Status${NC}"
    echo -e "────────────────────────────────────────"

    # Installed?
    local installed=false
    if command -v 9router &>/dev/null; then
        echo -e "  Installed:  ${GREEN}yes${NC} ($(command -v 9router))"
        installed=true
    elif command -v npx &>/dev/null; then
        echo -e "  Installed:  ${YELLOW}via npx${NC}"
        installed=true
    else
        echo -e "  Installed:  ${RED}no${NC} — run: skeleton router install"
    fi

    # Running?
    if _router_pid_alive; then
        local pid
        pid="$(cat "${pid_file}" 2>/dev/null || echo "?")"
        echo -e "  Running:    ${GREEN}yes${NC} (PID: ${pid})"
    else
        echo -e "  Running:    ${RED}no${NC}"
        [[ "${installed}" == "true" ]] && echo -e "             → run: skeleton router start"
    fi

    # Health?
    if _router_http_healthy; then
        echo -e "  Health:     ${GREEN}OK${NC} (${_ROUTER_HEALTH_URL})"
    else
        echo -e "  Health:     ${YELLOW}unreachable${NC} (${_ROUTER_HEALTH_URL})"
    fi

    # Port + dashboard
    echo -e "  Port:       ${_ROUTER_PORT}"
    echo -e "  Dashboard:  ${_ROUTER_DASHBOARD_URL}"

    # inject-env.sh
    if [[ -f "${_WRAP_DIR}/inject-env.sh" ]]; then
        echo -e "  inject-env: ${GREEN}configured${NC}"
    else
        echo -e "  inject-env: ${YELLOW}not configured${NC} — run: skeleton router oauth"
    fi

    echo ""
}

# ── router_health ─────────────────────────────────────────────────────────────
# HTTP GET the health endpoint.
# Exit 0 if healthy, 1 if not reachable.
router_health() {
    if _router_http_healthy; then
        log_ok "[router] Health check passed (${_ROUTER_HEALTH_URL})"
        return 0
    else
        log_error "[router] Health check failed — daemon may not be running"
        log_info "  Start with: skeleton router start"
        return 1
    fi
}

# ── router_check ──────────────────────────────────────────────────────────────
# Silent health check for use in scripts.
# Exit 0 if daemon is up and healthy, 1 if not. Never crashes.
router_check() {
    _router_http_healthy && return 0 || return 1
}

# ── router_oauth ──────────────────────────────────────────────────────────────
# Print OAuth setup instructions or open the guide.
router_oauth() {
    local provider="${1:-}"
    local oauth_guide="${_WRAP_DIR}/oauth-guide.md"

    if [[ -f "${oauth_guide}" ]]; then
        if command -v cat &>/dev/null; then
            echo ""
            cat "${oauth_guide}"
            echo ""
        fi
    else
        log_info "[router] OAuth guide not found at ${oauth_guide}"
        log_info "  Run: skeleton router install  (to generate the guide)"
    fi

    if [[ -n "${provider}" ]]; then
        log_info "[router] After completing OAuth for ${provider}:"
        log_info "  Edit router/inject-env.sh to add the token"
        log_info "  Then restart: skeleton router stop && skeleton router start"
    fi
}

# ── Internal helpers ──────────────────────────────────────────────────────────

# Check if the PID in the pid file is alive
_router_pid_alive() {
    local pid_file
    pid_file="$(_router_pid_file)"
    [[ -f "${pid_file}" ]] || return 1
    local pid
    pid="$(cat "${pid_file}" 2>/dev/null || true)"
    [[ -n "${pid}" ]] || return 1
    kill -0 "${pid}" 2>/dev/null
}

# Check if the HTTP health endpoint responds
_router_http_healthy() {
    if command -v curl &>/dev/null; then
        curl --silent --fail --max-time 2 "${_ROUTER_HEALTH_URL}" &>/dev/null
        return $?
    elif command -v wget &>/dev/null; then
        wget --quiet --timeout=2 --spider "${_ROUTER_HEALTH_URL}" &>/dev/null
        return $?
    fi
    return 1  # cannot check — assume not healthy
}

# ── Main dispatcher ───────────────────────────────────────────────────────────
main() {
    local subcommand="${1:-status}"
    shift || true

    case "${subcommand}" in
        install) router_install "$@" ;;
        start)        router_start ;;
        stop|down)    router_stop ;;
        status)       router_status ;;
        health)       router_health ;;
        check)        router_check ;;
        oauth)        router_oauth "$@" ;;
        *)
            log_error "[router] Unknown subcommand: ${subcommand}"
            log_info "  Usage: skeleton router <install|start|stop|down|status|health|check|oauth>"
            exit 1
            ;;
    esac
}

main "$@"
