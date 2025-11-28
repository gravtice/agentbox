#!/usr/bin/env bash
# Copyright 2024-2025 Gravtice
# SPDX-License-Identifier: Apache-2.0
#
# AgentBox Uninstallation Script
# This script removes gbox from ~/.local/bin and cleans up configurations
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

INSTALL_DIR="$HOME/.local/bin/gbox-app"
BIN_DIR="$HOME/.local/bin"
SYMLINK_PATH="$BIN_DIR/gbox"
GBOX_CONFIG_DIR="$HOME/.gbox"

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

ask_confirmation() {
    local prompt="$1"
    local default="${2:-n}"
    local input_device="/dev/stdin"
    local response

    if [ ! -t 0 ] && [ -r /dev/tty ]; then
        input_device="/dev/tty"
    elif [ ! -t 0 ] && [ ! -r /dev/tty ]; then
        echo_warn "Non-interactive session detected, using default answer: ${default}"
        if [ "$default" = "y" ]; then
            return 0
        else
            return 1
        fi
    fi

    while true; do
        if [ "$default" = "y" ]; then
            if ! read -p "$prompt [Y/n]: " response <"$input_device"; then
                response="y"
            fi
            response=${response:-y}
        else
            if ! read -p "$prompt [y/N]: " response <"$input_device"; then
                response="n"
            fi
            response=${response:-n}
        fi

        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

stop_containers() {
    echo_info "Checking for running AgentBox containers..."

    if ! command -v docker >/dev/null 2>&1; then
        echo_warn "Docker not found, skipping container cleanup"
        return
    fi

    local containers
    containers=$(docker ps -a --filter "name=^gbox-" --format "{{.Names}}" 2>/dev/null || true)

    if [ -z "$containers" ]; then
        echo_info "No AgentBox containers found"
        return
    fi

    echo ""
    echo "Found AgentBox containers:"
    echo "$containers" | sed 's/^/  - /'
    echo ""

    if ask_confirmation "Stop and remove all AgentBox containers?"; then
        echo_info "Stopping containers..."
        # Use while-read loop to handle container names with spaces
        echo "$containers" | while IFS= read -r container; do
            [ -n "$container" ] && docker stop "$container" 2>/dev/null || true
        done

        echo_info "Removing containers..."
        echo "$containers" | while IFS= read -r container; do
            [ -n "$container" ] && docker rm "$container" 2>/dev/null || true
        done

        echo_success "All AgentBox containers removed"
    else
        echo_info "Skipping container cleanup"
    fi
}

remove_installation() {
    echo_info "Removing gbox installation..."

    # Remove symlink
    if [ -L "$SYMLINK_PATH" ] || [ -f "$SYMLINK_PATH" ]; then
        rm -f "$SYMLINK_PATH"
        echo_success "Removed symlink: $SYMLINK_PATH"
    fi

    # Remove installation directory
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        echo_success "Removed installation directory: $INSTALL_DIR"
    fi
}

remove_path_config() {
    echo_info "Removing PATH configuration..."

    # List of shell config files to check (same as installer)
    local shellrcs=(
        "$HOME/.zprofile"
        "$HOME/.zshrc"
        "$HOME/.bash_profile"
        "$HOME/.bashrc"
        "$HOME/.profile"
    )

    local configs_updated=0

    for config in "${shellrcs[@]}"; do
        # Skip if file doesn't exist
        [ -f "$config" ] || continue

        # Skip if no AgentBox marker found
        if ! grep -Fq "# Added by AgentBox installer" "$config" 2>/dev/null; then
            continue
        fi

        # Create backup
        local backup="$config.bak.$(date +%Y%m%d%H%M%S)"
        cp "$config" "$backup"
        echo_info "Created backup: $backup"

        # Remove PATH configuration using awk (more portable than sed -i)
        local tmpfile
        tmpfile=$(mktemp)
        awk '
            /# Added by AgentBox installer/ {
                skip = 1
                next
            }
            skip == 1 && /^export PATH=/ {
                skip = 0
                next
            }
            { print }
        ' "$config" > "$tmpfile"

        mv "$tmpfile" "$config"
        echo_success "Removed PATH configuration from $config"
        configs_updated=$((configs_updated + 1))
    done

    if [ "$configs_updated" -eq 0 ]; then
        echo_info "No PATH configuration found in shell configs"
    fi
}

remove_completion() {
    echo_info "Removing shell completion..."

    if ! command -v zsh >/dev/null 2>&1 || [ ! -d "$HOME/.oh-my-zsh" ]; then
        echo_info "Zsh or oh-my-zsh not found, skipping completion removal"
        return 0
    fi

    local zsh_completion_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/gbox"
    local zshrc="$HOME/.zshrc"

    # Remove completion files
    if [ -d "$zsh_completion_dir" ]; then
        rm -rf "$zsh_completion_dir"
        echo_success "Removed zsh completion from $zsh_completion_dir"
    else
        echo_info "Zsh completion directory not found"
    fi

    # Remove from .zshrc plugins array
    if [ ! -f "$zshrc" ]; then
        return 0
    fi

    # Check if gbox is in plugins (support both single-line and multi-line)
    # Single-line: plugins=(git gbox docker)
    # Multi-line: plugins=(\n  gbox\n  ...)
    if ! grep -E "^[[:space:]]*plugins=.*\bgbox\b" "$zshrc" >/dev/null 2>&1 && \
       ! grep -E "^[[:space:]]*gbox[[:space:]]*$" "$zshrc" >/dev/null 2>&1; then
        echo_info "gbox plugin not found in .zshrc"
        return 0
    fi

    # Backup .zshrc
    local backup="$zshrc.bak.$(date +%Y%m%d%H%M%S)"
    cp "$zshrc" "$backup"
    echo_info "Created backup: $backup"

    # Remove gbox from plugins array
    local tmpfile
    tmpfile=$(mktemp)

    # Detect if plugins array is single-line or multi-line
    if grep -E "^[[:space:]]*plugins=\([^)]*\)" "$zshrc" >/dev/null 2>&1; then
        # Single-line: plugins=(git gbox docker)
        awk '
            /^[[:space:]]*plugins=.*\)/ {
                # Normalize spacing
                gsub(/\(/, "( ")
                gsub(/\)/, " )")
                gsub(/[[:space:]]+/, " ")

                # Split into array and rebuild without gbox
                n = split($0, a, " ")
                printf "plugins=("
                first = 1
                for (i = 1; i <= n; i++) {
                    if (a[i] != "plugins=(" && a[i] != "(" && a[i] != ")" && a[i] != "gbox" && a[i] != "") {
                        if (!first) printf " "
                        printf "%s", a[i]
                        first = 0
                    }
                }
                printf ")\n"
                next
            }
            { print }
        ' "$zshrc" > "$tmpfile"
    else
        # Multi-line: remove the gbox line
        awk '
            /^[[:space:]]*gbox[[:space:]]*$/ {
                next
            }
            { print }
        ' "$zshrc" > "$tmpfile"
    fi

    mv "$tmpfile" "$zshrc"
    echo_success "Removed gbox from .zshrc plugins"
}

remove_config_data() {
    if [ ! -d "$GBOX_CONFIG_DIR" ]; then
        echo_info "No configuration data found at $GBOX_CONFIG_DIR"
        return
    fi

    echo ""
    echo_warn "Configuration directory found: $GBOX_CONFIG_DIR"
    echo "This directory contains:"
    echo "  - OAuth login sessions"
    echo "  - MCP server configurations"
    echo "  - Dependency caches"
    echo "  - Container logs"
    echo ""

    if ask_confirmation "Do you want to remove all configuration data?"; then
        rm -rf "$GBOX_CONFIG_DIR"
        echo_success "Removed configuration directory: $GBOX_CONFIG_DIR"
    else
        echo_info "Configuration data preserved at $GBOX_CONFIG_DIR"
        echo_info "You can manually remove it later with: rm -rf $GBOX_CONFIG_DIR"
    fi
}

verify_uninstallation() {
    echo_info "Verifying uninstallation..."

    local issues=()

    if [ -L "$SYMLINK_PATH" ] || [ -f "$SYMLINK_PATH" ]; then
        issues+=("Symlink still exists: $SYMLINK_PATH")
    fi

    if [ -d "$INSTALL_DIR" ]; then
        issues+=("Installation directory still exists: $INSTALL_DIR")
    fi

    if [ ${#issues[@]} -ne 0 ]; then
        echo_warn "Uninstallation incomplete:"
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
        return 1
    fi

    echo_success "Uninstallation verified successfully"
    return 0
}

print_final_message() {
    echo ""
    echo_success "AgentBox has been uninstalled!"
    echo ""
    echo "What was removed:"
    echo "  - gbox command from $SYMLINK_PATH"
    echo "  - Installation directory at $INSTALL_DIR"
    echo "  - PATH configuration from shell configs"
    echo ""

    if [ -d "$GBOX_CONFIG_DIR" ]; then
        echo "What was preserved:"
        echo "  - Configuration data at $GBOX_CONFIG_DIR"
        echo "    (You can remove it manually if needed)"
        echo ""
    fi

    echo "Next steps:"
    echo "  1. Reload your shell configuration:"
    if [ -f "$HOME/.zshrc" ]; then
        echo "     source ~/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        echo "     source ~/.bashrc"
    fi
    echo ""
    echo "  2. If you want to reinstall later:"
    echo "     cd /path/to/agentbox && ./install.sh"
    echo ""
}

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║            AgentBox Uninstallation Script               ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    if ! ask_confirmation "Are you sure you want to uninstall AgentBox?" "n"; then
        echo_info "Uninstallation cancelled"
        exit 0
    fi

    echo ""

    stop_containers
    remove_installation
    remove_path_config
    remove_completion
    remove_config_data
    verify_uninstallation
    print_final_message
}

main "$@"
