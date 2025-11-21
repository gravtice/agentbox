#!/usr/bin/env bash
# Copyright 2024-2025 Gravtice
# SPDX-License-Identifier: Apache-2.0
#
# AgentBox Installation Script
# This script installs gbox to ~/.local/bin and configures PATH
# Requires: bash 4.0+

set -euo pipefail

# Validate environment
: "${HOME:?HOME environment variable not set}"
: "${BASH_VERSION:?This script requires bash}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/bin/gbox-app"
BIN_DIR="$HOME/.local/bin"
SYMLINK_PATH="$BIN_DIR/gbox"

# Validate installation directory is under HOME
case "$INSTALL_DIR" in
    "$HOME"/*)
        ;; # OK
    *)
        printf '%b\n' "\033[0;31m❌ Error: Installation directory must be under \$HOME\033[0m" >&2
        exit 1
        ;;
esac

# Setup error rollback trap
cleanup_on_error() {
    printf '%b\n' "\033[0;31m❌ Installation failed, rolling back...\033[0m" >&2
    rm -rf "$INSTALL_DIR"
    rm -f "$SYMLINK_PATH"
}
trap cleanup_on_error ERR

echo_info() {
    printf '%b\n' "${BLUE}ℹ️  $1${NC}"
}

echo_success() {
    printf '%b\n' "${GREEN}✅ $1${NC}"
}

echo_error() {
    printf '%b\n' "${RED}❌ $1${NC}" >&2
}

echo_warn() {
    printf '%b\n' "${YELLOW}⚠️  $1${NC}"
}

check_dependencies() {
    echo_info "Checking dependencies..."

    local missing_deps=()

    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        echo "Please install missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            case $dep in
                docker)
                    echo "  - Docker: https://docs.docker.com/get-docker/"
                    ;;
                jq)
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        echo "  - jq: brew install jq"
                    else
                        echo "  - jq: sudo apt-get install jq (Ubuntu/Debian) or sudo yum install jq (CentOS/RHEL)"
                    fi
                    ;;
            esac
        done
        exit 1
    fi

    echo_success "All dependencies are installed"
}

install_gbox() {
    echo_info "Installing gbox to $INSTALL_DIR..."

    # Atomically rebuild installation directory (remove old files, avoid stale leftovers)
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR" "$BIN_DIR"

    # Copy gbox script with explicit permissions
    install -m 0755 "$SCRIPT_DIR/gbox" "$INSTALL_DIR/gbox"

    # Copy directories (use cp -r for portability, rsync is not always available)
    cp -R "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
    cp -R "$SCRIPT_DIR/scripts" "$INSTALL_DIR/"

    # Copy VERSION file if exists
    if [ -f "$SCRIPT_DIR/VERSION" ]; then
        install -m 0644 "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/VERSION"
    fi

    # Create or update symlink (use -n to avoid following existing symlinks)
    if [ -e "$SYMLINK_PATH" ] || [ -L "$SYMLINK_PATH" ]; then
        echo_warn "Existing gbox found at $SYMLINK_PATH, will be replaced"
    fi

    ln -sfn "$INSTALL_DIR/gbox" "$SYMLINK_PATH"

    echo_success "gbox installed successfully"
}

configure_path() {
    echo_info "Configuring PATH..."

    local path_comment="# Added by AgentBox installer"
    local path_export="export PATH=\"$BIN_DIR:\$PATH\""

    # Check if already configured in any shell config
    local all_configs=(
        "$HOME/.zprofile"
        "$HOME/.zshrc"
        "$HOME/.bash_profile"
        "$HOME/.bashrc"
        "$HOME/.profile"
    )

    for config in "${all_configs[@]}"; do
        if [ -f "$config" ] && grep -Fqs "$BIN_DIR" "$config" 2>/dev/null; then
            echo_info "PATH already configured in $config"
            return 0
        fi
    done

    # Choose the appropriate config file (only one per shell type)
    local target_config=""

    # Priority 1: Zsh configs (prefer .zprofile for login shells)
    if [ -f "$HOME/.zprofile" ]; then
        target_config="$HOME/.zprofile"
    elif [ -f "$HOME/.zshrc" ]; then
        target_config="$HOME/.zshrc"
    # Priority 2: Bash configs (prefer .bash_profile for login shells)
    elif [ -f "$HOME/.bash_profile" ]; then
        target_config="$HOME/.bash_profile"
    elif [ -f "$HOME/.bashrc" ]; then
        target_config="$HOME/.bashrc"
    # Priority 3: Generic profile
    elif [ -f "$HOME/.profile" ]; then
        target_config="$HOME/.profile"
    fi

    if [ -z "$target_config" ]; then
        echo_warn "No shell configuration file found"
        echo_warn "Checked: ${all_configs[*]}"
        echo_warn "Please manually add $BIN_DIR to your PATH"
        return 1
    fi

    # Backup before modification
    local backup="$target_config.bak.$(date +%Y%m%d%H%M%S)"
    cp "$target_config" "$backup"
    echo_info "Created backup: $backup"

    # Append PATH configuration
    {
        printf '\n'
        printf '%s\n' "$path_comment"
        printf '%s\n' "$path_export"
    } >> "$target_config"

    echo_success "PATH configured in $target_config"
}

install_completion() {
    echo_info "Installing shell completion..."

    # Install zsh completion if zsh is available and oh-my-zsh is installed
    if ! command -v zsh >/dev/null 2>&1 || [ ! -d "$HOME/.oh-my-zsh" ] || [ ! -d "$SCRIPT_DIR/zsh-completion" ]; then
        echo_info "Zsh or oh-my-zsh not found, skipping completion installation"
        return 0
    fi

    local zsh_completion_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/gbox"
    local zshrc="$HOME/.zshrc"

    # Copy completion files
    mkdir -p "$zsh_completion_dir"

    if [ ! "$(ls -A "$SCRIPT_DIR/zsh-completion" 2>/dev/null)" ]; then
        echo_warn "zsh-completion directory is empty"
        return 0
    fi

    cp -R "$SCRIPT_DIR/zsh-completion/"* "$zsh_completion_dir/" 2>/dev/null || true
    echo_success "Zsh completion files installed to $zsh_completion_dir"

    # Enable plugin in .zshrc
    if [ ! -f "$zshrc" ]; then
        echo_warn ".zshrc not found, please manually add 'gbox' to plugins array"
        return 0
    fi

    # Check if gbox is already in plugins (support both single-line and multi-line)
    # Single-line: plugins=(git gbox docker)
    # Multi-line: plugins=(\n  gbox\n  ...)
    if grep -E "^[[:space:]]*plugins=.*\bgbox\b" "$zshrc" >/dev/null 2>&1 || \
       grep -E "^[[:space:]]*gbox[[:space:]]*$" "$zshrc" >/dev/null 2>&1; then
        echo_info "gbox plugin already enabled in .zshrc"
        return 0
    fi

    # Check if plugins line exists
    if ! grep -E "^[[:space:]]*plugins=" "$zshrc" >/dev/null 2>&1; then
        echo_warn "No plugins line found in .zshrc"
        echo_warn "Please manually add 'gbox' to your plugins array"
        return 0
    fi

    # Backup .zshrc
    local backup="$zshrc.bak.$(date +%Y%m%d%H%M%S)"
    cp "$zshrc" "$backup"
    echo_info "Created backup: $backup"

    # Add gbox to plugins array
    local tmpfile
    tmpfile=$(mktemp)

    # Detect if plugins array is single-line or multi-line
    if grep -E "^[[:space:]]*plugins=\([^)]*\)" "$zshrc" >/dev/null 2>&1; then
        # Single-line: plugins=(git docker)
        awk '
            /^[[:space:]]*plugins=.*\)/ {
                sub(/\)/, " gbox)", $0)
                print
                next
            }
            { print }
        ' "$zshrc" > "$tmpfile"
    else
        # Multi-line: plugins=(\n  git\n  docker\n)
        # Add gbox after plugins=( line
        awk '
            /^[[:space:]]*plugins=\(/ {
                print
                print "  gbox"
                next
            }
            { print }
        ' "$zshrc" > "$tmpfile"
    fi

    mv "$tmpfile" "$zshrc"
    echo_success "Enabled gbox plugin in .zshrc"
    echo_info "Restart your shell or run: source ~/.zshrc"
}

verify_installation() {
    echo_info "Verifying installation..."

    if [ ! -L "$SYMLINK_PATH" ]; then
        echo_error "Installation verification failed: symlink not created"
        exit 1
    fi

    if [ ! -x "$INSTALL_DIR/gbox" ]; then
        echo_error "Installation verification failed: gbox script not executable"
        exit 1
    fi

    echo_success "Installation verified successfully"
}

print_next_steps() {
    echo ""
    echo_success "AgentBox installation completed!"
    echo ""
    echo "Next steps:"
    echo "  1. Reload your shell configuration:"
    if [ -f "$HOME/.zshrc" ]; then
        echo "     source ~/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        echo "     source ~/.bashrc"
    fi
    echo ""
    echo "  2. Verify installation:"
    echo "     gbox --version"
    echo ""
    echo "  3. Get started:"
    echo "     gbox --help"
    echo ""
    echo "  4. Pull the Docker image (recommended):"
    echo "     gbox pull"
    echo ""
    echo "     Note: To build locally, use './gbox build' in the source directory"
    echo ""
    echo "  5. Start your first agent:"
    echo "     gbox claude        # Start Claude Code"
    echo ""
    echo "For more information, see:"
    echo "  - Quick Start: https://github.com/gravtice/agentbox#quick-start"
    echo "  - Documentation: $SCRIPT_DIR/README.md"
    echo ""
}

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║              AgentBox Installation Script               ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    check_dependencies
    install_gbox
    configure_path
    install_completion
    verify_installation
    print_next_steps
}

main "$@"
