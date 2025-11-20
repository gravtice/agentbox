#!/bin/bash
# Copyright 2024-2025 Gravtice
# SPDX-License-Identifier: Apache-2.0
#
# lib/common.sh - Common utilities and constants
# This module contains global constants, color definitions, environment checks and utility functions

# ============================================
# Global constants definition
# ============================================

# Read version from VERSION file
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
    VERSION=$(cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')
else
    # Fallback to default version
    VERSION="1.0.0"
    echo "Warning: VERSION file not found, using default version $VERSION" >&2
fi

# Image configuration
IMAGE_NAME="gravtice/agentbox"
IMAGE_TAG="$VERSION"
IMAGE_FULL="${IMAGE_NAME}:${IMAGE_TAG}"

# Container configuration
CONTAINER_PREFIX="gbox"
NETWORK_NAME="gbox-network"

# Directory configuration
GBOX_CONFIG_DIR="$HOME/.gbox"                     # gbox config root directory
GBOX_CLAUDE_DIR="$GBOX_CONFIG_DIR/claude"         # Claude config directory
GBOX_CODEX_DIR="$GBOX_CONFIG_DIR/codex"           # Codex config directory
GBOX_GEMINI_DIR="$GBOX_CONFIG_DIR/gemini"         # Gemini config directory
GBOX_HAPPY_DIR="$GBOX_CONFIG_DIR/happy"           # Happy config directory
STATE_FILE="$GBOX_CONFIG_DIR/containers.json"     # Container state file
LOGS_DIR="$GBOX_CONFIG_DIR/logs"                  # Logs directory
CACHE_DIR="$GBOX_CONFIG_DIR/cache"                # Cache directory

# Resource limit configuration (default values, can be overridden by environment variables or command-line arguments)
DEFAULT_MEMORY_LIMIT="4g"
DEFAULT_CPU_LIMIT="2"

# Actual resource limits (priority: command-line > environment variable > default)
MEMORY_LIMIT="${GBOX_MEMORY:-${DEFAULT_MEMORY_LIMIT}}"
CPU_LIMIT="${GBOX_CPU:-${DEFAULT_CPU_LIMIT}}"
CONTAINER_PORTS="${GBOX_PORTS:-}"                 # Port mapping configuration
CONTAINER_KEEP="${GBOX_KEEP:-false}"              # Whether to keep container after exit
CONTAINER_NAME="${GBOX_NAME:-}"                   # Custom container name
CONTAINER_REF_DIRS="${GBOX_REF_DIRS:-}"           # Read-only reference directories list
AGENT_PROXY="${GBOX_PROXY:-}"                     # Proxy address (passed to Agent)
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"        # Anthropic API Key
DEBUG="${DEBUG:-}"                                # Debug mode (e.g., happy:*)
REF_DIR_MOUNT_ARGS=()                             # Docker -v arguments (array)
REF_DIR_SOURCE_DIRS=()                            # Reference directories list for display

# List of supported AI Agents
SUPPORTED_AGENTS=("claude" "codex" "gemini")

# ============================================
# Color output
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# ============================================
# System detection
# ============================================

# Check if flock is supported (available on Linux, not by default on macOS)
HAS_FLOCK=0
if command -v flock &> /dev/null; then
    HAS_FLOCK=1
fi

# ============================================
# Environment check functions
# ============================================

function check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker is not installed or not running${NC}"
        exit 1
    fi
}

function check_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is not installed, please install it first: brew install jq${NC}"
        exit 1
    fi
}

# ============================================
# Environment variable loading
# ============================================

# Load .env file
# Priority: command-line parameters > .env.local > .env > defaults
function load_env_files() {
    local env_file="$SCRIPT_DIR/.env"
    local env_local_file="$SCRIPT_DIR/.env.local"

    # Load .env file
    if [[ -f "$env_file" ]]; then
        if [[ "${GBOX_DEBUG:-0}" == "1" ]]; then
            echo -e "${BLUE}Loading config file: $env_file${NC}" >&2
        fi

        # Read and export variables line by line (skip comments and blank lines)
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip comments and blank lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # Parse variable name and value
            if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
                local var_name="${BASH_REMATCH[1]}"
                local var_value="${BASH_REMATCH[2]}"

                # Remove quotes around values (if any)
                var_value="${var_value#\"}"
                var_value="${var_value%\"}"
                var_value="${var_value#\'}"
                var_value="${var_value%\'}"

                # Only export if variable is not set (command-line parameters take precedence)
                if [[ -z "${!var_name}" ]]; then
                    export "$var_name=$var_value"
                    if [[ "${GBOX_DEBUG:-0}" == "1" ]]; then
                        echo -e "${BLUE}  Export: $var_name=$var_value${NC}" >&2
                    fi
                fi
            fi
        done < "$env_file"
    fi

    # Load .env.local file (higher priority)
    if [[ -f "$env_local_file" ]]; then
        if [[ "${GBOX_DEBUG:-0}" == "1" ]]; then
            echo -e "${BLUE}Loading config file: $env_local_file${NC}" >&2
        fi

        # Read and export variables line by line (skip comments and blank lines)
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip comments and blank lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # Parse variable name and value
            if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
                local var_name="${BASH_REMATCH[1]}"
                local var_value="${BASH_REMATCH[2]}"

                # Remove quotes around values (if any)
                var_value="${var_value#\"}"
                var_value="${var_value%\"}"
                var_value="${var_value#\'}"
                var_value="${var_value%\'}"

                # .env.local overrides .env settings, but not command-line parameters
                # Check if variable already exists in environment to determine if it came from command-line
                if [[ -z "${!var_name}" ]]; then
                    export "$var_name=$var_value"
                    if [[ "${GBOX_DEBUG:-0}" == "1" ]]; then
                        echo -e "${BLUE}  Export: $var_name=$var_value${NC}" >&2
                    fi
                fi
            fi
        done < "$env_local_file"
    fi
}

# ============================================
# Utility functions
# ============================================

# Validate container name against Docker naming conventions
function validate_container_name() {
    local name="$1"
    # Only allow: letters, numbers, underscores, dots, hyphens
    # Cannot start with a dot or hyphen
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        echo -e "${RED}Error: Container name '$name' does not conform to naming conventions${NC}"
        echo -e "${YELLOW}Container names can only contain: letters, numbers, underscores, dots, hyphens${NC}"
        echo -e "${YELLOW}and must start with a letter or number${NC}"
        return 1
    fi
    return 0
}

# Validate if agent is supported
function is_valid_agent() {
    local agent="$1"
    for supported in "${SUPPORTED_AGENTS[@]}"; do
        if [[ "$agent" == "$supported" ]]; then
            return 0
        fi
    done
    return 1
}

# Find available port
function find_available_port() {
    local start_port=8001
    local end_port=8010

    for port in $(seq $start_port $end_port); do
        if ! lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo $port
            return 0
        fi
    done

    echo -e "${RED}Error: All ports $start_port-$end_port are in use${NC}" >&2
    return 1
}

# Convert email to suffix (email-safe format)
# Example: agent@gravtice.com -> agent-at-gravtice-com
function email_to_suffix() {
    local email="$1"
    echo "$email" | tr '[:upper:]' '[:lower:]' | sed 's/@/-at-/g' | sed 's/\./-/g'
}

# Parse and validate read-only reference directories list, and populate REF_DIR_MOUNT_ARGS/REF_DIR_SOURCE_DIRS arrays
function parse_ref_dirs() {
    local ref_dirs_config="$1"
    local work_dir="$2"       # Current working directory, used to avoid conflicts
    REF_DIR_MOUNT_ARGS=()
    REF_DIR_SOURCE_DIRS=()

    # If empty, do not mount any reference directories
    if [[ -z "$ref_dirs_config" ]]; then
        return 0
    fi

    # Replace semicolons with newlines, save to temp file to avoid subshell issues
    local temp_file=$(mktemp)
    echo "$ref_dirs_config" | tr ';' '\n' > "$temp_file"

    # Read and process line by line
    while IFS= read -r dir_item; do
        dir_item=$(echo "$dir_item" | xargs)  # Remove whitespace
        [[ -z "$dir_item" ]] && continue

        # Convert to absolute path
        local abs_dir
        if [[ "$dir_item" =~ ^/ ]]; then
            # Already an absolute path
            abs_dir="$dir_item"
        else
            # Relative path, convert to absolute path
            abs_dir=$(cd "$dir_item" 2>/dev/null && pwd)
            if [[ $? -ne 0 ]]; then
                echo -e "${YELLOW}Warning: Directory does not exist or cannot be accessed '$dir_item', skipping${NC}" >&2
                continue
            fi
        fi

        # Verify directory exists
        if [[ ! -d "$abs_dir" ]]; then
            echo -e "${YELLOW}Warning: Directory does not exist '$abs_dir', skipping${NC}" >&2
            continue
        fi

        # Verify no conflict with working directory
        if [[ "$abs_dir" == "$work_dir" ]]; then
            echo -e "${YELLOW}Warning: Reference directory same as working directory '$abs_dir', skipping (working directory is automatically mounted)${NC}" >&2
            continue
        fi

        # Verify not a subdirectory or parent directory of working directory
        if [[ "$abs_dir" == "$work_dir"/* ]] || [[ "$work_dir" == "$abs_dir"/* ]]; then
            echo -e "${YELLOW}Warning: Reference directory has containment relationship with working directory '$abs_dir', skipping${NC}" >&2
            continue
        fi

        # Add to results (mount in read-only mode to same path)
        REF_DIR_MOUNT_ARGS+=(-v "$abs_dir:$abs_dir:ro")
        REF_DIR_SOURCE_DIRS+=("$abs_dir")
    done < "$temp_file"

    # Clean up temp file
    rm -f "$temp_file"
}

# ============================================
# Help documentation
# ============================================

function print_usage() {
    local show_full="${1:-}"

    cat <<EOF
gbox - Gravtice AgentBox v${VERSION}

Quick Start:
    cd ~/myproject
    gbox claude                                 # Run Claude Code (local mode)
    gbox happy claude                           # Run Claude Code (remote collaboration mode)

Common Commands:
    gbox <agent> [-- <args>]                    Start AI Agent (local mode)
    gbox happy <agent> [-- <args>]              Start AI Agent (remote collaboration mode)
    gbox list                                   List running containers
    gbox stop <container-name>                  Stop and delete container
    gbox stop-all                               Stop all containers
    gbox logs <container-name>                  View container logs
    gbox shell <container-name>                 Login to container shell

Advanced Features:
    gbox oauth <cmd>                            OAuth account management
    gbox keepalive <cmd>                        Container maintenance management
    gbox build [--no-cache]                     Build container image
    gbox pull [tag]                             Pull pre-built image
    gbox status                                 Show detailed status of all containers
    gbox exec <container-name> <command>        Execute command in container
    gbox clean                                  Clean up all stopped containers

Supported AI Agents:
    claude          Claude Code
    codex           Codex
    gemini          Google Gemini

Usage Examples:
    gbox claude -- --model=sonnet               # Pass arguments to claude
    gbox happy claude -- --resume <id>          # Resume remote session
    gbox gemini                                  # Run Gemini CLI
    gbox oauth claude help                      # OAuth help

More Help:
    gbox help --full                            # Show complete help documentation
    gbox oauth help                             # OAuth detailed help
    gbox keepalive help                         # Container maintenance help
EOF

    # Show detailed help
    if [[ "$show_full" == "--full" ]]; then
        cat <<'FULLEOF'

═══════════════════════════════════════════════════════════════
                    Complete Help Documentation
═══════════════════════════════════════════════════════════════

Run Modes Explained:
    only-local      Local mode - Run AI Agent directly in container
    local-remote    Remote collaboration mode - Support remote client collaboration (based on happy-coder)

Container Management Explained:
    # Container is preserved by default after agent exits, can be reused directly
    # For automatic cleanup: GBOX_AUTO_CLEANUP=1 gbox claude

    gbox list                                   # View running containers
    gbox status                                 # View status of all containers
    gbox stop gbox-claude-myproject            # Stop and delete container
    gbox stop-all                               # Stop all containers
    gbox shell gbox-claude-myproject           # Login to container shell
    gbox exec gbox-claude-myproject "ls -la"   # Execute command in container
    gbox logs gbox-claude-myproject            # View container logs

OAuth Account Management:
    gbox oauth claude switch --limit 2025120111                         # Switch when account reaches limit (specify time)
    gbox oauth claude switch --limit-str "resets Nov 9, 5pm"           # Switch when account reaches limit (auto-parse)
    gbox oauth claude switch                                            # Manually switch account
    gbox oauth claude help                                              # Show OAuth help

    # Support multi-account management, auto-switch to available account when limit is reached
    # Account config stored in ~/.gbox/claude, shared across all containers

Container Maintenance Management:
    gbox keepalive list                         # List all maintenance containers
    gbox keepalive stop <account-suffix>        # Stop specified maintenance container
    gbox keepalive stop-all                     # Stop all maintenance containers
    gbox keepalive logs <account-suffix>        # View maintenance container logs
    gbox keepalive help                         # Show maintenance help

    # Maintenance containers keep inactive accounts logged in
    # Auto-start when switching account, auto-stop when switching back
    # Low resource usage (256MB memory, 0.25 CPU cores)

Image Building and Distribution:
    gbox build                                  # Build image (includes Playwright)
    gbox build --no-cache                       # Force rebuild without cache (for updating tools)
    gbox pull [tag]                             # Pull pre-built image
    gbox push [tag]                             # Push image to Docker Hub

    # Image repository: docker.io/gravtice/agentbox
    # Push requires login first: docker login
    # Use --no-cache when Claude Code/Codex/Gemini versions upgrade

Container Resource Configuration:
    # Method 1: Using .env file (recommended)
    # Copy .env.example to .env or .env.local for configuration
    # Priority: command-line parameters > .env.local > .env > defaults
    cp .env.example .env
    # Edit .env file to set common configuration
    # Edit .env.local file to set local-specific configuration (not committed to git)

    # Method 2: Set via environment variables
    GBOX_MEMORY=8g                              Container memory limit (default: 4g)
    GBOX_CPU=4                                  Container CPU cores (default: 2)
    GBOX_PORTS="8000:8000;7000:7001"            Port mapping configuration (default: no ports mapped)
    GBOX_REF_DIRS="/path/to/ref1;/path/to/ref2" Read-only reference directories (default: none)
    GBOX_PROXY="http://127.0.0.1:7890"          Agent network proxy (default: none)
    ANTHROPIC_API_KEY=sk-xxx                    Anthropic API Key (default: none)
    DEBUG=happy:*                               Debug mode (default: none)
    GBOX_KEEP=true                              Keep container after exit (default: false)
    GBOX_NAME=my-container                      Custom container name (default: auto-generated)

    # Port mapping format:
    # - Format: "host_port:container_port" (multiple ports separated by semicolon)
    # - Examples:
    #   GBOX_PORTS="8000:8000"              # Host 8000 -> Container 8000
    #   GBOX_PORTS="8080:8000"              # Host 8080 -> Container 8000
    #   GBOX_PORTS="8000:8000;7000:7001"    # Multiple ports: 8000->8000, 7000->7001
    # - All ports mapped to 127.0.0.1 (local access only)
    # - No ports mapped by default, explicitly configure via GBOX_PORTS when needed

    # Read-only reference directories format:
    # - Format: "directory path" (multiple directories separated by semicolon)
    # - Examples:
    #   GBOX_REF_DIRS="/Users/me/project1"                        # Single reference directory
    #   GBOX_REF_DIRS="/Users/me/project1;/Users/me/project2"    # Multiple reference directories
    # - All directories mounted read-only to same path in container
    # - Provide code references from other projects to AI Agent
    # - Auto-validate directory existence and path conflicts

    # Set via command-line parameters (higher priority than environment variables)
    gbox claude --memory 8g --cpu 4 -- --model sonnet
    gbox happy claude -m 16g -c 8 -- --resume <session-id>
    gbox claude --ref-dirs "/path/to/ref1;/path/to/ref2"
    gbox claude --api-key sk-xxx --debug

    # Available parameters:
    --memory, -m <value>       Memory limit (e.g., 4g, 8g, 16g)
    --cpu, -c <value>          CPU cores (e.g., 2, 4, 8)
    --ports <value>            Port mapping (e.g., "8000:8000;7000:7001")
    --ref-dirs <value>         Read-only reference directories (e.g., "/path/to/ref1;/path/to/ref2")
    --proxy <value>            Agent network proxy (e.g., "http://127.0.0.1:7890")
    --api-key <value>          Anthropic API Key (e.g., "sk-xxx")
    --debug                    Enable debug mode (happy:*)
    --keep                     Keep container after exit
    --name <value>             Custom container name

Other Environment Variables:
    GBOX_AUTO_CLEANUP=1       Auto-cleanup container after exit (default: keep container)
    GBOX_DEBUG=1              Enable debug mode
    GBOX_READY_ATTEMPTS=30    Number of container readiness checks
    GBOX_READY_DELAY=0.2      Check interval (seconds)

Features:
    ✅ Two run modes: Local mode (only-local) and remote collaboration mode (local-remote)
    ✅ Multiple AI Agents: Support claude, codex, gemini, etc.
    ✅ Auto management: Auto manage containers based on current directory and run mode
    ✅ Argument forwarding: Support -- separator to pass arguments
    ✅ Config persistence: Config stored in ~/.gbox/{claude,happy}
    ✅ Container isolation: Independent containers per project+mode, no interference
    ✅ Resource limits: Auto limit memory and CPU, enable dependency caching
FULLEOF
    fi
}
