#!/bin/bash
# Copyright 2024-2025 Gravtice
# SPDX-License-Identifier: Apache-2.0
#
# lib/state.sh - State management
# This module is responsible for config directory initialization, state file management, and container mappings

# ============================================
# Git config initialization
# ============================================

# Initialize Git config file
function init_gitconfig() {
    local gitconfig_file="$GBOX_CONFIG_DIR/.gitconfig"

    # If file already exists, don't overwrite
    if [[ -f "$gitconfig_file" ]]; then
        return 0
    fi

    # Try to copy user information from host machine
    local git_name=""
    local git_email=""

    if [[ -f "$HOME/.gitconfig" ]]; then
        git_name=$(git config --file "$HOME/.gitconfig" --get user.name 2>/dev/null || echo "")
        git_email=$(git config --file "$HOME/.gitconfig" --get user.email 2>/dev/null || echo "")
    fi

    # Create default config file
    cat > "$gitconfig_file" <<EOF
# gbox shared Git config
# This file will be mounted to all gbox containers as global config
# Location: $gitconfig_file

[core]
	autocrlf = input
	eol = lf
	safecrlf = warn

[user]
	# Please modify the following information as needed
	name = ${git_name:-Your Name}
	email = ${git_email:-your.email@example.com}

[pull]
	rebase = false

# You can add more config here, for example:
# [alias]
#     st = status
#     co = checkout
#     br = branch
#     ci = commit
EOF

    # If user info was successfully copied from host, notify the user
    if [[ -n "$git_name" && -n "$git_email" ]]; then
        echo -e "${GREEN}✓ Git config file created and user info copied from host${NC}"
        echo -e "${BLUE}  Config file: $gitconfig_file${NC}"
    else
        echo -e "${YELLOW}⚠ Git config file created, but no host user info found${NC}"
        echo -e "${YELLOW}  Please edit config file: $gitconfig_file${NC}"
    fi
}

# ============================================
# State directory initialization
# ============================================

# Initialize state directories and config files
function init_state() {
    mkdir -p "$GBOX_CONFIG_DIR"
    mkdir -p "$GBOX_CLAUDE_DIR"
    mkdir -p "$GBOX_CODEX_DIR"
    mkdir -p "$GBOX_HAPPY_DIR"
    mkdir -p "$LOGS_DIR"
    mkdir -p "$CACHE_DIR/pip"
    mkdir -p "$CACHE_DIR/npm"
    mkdir -p "$CACHE_DIR/uv"

    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{}' > "$STATE_FILE"
    fi

    # Initialize shared .gitconfig
    init_gitconfig
}

# ============================================
# Safe state file updates
# ============================================

# Safely update state file (cross-platform compatible)
# Parameters: jq_filter jq_args...
function safe_jq_update() {
    local jq_expr="$1"
    shift
    local jq_args=("$@")

    if (( HAS_FLOCK == 1 )); then
        # Linux: Use flock to ensure concurrent safety
        (
            flock -x 200
            jq "${jq_args[@]}" "$jq_expr" "$STATE_FILE" > "$STATE_FILE.tmp"
            mv "$STATE_FILE.tmp" "$STATE_FILE"
        ) 200>"$STATE_FILE.lock"
    else
        # macOS/others: Execute directly (mv operation itself is atomic)
        jq "${jq_args[@]}" "$jq_expr" "$STATE_FILE" > "$STATE_FILE.tmp"
        mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
}

# ============================================
# State key generation
# ============================================

# Generate state file key: {mainDir}
# Note: Use main repository directory instead of work directory to ensure main repo and worktree share the same state key
# This is consistent with container name generation logic (container names are also based on main repo directory)
# One repository corresponds to one container, regardless of agent or run mode
function generate_state_key() {
    local work_dir="$1"

    # Get main repository directory (if it's a worktree, return main repo directory)
    # Ensure main repo and worktree share the same state key
    local main_dir=$(get_main_repo_dir "$work_dir")

    echo "${main_dir}"
}

# ============================================
# Container mapping queries
# ============================================

# Get container name by work directory
function get_container_by_workdir() {
    local work_dir="$1"
    local key=$(generate_state_key "$work_dir")
    jq -r --arg key "$key" '.[$key] // empty' "$STATE_FILE"
}

# Get state key by container name
function get_state_key_by_container() {
    local container_name="$1"
    jq -r --arg name "$container_name" 'to_entries[] | select(.value == $name) | .key' "$STATE_FILE"
}

# Get main repository directory from container name
# Note: Returns main repository directory, not actual work directory (worktree scenario)
function get_workdir_by_container() {
    local container_name="$1"
    local state_key=$(get_state_key_by_container "$container_name")
    if [[ -n "$state_key" ]]; then
        # State key is the main directory path
        echo "$state_key"
    fi
}

# ============================================
# Container mapping save and delete
# ============================================

# Save container mapping
function save_container_mapping() {
    local work_dir="$1"
    local container_name="$2"
    local key=$(generate_state_key "$work_dir")

    # Use safe update function (cross-platform compatible)
    safe_jq_update '. + {($key): $name}' --arg key "$key" --arg name "$container_name"
}

# Delete container mapping (by key)
function remove_container_mapping() {
    local work_dir="$1"
    local key=$(generate_state_key "$work_dir")

    # Use safe update function (cross-platform compatible)
    safe_jq_update 'del(.[$key])' --arg key "$key"
}

# Delete mapping by container name
function remove_container_mapping_by_container() {
    local container_name="$1"

    # Use safe update function (cross-platform compatible)
    safe_jq_update 'to_entries | map(select(.value != $name)) | from_entries' --arg name "$container_name"
}
