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

if [[ -n "${BASH_SOURCE:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(pwd)"
fi
SOURCE_DIR="$SCRIPT_DIR"
SOURCE_IS_LOCAL=1
DOWNLOAD_TEMP_DIR=""
MODE="install"
INSTALL_DIR="$HOME/.local/bin/gbox-app"
BIN_DIR="$HOME/.local/bin"
SYMLINK_PATH="$BIN_DIR/gbox"
DEFAULT_ARCHIVE_URL="https://codeload.github.com/Gravtice/AgentBox/tar.gz/refs/heads/main"

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
    printf '%b\n' "\033[0;31m❌ Operation failed, rolling back...\033[0m" >&2
    if [ "$MODE" = "install" ]; then
        rm -rf "$INSTALL_DIR"
        rm -f "$SYMLINK_PATH"
    fi
}
trap cleanup_on_error ERR
trap '[[ -n "$DOWNLOAD_TEMP_DIR" && -d "$DOWNLOAD_TEMP_DIR" ]] && rm -rf "$DOWNLOAD_TEMP_DIR"' EXIT

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

print_usage() {
    cat <<'EOF'
Usage: install.sh [--uninstall]

Options:
  --uninstall   Run uninstallation (downloads package if needed)
  -h, --help    Show this help message
EOF
}

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --uninstall)
                MODE="uninstall"
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                echo_error "Unknown argument: $arg"
                print_usage
                exit 1
                ;;
        esac
    done
}

detect_source_mode() {
    if [ -x "$SOURCE_DIR/gbox" ] && [ -d "$SOURCE_DIR/lib" ] && [ -d "$SOURCE_DIR/scripts" ]; then
        SOURCE_IS_LOCAL=1
    else
        SOURCE_IS_LOCAL=0
    fi
}

download_agentbox_source() {
    echo_info "Downloading AgentBox package..."

    if [ -z "${AGENTBOX_ARCHIVE_URL:-}" ] && [ -z "${AGENTBOX_VERSION:-}" ]; then
        echo_info "Using default archive from main branch"
    fi

    if ! command -v tar >/dev/null 2>&1; then
        echo_error "tar is required to extract the installation package"
        exit 1
    fi

    DOWNLOAD_TEMP_DIR=$(mktemp -d)
    local archive_url
    local archive_path="$DOWNLOAD_TEMP_DIR/agentbox.tar.gz"

    if [ -n "${AGENTBOX_ARCHIVE_URL:-}" ]; then
        archive_url="$AGENTBOX_ARCHIVE_URL"
    elif [ -n "${AGENTBOX_VERSION:-}" ]; then
        archive_url="https://codeload.github.com/Gravtice/AgentBox/tar.gz/refs/tags/${AGENTBOX_VERSION}"
    else
        archive_url="$DEFAULT_ARCHIVE_URL"
    fi

    echo_info "Downloading AgentBox from $archive_url"

    if command -v curl >/dev/null 2>&1; then
        curl -fL "$archive_url" -o "$archive_path"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$archive_path" "$archive_url"
    else
        echo_error "curl or wget is required to download AgentBox"
        exit 1
    fi

    mkdir -p "$DOWNLOAD_TEMP_DIR/src"
    tar -xzf "$archive_path" -C "$DOWNLOAD_TEMP_DIR/src"

    local extracted_dir=""

    # Case 1: archive already extracts to the current directory (no top-level folder)
    if [ -x "$DOWNLOAD_TEMP_DIR/src/gbox" ]; then
        extracted_dir="$DOWNLOAD_TEMP_DIR/src"
    else
        # Case 2: archive has a single top-level folder
        extracted_dir=$(find "$DOWNLOAD_TEMP_DIR/src" -maxdepth 1 -mindepth 1 -type d | head -n 1)
    fi

    if [ -z "$extracted_dir" ] || [ ! -x "$extracted_dir/gbox" ]; then
        echo_error "Failed to locate extracted AgentBox directory (missing gbox entry point)"
        exit 1
    fi

    SOURCE_DIR="$extracted_dir"
    SOURCE_IS_LOCAL=1
    echo_info "Using downloaded AgentBox source at $SOURCE_DIR"
}

is_download_required() {
    if [ "$SOURCE_IS_LOCAL" -ne 1 ]; then
        return 0
    fi

    if [ -n "${AGENTBOX_ARCHIVE_URL:-}" ] || [ -n "${AGENTBOX_VERSION:-}" ]; then
        return 0
    fi

    return 1
}

prepare_source() {
    if ! is_download_required; then
        echo_info "Using existing AgentBox source at $SOURCE_DIR"
        return
    fi

    download_agentbox_source
}

check_dependencies() {
    echo_info "Checking dependencies..."

    local missing_deps=()

    if [ "$MODE" = "install" ]; then
        if ! command -v docker &> /dev/null; then
            missing_deps+=("docker")
        fi

        if ! command -v jq &> /dev/null; then
            missing_deps+=("jq")
        fi
    fi

    if is_download_required; then
        if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
            missing_deps+=("curl/wget")
        fi

        if ! command -v tar >/dev/null 2>&1; then
            missing_deps+=("tar")
        fi
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
                curl/wget)
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        echo "  - curl or wget: brew install curl"
                    else
                        echo "  - curl or wget: sudo apt-get install curl (Ubuntu/Debian) or sudo yum install curl (CentOS/RHEL)"
                    fi
                    ;;
                tar)
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        echo "  - tar: typically pre-installed on macOS; reinstall via Xcode Command Line Tools if missing"
                    else
                        echo "  - tar: sudo apt-get install tar (Ubuntu/Debian) or sudo yum install tar (CentOS/RHEL)"
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
    install -m 0755 "$SOURCE_DIR/gbox" "$INSTALL_DIR/gbox"

    # Copy directories (use cp -r for portability, rsync is not always available)
    cp -R "$SOURCE_DIR/lib" "$INSTALL_DIR/"
    cp -R "$SOURCE_DIR/scripts" "$INSTALL_DIR/"

    # Copy VERSION file if exists
    if [ -f "$SOURCE_DIR/VERSION" ]; then
        install -m 0644 "$SOURCE_DIR/VERSION" "$INSTALL_DIR/VERSION"
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
    if ! command -v zsh >/dev/null 2>&1 || [ ! -d "$HOME/.oh-my-zsh" ] || [ ! -d "$SOURCE_DIR/zsh-completion" ]; then
        echo_info "Zsh or oh-my-zsh not found, skipping completion installation"
        return 0
    fi

    local zsh_completion_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/gbox"
    local zshrc="$HOME/.zshrc"

    # Copy completion files
    mkdir -p "$zsh_completion_dir"

    if [ ! "$(ls -A "$SOURCE_DIR/zsh-completion" 2>/dev/null)" ]; then
        echo_warn "zsh-completion directory is empty"
        return 0
    fi

    cp -R "$SOURCE_DIR/zsh-completion/"* "$zsh_completion_dir/" 2>/dev/null || true
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

run_uninstall() {
    echo_info "Running AgentBox uninstallation..."

    if [ ! -x "$SOURCE_DIR/uninstall.sh" ]; then
        echo_error "uninstall.sh not found in $SOURCE_DIR"
        exit 1
    fi

    if [ -r /dev/tty ]; then
        bash "$SOURCE_DIR/uninstall.sh" </dev/tty
    else
        bash "$SOURCE_DIR/uninstall.sh"
    fi
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
    echo "  - Documentation: https://github.com/Gravtice/AgentBox#readme"
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

    parse_args "$@"
    detect_source_mode
    check_dependencies
    prepare_source

    if [ "$MODE" = "uninstall" ]; then
        run_uninstall
        return
    fi

    install_gbox
    configure_path
    install_completion
    verify_installation
    print_next_steps
}

main "$@"
