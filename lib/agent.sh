# Copyright 2024-2025 Gravtice
# SPDX-License-Identifier: Apache-2.0
#
# lib/agent.sh
# Agent session management related functions (extracted from gbox.backup, do not modify logic)

# ========================
# Port mapping utility functions
# ========================
function parse_port_mappings() {
    local ports_config="$1"
    local run_mode="$2"  # "only-local" or "local-remote"
    local result=""

    # If empty, do not map any ports (local mode and Happy remote mode do not need default mapping)
    if [[ -z "$ports_config" ]]; then
        return 0
    fi

    # Split port mappings (semicolon separated)
    IFS=';' read -ra port_items <<< "$ports_config"

    for port_item in "${port_items[@]}"; do
        port_item=$(echo "$port_item" | xargs)  # Remove whitespace
        [[ -z "$port_item" ]] && continue

        # Only support host_port:container_port format
        if [[ "$port_item" =~ ^([0-9]+):([0-9]+)$ ]]; then
            local host_port="${BASH_REMATCH[1]}"
            local container_port="${BASH_REMATCH[2]}"
            result="$result -p 127.0.0.1:${host_port}:${container_port}"
        else
            echo -e "${YELLOW}Warning: Port configuration format error '$port_item', should be 'host_port:container_port'${NC}" >&2
        fi
    done

    echo "$result"
}

# ========================
# Container naming utility functions
# ========================
function generate_container_name() {
    local work_dir="$1"

    # Get main repository directory (if it's a worktree, returns the main repository directory)
    # This ensures the same container name is used whether starting from the main directory or worktrees subdirectory
    local main_dir=$(get_main_repo_dir "$work_dir")

    # Get the basename of the main directory
    local dir_name=$(basename "$main_dir")
    # Convert to lowercase, replace illegal characters with hyphens
    local dir_part=$(echo "$dir_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')

    # Generate container name: gbox-{dirname}
    # One repository corresponds to one container, regardless of agent or run mode
    echo "${CONTAINER_PREFIX}-${dir_part}"
}

# ========================
# Agent parameter append utility functions
# ========================
function append_agent_args_to_cmd() {
    local base_cmd="$1"
    local skip_delimiter="${2:-0}"
    shift 2 || true
    local args=("$@")

    if (( ${#args[@]} == 0 )); then
        echo "$base_cmd"
        return
    fi

    local needs_delimiter=0

    if (( skip_delimiter == 0 )); then
        if [[ "${args[0]}" == "--" ]]; then
            needs_delimiter=1
            args=("${args[@]:1}")
        elif [[ "${args[0]}" != -* ]]; then
            needs_delimiter=1
        fi
    fi

    if (( needs_delimiter == 1 )); then
        base_cmd="$base_cmd --"
    fi

    if (( ${#args[@]} > 0 )); then
        base_cmd="$base_cmd ${args[*]}"
    fi

    echo "$base_cmd"
}

# ========================
# Agent session management
# ========================
function agent_session() {
    local run_mode="$1"
    local agent="$2"
    shift 2
    local agent_args=("$@")

    local agent_args_skip_delimiter=0
    if [[ "$agent" == "claude" ]]; then
        for arg in "${agent_args[@]}"; do
            [[ -z "$arg" ]] && continue
            if [[ "$arg" == "--" ]]; then
                continue
            fi
            if [[ "$arg" == "mcp" ]]; then
                agent_args_skip_delimiter=1
            fi
            break
        done
    fi

    # Use current directory as working directory
    local work_dir=$(pwd)

    # Proxy configuration to inject (if provided by user via environment variable or parameter)
    local agent_proxy_value="${AGENT_PROXY:-}"
    local agent_cmd_prefix="cd '$work_dir' && export PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/playwright"
    if [[ -n "$agent_proxy_value" ]]; then
        local agent_proxy_escaped
        agent_proxy_escaped=$(printf '%q' "$agent_proxy_value")
        agent_cmd_prefix="$agent_cmd_prefix && export GBOX_PROXY=$agent_proxy_escaped && export HTTP_PROXY=$agent_proxy_escaped && export HTTPS_PROXY=$agent_proxy_escaped && export ALL_PROXY=$agent_proxy_escaped && export http_proxy=$agent_proxy_escaped && export https_proxy=$agent_proxy_escaped && export all_proxy=$agent_proxy_escaped"
    fi
    agent_cmd_prefix="$agent_cmd_prefix && exec "

    # Generate container name based on working directory
    # One repository corresponds to one container, regardless of agent or run mode
    local container_name=$(generate_container_name "$work_dir")

    # Check if container already exists
    local existing_container=$(get_container_by_workdir "$work_dir")

    local actual_container=""
    local container_created=0
    local container_started=0
    local existed_before=false

    if [[ -n "$existing_container" ]]; then
        # Mapping exists in status file, check if container actually exists
        if ! docker ps -a --format '{{.Names}}' | grep -q "^${existing_container}$"; then
            # Container mapping exists but container actually doesn't (may have been manually deleted), clean up mapping
            echo -e "${YELLOW}Container mapping exists but container has been deleted, cleaning up state...${NC}"
            remove_container_mapping "$work_dir"
            existing_container=""  # Clear it, will recreate later
        fi
    fi

    if [[ -n "$existing_container" ]]; then
        # Container exists, check if it's running
        if ! is_container_running "$existing_container"; then
            # Container exists but is not running, start it
            echo -e "${YELLOW}Container has stopped, starting...${NC}"
            docker start "$existing_container" >/dev/null 2>&1

            # Wait for container to be ready
            if ! wait_for_container_ready "$existing_container"; then
                echo -e "${RED}Error: Container startup failed${NC}"
                exit 1
            fi

            container_started=1
        fi

        # Container should now be running
        actual_container="$existing_container"
        existed_before=true

        # Display notification and execute
        echo -e "${GREEN}Connecting to existing container${NC}"
        echo -e "  Run mode: ${BLUE}$run_mode${NC}"
        echo -e "  Agent: ${BLUE}$agent${NC}"
        echo -e "  Container: ${BLUE}$existing_container${NC}"
        echo -e "  Directory: ${BLUE}$work_dir${NC}"
        echo ""

        # Clean up Playwright lock directory and processes (clean up on every connection)
        docker exec "$existing_container" bash -c '
            # Stop Chrome and Playwright processes
            pkill -9 chrome 2>/dev/null || true
            pkill -9 playwright 2>/dev/null || true
            # Clean up browser data directory
            find /usr/local/share/playwright -maxdepth 1 -name "mcp-chrome-*" -type d -exec rm -rf {} + 2>/dev/null || true
        ' >/dev/null 2>&1

        # Determine the command to execute based on run mode and agent
        local cmd="$agent_cmd_prefix"
        if [[ "$run_mode" == "local-remote" ]]; then
            # Remote collaboration mode: use happy
            cmd="${cmd}happy $agent"
            # claude needs --dangerously-skip-permissions
            if [[ "$agent" == "claude" ]]; then
                cmd="$cmd --dangerously-skip-permissions"
            # gemini needs --yolo automation mode
            elif [[ "$agent" == "gemini" ]]; then
                cmd="$cmd --yolo"
            fi
        else
            # Local mode: run agent directly
            cmd="${cmd}$agent"
            # claude needs --dangerously-skip-permissions
            if [[ "$agent" == "claude" ]]; then
                cmd="$cmd --dangerously-skip-permissions"
            # gemini needs --yolo automation mode
            elif [[ "$agent" == "gemini" ]]; then
                cmd="$cmd --yolo"
            fi
        fi

        # Add parameters passed by user
        cmd=$(append_agent_args_to_cmd "$cmd" "$agent_args_skip_delimiter" "${agent_args[@]}")

        echo -e "${YELLOW}Tip: Press Ctrl+C to exit${NC}"
        echo ""

        docker exec "${DOCKER_EXEC_TTY_ARGS[@]}" --user guser "$existing_container" bash -c "$cmd"

    else
        # Container mapping doesn't exist, but check if there's a container with the same name (may be orphaned)
        if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
            # Container with same name exists, try to use it
            echo -e "${YELLOW}Detected container with same name (may be orphaned), recovering...${NC}"

            # Check if container is running
            if ! is_container_running "$container_name"; then
                # Container exists but is not running, start it
                echo -e "${YELLOW}Container has stopped, starting...${NC}"
                docker start "$container_name" >/dev/null 2>&1

                # Wait for container to be ready
                if ! wait_for_container_ready "$container_name"; then
                    echo -e "${RED}Error: Container startup failed${NC}"
                    exit 1
                fi

                container_started=1
            fi

            # Restore mapping relationship
            save_container_mapping "$work_dir" "$container_name"
            actual_container="$container_name"
            existed_before=true

            echo -e "${GREEN}Connecting to existing container${NC}"
            echo -e "  Run mode: ${BLUE}$run_mode${NC}"
            echo -e "  Agent: ${BLUE}$agent${NC}"
            echo -e "  Container: ${BLUE}$container_name${NC}"
            echo -e "  Directory: ${BLUE}$work_dir${NC}"
            echo ""

            # Clean up Playwright lock directory and processes
            docker exec "$container_name" bash -c '
                pkill -9 chrome 2>/dev/null || true
                pkill -9 playwright 2>/dev/null || true
                find /usr/local/share/playwright -maxdepth 1 -name "mcp-chrome-*" -type d -exec rm -rf {} + 2>/dev/null || true
            ' >/dev/null 2>&1

            # Execute agent command
            local cmd="$agent_cmd_prefix"
            if [[ "$run_mode" == "local-remote" ]]; then
                cmd="${cmd}happy $agent"
                if [[ "$agent" == "claude" ]]; then
                    cmd="$cmd --dangerously-skip-permissions"
                elif [[ "$agent" == "gemini" ]]; then
                    cmd="$cmd --yolo"
                fi
            else
                cmd="${cmd}$agent"
                if [[ "$agent" == "claude" ]]; then
                    cmd="$cmd --dangerously-skip-permissions"
                elif [[ "$agent" == "gemini" ]]; then
                    cmd="$cmd --yolo"
                fi
            fi

            cmd=$(append_agent_args_to_cmd "$cmd" "$agent_args_skip_delimiter" "${agent_args[@]}")

            echo -e "${YELLOW}Tip: Press Ctrl+C to exit${NC}"
            echo ""

            docker exec "${DOCKER_EXEC_TTY_ARGS[@]}" --user guser "$container_name" bash -c "$cmd"

        else
            # Container doesn't exist, auto-create it
            actual_container="$container_name"
            container_created=1
            container_started=1

            echo -e "${YELLOW}Container does not exist, creating...${NC}"
            echo ""

            # Call start_container to create container
            start_container "$container_name" "$work_dir" "$run_mode" "$agent"

            # Save mapping relationship
            save_container_mapping "$work_dir" "$container_name"
        fi

        # Display notification and execute
        echo ""
        echo -e "${GREEN}Container creation complete, starting...${NC}"
        echo -e "  Run mode: ${BLUE}$run_mode${NC}"
        echo -e "  Agent: ${BLUE}$agent${NC}"
        echo -e "  Container: ${BLUE}$container_name${NC}"
        echo -e "  Directory: ${BLUE}$work_dir${NC}"
        echo ""

        # Determine the command to execute based on run mode and agent
        local cmd="$agent_cmd_prefix"
        if [[ "$run_mode" == "local-remote" ]]; then
            # Remote collaboration mode: use happy
            cmd="${cmd}happy $agent"
            # claude needs --dangerously-skip-permissions
            if [[ "$agent" == "claude" ]]; then
                cmd="$cmd --dangerously-skip-permissions"
            # gemini needs --yolo automation mode
            elif [[ "$agent" == "gemini" ]]; then
                cmd="$cmd --yolo"
            fi
        else
            # Local mode: run agent directly
            cmd="${cmd}$agent"
            # claude needs --dangerously-skip-permissions
            if [[ "$agent" == "claude" ]]; then
                cmd="$cmd --dangerously-skip-permissions"
            # gemini needs --yolo automation mode
            elif [[ "$agent" == "gemini" ]]; then
                cmd="$cmd --yolo"
            fi
        fi

        # Add parameters passed by user
        cmd=$(append_agent_args_to_cmd "$cmd" "$agent_args_skip_delimiter" "${agent_args[@]}")

        echo -e "${YELLOW}Tip: Press Ctrl+C to exit${NC}"
        echo ""

        docker exec "${DOCKER_EXEC_TTY_ARGS[@]}" --user guser "$container_name" bash -c "$cmd"
    fi

    # Notification and cleanup after exit
    echo ""
    echo -e "${GREEN}Exited${NC}"
    echo ""

    # Check if auto-cleanup is needed (default is to keep container)
    local auto_cleanup=0
    if [[ "${GBOX_AUTO_CLEANUP:-0}" == "1" ]]; then
        auto_cleanup=1
    fi

    if (( auto_cleanup == 1 )); then
        # Auto-delete container
        echo -e "${YELLOW}Cleaning up container...${NC}"

        # Stop and delete container
        if is_container_running "$actual_container"; then
            docker stop "$actual_container" > /dev/null 2>&1
        fi
        docker rm "$actual_container" > /dev/null 2>&1

        # Clean up mapping relationship
        remove_container_mapping "$work_dir"

        echo -e "${GREEN}✓ Container cleaned${NC}"
    else
        echo -e "${BLUE}Container preserved: $actual_container${NC}"
        echo -e "${YELLOW}Tip: Use 'gbox stop $actual_container' to stop the container${NC}"
        echo -e "${YELLOW}Tip: Use 'gbox $agent' or 'gbox happy $agent' to continue using${NC}"
    fi
}
