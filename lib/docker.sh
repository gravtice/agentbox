#!/bin/bash
# lib/docker.sh - Docker basic operations
# This module handles Docker network management, container state checking, and worktree directory management

# ============================================
# Docker Exec interaction flags
# ============================================
# Using -t in non-TTY environments causes "the input device is not a TTY" error.
# Determine the appropriate docker exec interaction parameters based on the current environment at script load time.
if [[ -t 0 && -t 1 ]]; then
    DOCKER_EXEC_TTY_ARGS=(-it)
else
    DOCKER_EXEC_TTY_ARGS=(-i)
fi

# ============================================
# Docker network management
# ============================================

# Ensure Docker network exists
function ensure_network() {
    if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
        echo -e "${YELLOW}Creating Docker network: $NETWORK_NAME${NC}"
        docker network create "$NETWORK_NAME"
    fi
}

# ============================================
# Container state checking
# ============================================

# Check if container is running
function is_container_running() {
    local container_name="$1"
    docker ps --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Wait for container to be ready
function wait_for_container_ready() {
    local container_name="$1"
    local attempts="${2:-${GBOX_READY_ATTEMPTS:-30}}"
    local delay="${3:-${GBOX_READY_DELAY:-0.2}}"

    for ((i = 0; i < attempts; i++)); do
        if docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null | grep -q "true"; then
            if docker exec "$container_name" bash -c "true" >/dev/null 2>&1; then
                return 0
            fi
        fi
        sleep "$delay"
    done

    return 1
}

# ============================================
# Worktree directory management
# ============================================

# Detect and get main repository directory
# If current directory is a worktree, return the main repository directory
# If current directory is a main repository or regular directory, return itself
# Directory convention: main directory /path/to/project -> worktrees directory /path/to/project-worktrees
function get_main_repo_dir() {
    local work_dir="$1"

    # Check if it is a git worktree
    if [[ -f "$work_dir/.git" ]]; then
        # If .git is a file (not a directory), it might be a worktree
        local git_content=$(cat "$work_dir/.git" 2>/dev/null)
        if [[ "$git_content" =~ ^gitdir:\ (.+)$ ]]; then
            # This is a worktree, try to get the main repository path via git
            local main_worktree=$(cd "$work_dir" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
            if [[ -n "$main_worktree" ]]; then
                # git-common-dir returns .git/worktrees/<name> or .git
                # Need to extract the main repository root directory
                main_worktree="${main_worktree%/.git*}"
                if [[ -d "$main_worktree" ]]; then
                    echo "$main_worktree"
                    return 0
                fi
            fi
        fi
    fi

    # If not a worktree or unable to detect main repository, check if in worktrees directory
    # Infer by directory naming convention: if parent directory name ends with -worktrees
    local parent_dir=$(dirname "$work_dir")
    local parent_name=$(basename "$parent_dir")

    if [[ "$parent_name" =~ ^(.+)-worktrees$ ]]; then
        # Parent directory is worktrees directory, infer main directory
        local main_name="${BASH_REMATCH[1]}"
        local grandparent=$(dirname "$parent_dir")
        local main_dir="$grandparent/$main_name"

        if [[ -d "$main_dir" ]]; then
            echo "$main_dir"
            return 0
        fi
    fi

    # Default: return the working directory itself (not a worktree)
    echo "$work_dir"
}

# Generate worktrees directory path based on working directory
# Automatically detect main repository directory, ensure convention: main directory /path/to/project -> worktrees directory /path/to/project-worktrees
function get_worktree_dir() {
    local work_dir="$1"

    # First get the main repository directory
    local main_dir=$(get_main_repo_dir "$work_dir")

    # Return the worktrees directory corresponding to the main repository
    echo "${main_dir}-worktrees"
}

# Ensure worktrees directory exists
# Create if directory doesn't exist, skip if already exists
# Return value: worktrees directory path
function ensure_worktree_dir() {
    local work_dir="$1"
    local quiet_mode="${2:-0}"
    local worktree_dir=$(get_worktree_dir "$work_dir")

    if [[ ! -d "$worktree_dir" ]]; then
        mkdir -p "$worktree_dir"
        if (( quiet_mode == 0 )); then
            echo -e "${GREEN}✓ Creating worktrees directory: $worktree_dir${NC}" >&2
        fi
    fi

    echo "$worktree_dir"
}
