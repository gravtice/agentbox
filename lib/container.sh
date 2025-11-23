#!/bin/bash
# Copyright 2024-2025 Gravtice
# SPDX-License-Identifier: Apache-2.0
#
# lib/container.sh - Container lifecycle management
# Depends on variables and functions provided by common.sh/state.sh/docker.sh

# ============================================
# Container environment preparation
# ============================================

function prepare_container_environment() {
    local container_name="$1"
    local user_id="$2"
    local group_id="$3"
    local quiet="${4:-0}"

    local prepare_cmd
    prepare_cmd=$(cat <<EOF
# Remove container identifier files
rm -f /.dockerenv
rm -f /run/.containerenv

# Git configuration is provided through mounting ~/.gbox/.gitconfig
# Verify that the configuration is correctly mounted
if [[ -f \$HOME/.gitconfig ]]; then
    echo '✅ Git config mounted'
else
    echo '⚠️  Warning: Git config file not found'
fi

# Create user (matching host UID/GID)
groupadd -g ${group_id} guser 2>/dev/null || true
useradd -u ${user_id} -g ${group_id} -d \$HOME -s /bin/bash guser 2>/dev/null || true

# Ensure entire HOME directory is owned by guser (including all mount points and subdirectories)
# This allows any program to create config files and cache directories under HOME
chown -R ${user_id}:${group_id} \$HOME 2>/dev/null || true

# Clean Playwright lock directories (aggressive strategy)
# Playwright MCP uses fixed directory names, prone to lock issues
# Clean on every startup to ensure clean environment (user data not important, can re-login)
find /usr/local/share/playwright -maxdepth 1 -name "mcp-chrome-*" -type d -exec rm -rf {} + 2>/dev/null || true

# Also clean up potentially stray Chrome processes (use kill instead of pkill to avoid hanging)
ps aux | grep -E 'chrome.*--user-data-dir=/usr/local/share/playwright' | grep -v grep | awk '{print \$2}' | xargs -r kill -9 2>/dev/null || true

# Claude Code config file path handling:
# - Claude Code expects config at \$HOME/.claude.json
# - To share config across all containers, we mount ~/.gbox/claude/ to \$HOME/.claude/
# - Actual config file is at \$HOME/.claude/.claude.json
# - Create symlink: \$HOME/.claude.json -> \$HOME/.claude/.claude.json

# Ensure .claude/.claude.json exists
if [[ ! -f \$HOME/.claude/.claude.json ]]; then
    echo '{}' > \$HOME/.claude/.claude.json
    chown ${user_id}:${group_id} \$HOME/.claude/.claude.json
    echo '📝 Created new Claude config file'
fi

# Create symlink (if not exists)
if [[ ! -e \$HOME/.claude.json ]]; then
    ln -s \$HOME/.claude/.claude.json \$HOME/.claude.json
    echo '✅ Created config file symlink: \$HOME/.claude.json -> \$HOME/.claude/.claude.json'
fi

# Verify OAuth config
if grep -q '\"oauthAccount\"' \$HOME/.claude/.claude.json 2>/dev/null; then
    echo '✅ Detected Claude OAuth config (shared across all containers)'
else
    echo '📝 First time using Claude, need to login to Claude Code'
    echo '   After startup, complete OAuth login, auth info will be saved in ~/.gbox/claude/.claude.json'
fi

# Codex config file path handling:
# - Codex uses \$HOME/.codex/config.toml
# - To share config across all containers, we mount ~/.gbox/codex/ to \$HOME/.codex/

# Ensure .codex directory exists and belongs to guser
if [[ ! -d \$HOME/.codex ]]; then
    mkdir -p \$HOME/.codex
    chown ${user_id}:${group_id} \$HOME/.codex
    echo '📝 Created Codex config directory'
fi

# If config.toml does not exist, create a basic config
if [[ ! -f \$HOME/.codex/config.toml ]]; then
    cat > \$HOME/.codex/config.toml <<'CODEX_CONFIG'
model = "gpt-5-codex"
model_reasoning_effort = "high"
model_reasoning_summary = "detailed"
approval_policy = "never"
sandbox_mode = "danger-full-access"

[mcp_servers.playwright]
command = "npx"
args = ["-y", "@playwright/mcp@latest", "--isolated", "--no-sandbox"]

[mcp_servers.playwright.env]
PLAYWRIGHT_BROWSERS_PATH = "/usr/local/share/playwright"
CODEX_CONFIG
    chown ${user_id}:${group_id} \$HOME/.codex/config.toml
    echo '📝 Created default Codex config file (with Playwright MCP support)'
fi

# Happy login state sharing handling:
# - Each container has its own happy config directory (with independent machineId and daemon state)
# - But all containers share login credentials (access.key) to avoid re-login
# - Implemented via symlink: \$HOME/.happy/access.key -> \$HOME/.happy-shared/access.key

# Ensure shared directory exists
if [[ ! -d \$HOME/.happy-shared ]]; then
    mkdir -p \$HOME/.happy-shared
    chown ${user_id}:${group_id} \$HOME/.happy-shared
    echo '📝 Created Happy shared config directory'
fi

# Handle access.key sharing
# Scenario 1: Current container has access.key but it's not a symlink (old data or new login) -> move to shared/
if [[ -f \$HOME/.happy/access.key ]] && [[ ! -L \$HOME/.happy/access.key ]]; then
    mv \$HOME/.happy/access.key \$HOME/.happy-shared/access.key
    chown ${user_id}:${group_id} \$HOME/.happy-shared/access.key
    echo '📦 Migrated login credentials to shared directory'
fi

# Scenario 2: shared/ has access.key, but current container doesn't -> create symlink
if [[ -f \$HOME/.happy-shared/access.key ]] && [[ ! -e \$HOME/.happy/access.key ]]; then
    ln -s \$HOME/.happy-shared/access.key \$HOME/.happy/access.key
    echo '✅ Created login credential symlink (login state shared across all containers)'
fi

# Verify login state
if [[ -f \$HOME/.happy-shared/access.key ]]; then
    echo '✅ Detected Happy login credentials (shared across all containers)'
else
    echo '📝 First time using Happy, need to login'
    echo '   After startup run: happy auth login'
fi

# Verify Happy environment variable config
echo '✅ Happy permission config set (via environment variable)'
echo '   HAPPY_AUTO_BYPASS_PERMISSIONS=1 will auto-skip permissions in all modes'

# Setup git-protector for guser
# Git Protector wraps rm/mv/rmdir commands to prevent accidental deletion of .git directories
if [[ ! -f \$HOME/.bashrc ]] || ! grep -q 'git-protector' \$HOME/.bashrc; then
    cat >> \$HOME/.bashrc <<'BASHRC_APPEND'

# Load Git Protector (protects .git directories from accidental deletion)
if [[ -f /usr/local/bin/git-protector.sh ]]; then
    source /usr/local/bin/git-protector.sh
fi
BASHRC_APPEND
    chown ${user_id}:${group_id} \$HOME/.bashrc
    echo '✅ Enabled Git Protector (dual-layer protection)'
    echo '   - Layer 1: Command wrapping (rm/mv/rmdir functions)'
    echo '   - Layer 2: System command replacement (/bin/rm, /bin/mv, /bin/rmdir)'
fi
EOF
    )

    if (( quiet == 0 )); then
        echo -e "${YELLOW}Preparing environment...${NC}"
        docker exec "$container_name" bash -c "$prepare_cmd"
        echo ""
        echo -e "${GREEN}✓ Environment preparation complete!${NC}"
        echo ""
        echo -e "${BLUE}Next steps:${NC}"
        echo -e "  ${YELLOW}./gbox claude $container_name${NC}  # Start Claude Code"
        echo ""
    else
        docker exec "$container_name" bash -c "$prepare_cmd" >/dev/null
    fi
}

# ============================================
# Container creation and startup
# ============================================

function start_container() {
    local container_name="$1"
    local work_dir="${2:-.}"
    local run_mode="${3:-only-local}"  # only-local or local-remote
    local agent="${4:-claude}"  # claude or codex
    local quiet_mode=0

    # Ensure image exists
    ensure_image

    # Verify that container name is not empty
    if [[ -z "$container_name" ]]; then
        echo -e "${RED}Error: Please specify container name${NC}"
        echo -e "${YELLOW}Usage: ./gbox new <container-name> [work-directory]${NC}"
        echo -e "${YELLOW}Example: ./gbox new myproject${NC}"
        exit 1
    fi

    # Verify container name format
    if ! validate_container_name "$container_name"; then
        exit 1
    fi

    # Convert to absolute path
    work_dir=$(cd "$work_dir" && pwd)

    # Check if directory exists
    if [[ ! -d "$work_dir" ]]; then
        echo -e "${RED}Error: Work directory does not exist: $work_dir${NC}"
        exit 1
    fi

    # Check if it's a git repository or worktree
    # Note: Regular repos have .git as directory, worktrees have .git as file
    if [[ ! -e "$work_dir/.git" ]]; then
        if (( quiet_mode == 0 )); then
            echo -e "${YELLOW}Warning: $work_dir is not a git repository or worktree${NC}"
        fi
    fi

    # Check if container name already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${RED}Error: Container name $container_name already exists${NC}"
        echo -e "${YELLOW}Hint: Use './gbox list' to view all containers${NC}"
        echo -e "${YELLOW}Or: Use a different container name${NC}"
        exit 1
    fi

    # Parse port mapping configuration
    local port_mappings=$(parse_port_mappings "$CONTAINER_PORTS" "$run_mode")

    # Parse read-only reference directories configuration
    parse_ref_dirs "$CONTAINER_REF_DIRS" "$work_dir"
    local -a ref_dir_mappings=("${REF_DIR_MOUNT_ARGS[@]}")
    local -a ref_dir_sources=("${REF_DIR_SOURCE_DIRS[@]}")

    # Ensure network exists
    ensure_network

    # Get main repository directory (if worktree, returns main repo directory)
    local main_dir=$(get_main_repo_dir "$work_dir")

    # Ensure worktrees directory exists and get path (based on main repo directory)
    local worktree_dir=$(ensure_worktree_dir "$main_dir" "$quiet_mode")

    # Container log file
    local log_file="$LOGS_DIR/${container_name}.log"

    if (( quiet_mode == 0 )); then
        echo -e "${GREEN}Starting new container...${NC}"
        echo -e "  Run mode: ${BLUE}$run_mode${NC}"
        echo -e "  AI Agent: ${BLUE}$agent${NC}"
        echo -e "  Main repo directory: ${BLUE}$main_dir${NC}"
        echo -e "  Work directory: ${BLUE}$work_dir${NC}"
        echo -e "  Worktrees directory: ${BLUE}$worktree_dir${NC}"
        echo -e "  Container name: ${BLUE}$container_name${NC}"
        if [[ -n "$port_mappings" ]]; then
            echo -e "  Port mapping: ${BLUE}${port_mappings//-p /}${NC}"
        else
            echo -e "  Port mapping: ${BLUE}None (container network only)${NC}"
        fi
        if (( ${#ref_dir_sources[@]} > 0 )); then
            # Count reference directories
            local ref_count=${#ref_dir_sources[@]}
            echo -e "  Reference directories: ${BLUE}${ref_count} read-only directories${NC}"
            for src_dir in "${ref_dir_sources[@]}"; do
                echo -e "    - ${BLUE}${src_dir}${NC} (read-only)"
            done
        fi
        echo -e "  User permissions: ${BLUE}$(id -u):$(id -g)${NC}"
        echo -e "  Permission-less mode: ${BLUE}Enabled${NC}"
        echo -e "  Resource limits: ${BLUE}Memory=${MEMORY_LIMIT}, CPU=${CPU_LIMIT} cores${NC}"
        echo -e "  File descriptors: ${BLUE}65536${NC}"
        echo -e "  TCP Keepalive: ${BLUE}5 minutes (optimize long connection stability)${NC}"
        echo -e "  Dependency cache: ${BLUE}Enabled (pip/npm/uv)${NC}"
        echo -e "  Container logs: ${BLUE}$log_file${NC}"
        echo -e "  Network mode: ${BLUE}$NETWORK_NAME${NC}"
        echo -e "  Claude config: ${BLUE}$GBOX_CLAUDE_DIR${NC}"
        echo -e "  Codex config: ${BLUE}$GBOX_CODEX_DIR${NC}"
        echo -e "  Gemini config: ${BLUE}$GBOX_GEMINI_DIR${NC}"
        echo -e "  Happy config: ${BLUE}$GBOX_HAPPY_DIR${NC}"
        echo ""
    fi

    # Get current user's UID and GID
    local user_id=$(id -u)
    local group_id=$(id -g)

    # Set container hostname: use container name to ensure each container has independent identity
    local container_hostname="$container_name"

    # Start container in background
    # New strategy: gbox independent configuration system
    #   - All Claude configs stored in host ~/.gbox/claude directory
    #   - All Codex configs stored in host ~/.gbox/codex directory
    #   - All Gemini configs stored in host ~/.gbox/gemini directory
    #   - All Happy configs stored in host ~/.gbox/happy directory
    #   - Direct bind mount to container's ~/.claude, ~/.codex, ~/.gemini and ~/.happy directories
    #   - All containers share the same config (OAuth, CLAUDE.md, config.toml etc.)
    #   - Host can directly edit files under ~/.gbox/{claude,codex,gemini,happy}
    #   - Linux containers can share OAuth authentication
    #   - worktrees directory for git worktree parallel development
    #   - Both main directory and worktrees directory mounted to container, ensuring worktree can access main repo
    #   - Support mounting read-only reference directories for providing code references
    docker run -d -it \
        --name "$container_name" \
        --hostname "$container_hostname" \
        -v "$GBOX_CLAUDE_DIR:$HOME/.claude" \
        -v "$GBOX_CODEX_DIR:$HOME/.codex" \
        -v "$GBOX_GEMINI_DIR:$HOME/.gemini" \
        -v "$GBOX_HAPPY_DIR/$container_name:$HOME/.happy" \
        -v "$GBOX_HAPPY_DIR/shared:$HOME/.happy-shared" \
        -v "$GBOX_CONFIG_DIR/.gitconfig:$HOME/.gitconfig:ro" \
        -v "$main_dir:$main_dir" \
        -v "$worktree_dir:$worktree_dir" \
        -v "$CACHE_DIR/pip:/tmp/.cache/pip" \
        -v "$CACHE_DIR/npm:/tmp/.npm" \
        -v "$CACHE_DIR/uv:/tmp/.cache/uv" \
        -v "$log_file:/var/log/gbox.log" \
        $port_mappings \
        "${ref_dir_mappings[@]}" \
        -w "$work_dir" \
        -e "HOME=$HOME" \
        -e "GBOX_USER_ID=${user_id}" \
        -e "GBOX_GROUP_ID=${group_id}" \
        -e "GBOX_WORK_DIR=$work_dir" \
        -e "GBOX_MAIN_DIR=$main_dir" \
        -e "PIP_CACHE_DIR=/tmp/.cache/pip" \
        -e "NPM_CONFIG_CACHE=/tmp/.npm" \
        -e "UV_CACHE_DIR=/tmp/.cache/uv" \
        -e "PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/" \
        -e "NPM_CONFIG_REGISTRY=https://registry.npmmirror.com" \
        -e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}" \
        -e "HAPPY_AUTO_BYPASS_PERMISSIONS=1" \
        -e "DEBUG=${DEBUG:-}" \
        --user "root" \
        --memory="$MEMORY_LIMIT" \
        --cpus="$CPU_LIMIT" \
        --network="$NETWORK_NAME" \
        --sysctl net.ipv4.tcp_keepalive_time=300 \
        --sysctl net.ipv4.tcp_keepalive_intvl=30 \
        --sysctl net.ipv4.tcp_keepalive_probes=3 \
        --ulimit nofile=65536:65536 \
        "$IMAGE_FULL" \
        bash > /dev/null

    if (( quiet_mode == 0 )); then
        echo -e "${GREEN}✓ Container started in background${NC}"
        echo ""
    fi

    if ! wait_for_container_ready "$container_name"; then
        echo -e "${RED}Error: Container $container_name did not become ready in expected time after startup${NC}"
        echo -e "${YELLOW}Please check container logs: gbox logs $container_name${NC}"
        docker rm -f "$container_name" >/dev/null 2>&1 || true
        remove_container_mapping "$work_dir"
        exit 1
    fi

    # Prepare container environment (non-interactive)
    prepare_container_environment "$container_name" "$user_id" "$group_id" "$quiet_mode"
}

# ============================================
# Container query and status
# ============================================

function list_containers() {
    echo -e "${GREEN}Running gbox containers:${NC}"
    echo ""

    local containers=$(docker ps --filter "name=${CONTAINER_PREFIX}-" --format "{{.Names}}")

    if [[ -z "$containers" ]]; then
        echo -e "${YELLOW}No running containers${NC}"
        return
    fi

    printf "%-30s %-35s %-30s %-15s\n" "Container" "Work Dir" "Image" "Port"
    echo "------------------------------------------------------------------------------------------------------------------------"

    while IFS= read -r container; do
        local workdir=$(get_workdir_by_container "$container")
        local port=$(docker port "$container" 8000 2>/dev/null | cut -d: -f2)
        local image=$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null)
        printf "%-30s %-35s %-30s %-15s\n" "$container" "${workdir:-Unknown}" "${image:-Unknown}" "$port:8000"
    done <<< "$containers"
}

function show_status() {
    echo -e "${GREEN}All gbox container status:${NC}"
    echo ""

    printf "%-30s %-20s %-15s %-50s %-15s %-15s\n" "Container" "Run Mode" "Agent" "Work Dir" "Status" "Port"
    echo "-----------------------------------------------------------------------------------------------------------------------------------"

    # Key format: "{workDir}:{run_mode}:{agent}"
    jq -r 'to_entries[] | "\(.key)|\(.value)"' "$STATE_FILE" | while IFS='|' read -r state_key container; do
        # Separate workDir, run_mode, agent
        local workdir="${state_key%%:*}"
        local rest="${state_key#*:}"
        local run_mode="${rest%%:*}"
        local agent="${rest##*:}"

        if is_container_running "$container"; then
            local port=$(docker port "$container" 8000 2>/dev/null | cut -d: -f2)
            printf "%-30s %-20s %-15s %-50s %-15s %-15s\n" "$container" "$run_mode" "$agent" "$workdir" "Running" "$port:8000"
        else
            printf "%-30s %-20s %-15s %-50s %-15s %-15s\n" "$container" "$run_mode" "$agent" "$workdir" "Stopped" "-"
        fi
    done
}

# ============================================
# Container stop and cleanup
# ============================================

function stop_container() {
    local container_name="$1"
    if [[ -z "$container_name" ]]; then
        echo -e "${RED}Error: Please specify container name${NC}"
        echo -e "${YELLOW}Hint: Use './gbox list' to view running containers${NC}"
        exit 1
    fi

    # Check if container exists (running or stopped)
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${RED}Error: Container $container_name does not exist${NC}"
        exit 1
    fi

    # If container is running, stop it first
    if is_container_running "$container_name"; then
        echo -e "${YELLOW}Stopping container: $container_name${NC}"
        docker stop "$container_name" > /dev/null
    else
        echo -e "${YELLOW}Removing stopped container: $container_name${NC}"
    fi

    # Remove container
    docker rm "$container_name" > /dev/null

    # Clean up Happy config directory for this container
    # This prevents stale daemon.state.json and other Happy state files from being reused
    # when a container with the same name is created again
    local happy_container_dir="$GBOX_HAPPY_DIR/$container_name"
    if [[ -d "$happy_container_dir" ]]; then
        echo -e "${YELLOW}Cleaning up Happy config directory...${NC}"
        rm -rf "$happy_container_dir"
        echo -e "${GREEN}✓ Happy config directory removed${NC}"
    fi

    # Clean up mapping (delete directly using container name)
    remove_container_mapping_by_container "$container_name"

    echo -e "${GREEN}✓ Container removed${NC}"
}

function stop_all_containers() {
    echo -e "${YELLOW}Stopping and removing all gbox containers...${NC}"
    local containers=$(docker ps --filter "name=${CONTAINER_PREFIX}-" -q)

    if [[ -z "$containers" ]]; then
        echo -e "${YELLOW}No running containers${NC}"
        return
    fi

    # Get container names before deletion for Happy cleanup
    local container_names=$(docker ps --filter "name=${CONTAINER_PREFIX}-" --format '{{.Names}}')

    echo "$containers" | xargs docker stop
    echo "$containers" | xargs docker rm

    # Clean up Happy config directories for all containers
    echo -e "${YELLOW}Cleaning up Happy config directories...${NC}"
    while IFS= read -r container_name; do
        local happy_container_dir="$GBOX_HAPPY_DIR/$container_name"
        if [[ -d "$happy_container_dir" ]]; then
            rm -rf "$happy_container_dir"
            echo -e "${GREEN}✓ Removed Happy config for: $container_name${NC}"
        fi
    done <<< "$container_names"

    # Clean up all mappings
    echo '{}' > "$STATE_FILE"

    echo -e "${GREEN}Done: All containers stopped and removed${NC}"
}

function clean_containers() {
    echo -e "${YELLOW}Cleaning stopped containers and mappings...${NC}"

    # Get stopped container names before deletion for Happy cleanup
    local stopped_names=$(docker ps -a --filter "name=${CONTAINER_PREFIX}-" --filter "status=exited" --format '{{.Names}}')

    # Clean up Docker containers
    local stopped=$(docker ps -a --filter "name=${CONTAINER_PREFIX}-" --filter "status=exited" -q)
    if [[ -n "$stopped" ]]; then
        echo "$stopped" | xargs docker rm

        # Clean up Happy config directories for stopped containers
        if [[ -n "$stopped_names" ]]; then
            echo -e "${YELLOW}Cleaning up Happy config directories...${NC}"
            while IFS= read -r container_name; do
                local happy_container_dir="$GBOX_HAPPY_DIR/$container_name"
                if [[ -d "$happy_container_dir" ]]; then
                    rm -rf "$happy_container_dir"
                    echo -e "${GREEN}✓ Removed Happy config for: $container_name${NC}"
                fi
            done <<< "$stopped_names"
        fi
    fi

    # Clean up invalid mappings (filter directly with jq)
    # Note: Key format is "{workDir}:{agent}"
    local all_containers=$(docker ps -a --format '{{.Names}}')
    safe_jq_update 'to_entries | map(select($containers | contains(.value))) | from_entries' --arg containers "$all_containers"

    echo -e "${GREEN}Done${NC}"
}

# ============================================
# Logs and command execution
# ============================================

function show_logs() {
    local container_name="$1"
    if [[ -z "$container_name" ]]; then
        echo -e "${RED}Error: Please specify container name${NC}"
        exit 1
    fi

    docker logs -f "$container_name"
}

function exec_command() {
    local container_name="$1"
    shift
    local command="$@"

    if [[ -z "$container_name" ]]; then
        echo -e "${RED}Error: Please specify container name${NC}"
        exit 1
    fi

    docker exec "${DOCKER_EXEC_TTY_ARGS[@]}" "$container_name" bash -c "$command"
}

function shell_command() {
    local container_name="$1"

    if [[ -z "$container_name" ]]; then
        echo -e "${RED}Error: Please specify container name${NC}"
        echo -e "${YELLOW}Usage: gbox shell <container-name>${NC}"
        echo -e "${YELLOW}Hint: Use 'gbox list' to view running containers${NC}"
        exit 1
    fi

    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${RED}Error: Container '$container_name' does not exist${NC}"
        echo -e "${YELLOW}Hint: Use 'gbox list' to view running containers${NC}"
        exit 1
    fi

    # Check if container is running
    local container_state=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
    if [[ "$container_state" != "running" ]]; then
        echo -e "${YELLOW}Container '$container_name' is not running, starting...${NC}"
        docker start "$container_name" >/dev/null 2>&1
        if ! wait_for_container_ready "$container_name"; then
            echo -e "${RED}Error: Container startup failed${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Container started${NC}"
    fi

    echo -e "${GREEN}Logging into container '$container_name'...${NC}"
    echo -e "${BLUE}Hint: Use 'exit' or Ctrl+D to exit container shell${NC}"
    echo ""

    # Log into container bash shell as guser
    docker exec "${DOCKER_EXEC_TTY_ARGS[@]}" --user guser "$container_name" bash
}

