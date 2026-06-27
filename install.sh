#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# install.sh — skeleton-parallel installer
# ─────────────────────────────────────────────────────────────────────────────
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/okfriansyah-moh/skeleton-parallel/main/install.sh | bash
#
# Installs the `skeleton` CLI to ~/.local/bin by cloning the repo to
# ~/.skeleton-parallel and symlinking bin/skeleton.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_URL="https://github.com/okfriansyah-moh/skeleton-parallel"
INSTALL_DIR="${SKELETON_INSTALL_DIR:-$HOME/.skeleton-parallel}"
BIN_DIR="${SKELETON_BIN_DIR:-$HOME/.local/bin}"
BINARY="${BIN_DIR}/skeleton"

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$1"; }
log_ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$1"; }
log_warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }
die()       { log_error "$1"; exit 1; }

# ── Check dependencies ────────────────────────────────────────────────────────
echo ""
printf "${BOLD}skeleton-parallel installer${NC}\n"
echo "────────────────────────────────────────"
echo ""

command -v git  &>/dev/null || die "git is required. Install: brew install git"
command -v bash &>/dev/null || die "bash is required."

# Warn if bash < 4
BASH_MAJOR="${BASH_VERSINFO[0]:-3}"
if (( BASH_MAJOR < 4 )); then
    log_warn "bash 4+ recommended. Found bash ${BASH_VERSION}."
    log_warn "Install via: brew install bash"
fi

# ── Install or update ─────────────────────────────────────────────────────────
if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log_info "Updating existing installation at ${INSTALL_DIR}..."
    git -C "${INSTALL_DIR}" pull --ff-only --quiet
    log_ok "Updated to $(git -C "${INSTALL_DIR}" describe --tags --always 2>/dev/null || echo 'latest')"
else
    log_info "Installing to ${INSTALL_DIR}..."
    git clone --depth=1 "${REPO_URL}" "${INSTALL_DIR}" --quiet
    log_ok "Cloned skeleton-parallel"
fi

# ── Create bin dir and symlink ────────────────────────────────────────────────
mkdir -p "${BIN_DIR}"
chmod +x "${INSTALL_DIR}/bin/skeleton"

if [[ -L "${BINARY}" ]] || [[ -f "${BINARY}" ]]; then
    rm -f "${BINARY}"
fi

ln -s "${INSTALL_DIR}/bin/skeleton" "${BINARY}"
log_ok "Linked: ${BINARY} → ${INSTALL_DIR}/bin/skeleton"

# ── Check PATH ────────────────────────────────────────────────────────────────
echo ""
if command -v skeleton &>/dev/null; then
    log_ok "skeleton is on your PATH"
    skeleton version
else
    log_warn "${BIN_DIR} is not on your PATH."
    echo ""
    echo "  Add it now:"

    SHELL_NAME="$(basename "${SHELL:-bash}")"
    case "${SHELL_NAME}" in
        zsh)
            echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
            ;;
        fish)
            echo "    fish_add_path \$HOME/.local/bin"
            ;;
        *)
            echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
            ;;
    esac
    echo ""
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
printf "${BOLD}Installation complete.${NC}\n"
echo ""
echo "  Next steps:"
echo "    skeleton init go --name=my-service   # new project"
echo "    skeleton integrate                    # existing repo"
echo "    skeleton doctor                       # verify setup"
echo "    skeleton --help                       # full reference"
echo ""
