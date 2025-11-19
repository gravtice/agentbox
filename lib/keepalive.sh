#!/bin/bash
# lib/keepalive.sh - Keepalive account session maintenance module
# Responsible for account scanning, state management, container lifecycle and command handling, depends on common/state/docker/oauth modules for variables and utilities

# ============================================
# Keepalive Account Session Maintenance
# ============================================

# Keepalive state file
KEEPALIVE_STATE_FILE="$GBOX_CONFIG_DIR/keepalive-state.json"
KEEPALIVE_INTERVAL="${KEEPALIVE_INTERVAL:-3600}"  # Default 1 hour
DOCKER_IMAGE="${IMAGE_FULL}"

# Convert email to suffix (email-safe format)
# Example: agent@gravtice.com -> agent-at-gravtice-com
email_to_suffix() {
    local email="$1"
    echo "$email" | tr '[:upper:]' '[:lower:]' | sed 's/@/-at-/g' | sed 's/\./-/g'
}

# Get the suffix of current account
get_current_account_suffix() {
    local claude_json="$GBOX_CLAUDE_DIR/.claude.json"
    if [[ ! -f "$claude_json" ]]; then
        echo ""
        return 1
    fi

    # Read the email of current account
    local email=$(jq -r '.oauthAccount.emailAddress // empty' "$claude_json" 2>/dev/null)
    if [[ -z "$email" ]]; then
        echo ""
        return 1
    fi

    # Convert email to suffix
    email_to_suffix "$email"
}

# Scan all logged-in accounts (V5 version)
# V5 changes: Use .claude-{suffix}.json instead of .oauth-account-{suffix}.json
# Output format: One account info per line, format is "email-suffix|filepath-suffix"
# Example output:
# current|current                                    # Current account
# agent-at-gravtice-com|agent-at-gravtice-com-2025120115  # Backup account (with limit time)
scan_logged_accounts() {
    local accounts=()

    # 1. Check current account
    if [[ -f "$GBOX_CLAUDE_DIR/.credentials.json" ]]; then
        local email=$(jq -r '.oauthAccount.emailAddress // empty' "$GBOX_CLAUDE_DIR/.claude.json" 2>/dev/null)
        if [[ -n "$email" ]]; then
            # Use "current" as special identifier
            accounts+=("current|current")
        fi
    fi

    # 2. Scan backup accounts (based on .credentials-{suffix}.json)
    for cred_file in "$GBOX_CLAUDE_DIR"/.credentials-*.json; do
        [[ -f "$cred_file" ]] || continue

        local basename=$(basename "$cred_file")
        local suffix="${basename#.credentials-}"
        suffix="${suffix%.json}"

        # Check if corresponding .claude-{suffix}.json exists (V5 changes)
        if [[ -f "$GBOX_CLAUDE_DIR/.claude-${suffix}.json" ]]; then
            # Extract email_suffix (remove limitTime)
            local email_suffix="$suffix"
            if [[ "$suffix" =~ ^(.+)-([0-9]{10})$ ]]; then
                email_suffix="${BASH_REMATCH[1]}"
            fi

            accounts+=("${email_suffix}|${suffix}")
        fi
    done

    # Output all accounts (one per line)
    printf '%s\n' "${accounts[@]}"
}

# Helper function: Extract unique email_suffix list from scan result
get_unique_email_suffixes() {
    local scan_result="$1"
    echo "$scan_result" | cut -d'|' -f1 | sort -u
}

# Get account email and file suffix (V5 version)
# V5 changes: Use .claude-{suffix}.json instead of .oauth-account-{suffix}.json
# Parameter: email_suffix (without limit time) or "current"
# Returns: Account information in JSON format
get_account_info() {
    local email_suffix="$1"

    # If it is current account (email_suffix == "current")
    if [[ "$email_suffix" == "current" ]]; then
        local claude_json="$GBOX_CLAUDE_DIR/.claude.json"
        if [[ -f "$claude_json" ]]; then
            jq -r '.oauthAccount | {
                email: .emailAddress,
                accountUuid: .accountUuid,
                fileSuffix: null
            }' "$claude_json" 2>/dev/null
            return 0
        fi
    fi

    # Read from backup file, find matching .claude-{suffix}.json (may have limit time)
    for claude_file in "$GBOX_CLAUDE_DIR"/.claude-${email_suffix}*.json; do
        [[ -f "$claude_file" ]] || continue

        # Extract suffix from filename
        local basename=$(basename "$claude_file")
        local file_suffix="${basename#.claude-}"
        file_suffix="${file_suffix%.json}"

        # Read account info (from oauthAccount field)
        local info=$(jq -r '.oauthAccount | {
            email: .emailAddress,
            accountUuid: .accountUuid
        }' "$claude_file" 2>/dev/null)

        # Add fileSuffix field
        echo "$info" | jq --arg fs "$file_suffix" '. + {fileSuffix: $fs}' 2>/dev/null
        return 0
    done

    echo "{}"
}

# Get account limit time (extract from filename)
# Parameter: file_suffix (may contain limit time)
# Returns: Limit time string or empty
get_account_limit_time() {
    local file_suffix="$1"

    # Extract limit time from file_suffix
    if [[ "$file_suffix" =~ -([0-9]{10})$ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Initialize state file
init_keepalive_state() {
    if [[ ! -f "$KEEPALIVE_STATE_FILE" ]]; then
        mkdir -p "$(dirname "$KEEPALIVE_STATE_FILE")"
        echo '{"accounts":{},"currentAccount":"","lastScan":""}' > "$KEEPALIVE_STATE_FILE"
    fi
}

# Read state file
# Output format: One suffix per line
read_keepalive_state() {
    if [[ ! -f "$KEEPALIVE_STATE_FILE" ]]; then
        # File does not exist, return empty
        return 0
    fi

    # Extract all account keys
    jq -r '.accounts | keys[]' "$KEEPALIVE_STATE_FILE" 2>/dev/null || true
}

# Update state file (V5 version)
# Parameter: scan result (line format: email_suffix|file_suffix)
# V5 changes: Properly handle "current" account
update_keepalive_state() {
    local scan_result="$1"

    local accounts_json="{}"

    # Build JSON object for each account
    while IFS='|' read -r email_suffix file_suffix; do
        [[ -z "$email_suffix" ]] && continue

        # Get account info
        local account_info=$(get_account_info "$email_suffix")
        local email=$(echo "$account_info" | jq -r '.email // ""' 2>/dev/null)

        # Build container name (V5: current account uses gbox-keepalive-current)
        local container_name
        if [[ "$file_suffix" == "current" ]]; then
            container_name="gbox-keepalive-current"
        else
            container_name="gbox-keepalive-${file_suffix}"
        fi

        local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Get limit time (extract from file_suffix)
        local limit_time=""
        if [[ "$file_suffix" != "current" ]]; then
            limit_time=$(get_account_limit_time "$file_suffix")
        fi

        # Determine if it is current account
        local is_current=false
        if [[ "$email_suffix" == "current" ]]; then
            is_current=true
        fi

        # Update JSON
        accounts_json=$(echo "$accounts_json" | jq \
            --arg suffix "$email_suffix" \
            --arg email "$email" \
            --arg container "$container_name" \
            --arg limit "$limit_time" \
            --argjson isCurrent "$is_current" \
            --arg now "$now" \
            '.[$suffix] = {
                email: $email,
                containerName: $container,
                limitTime: (if $limit != "" then $limit else null end),
                isCurrent: $isCurrent,
                lastUpdate: $now
            }' 2>/dev/null)
    done <<< "$scan_result"

    # Write to state file
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -n \
        --argjson accounts "$accounts_json" \
        --arg current "current" \
        --arg lastScan "$now" \
        '{
            accounts: $accounts,
            currentAccount: $current,
            lastScan: $lastScan
        }' > "$KEEPALIVE_STATE_FILE" 2>/dev/null
}

# Compare account lists - Find added accounts
compare_accounts_added() {
    local current="$1"
    local previous="$2"

    # Use comm command to find differences
    comm -23 <(echo "$current" | sort) <(echo "$previous" | sort)
}

# Compare account lists - Find logged out accounts
compare_accounts_removed() {
    local current="$1"
    local previous="$2"

    # comm -13: Lines only in the second file (logged out accounts)
    comm -13 <(echo "$current" | sort) <(echo "$previous" | sort)
}

# Compare account lists - Find unchanged accounts
compare_accounts_unchanged() {
    local current="$1"
    local previous="$2"

    # comm -12: Lines in both files (unchanged accounts)
    comm -12 <(echo "$current" | sort) <(echo "$previous" | sort)
}

# Start keepalive container for account (V5 version)
# V5 core changes: Each container independently mounts config files to fixed paths
start_keepalive_for_account() {
    local email_suffix="$1"
    local file_suffix="$2"  # May be the same as email_suffix or with limitTime
    local quiet_mode="${3:-0}"

    local container_name
    local claude_file
    local cred_file

    # Determine container name and file paths
    if [[ "$file_suffix" == "current" ]]; then
        container_name="gbox-keepalive-current"
        claude_file="$GBOX_CLAUDE_DIR/.claude.json"
        cred_file="$GBOX_CLAUDE_DIR/.credentials.json"
    else
        container_name="gbox-keepalive-${file_suffix}"
        claude_file="$GBOX_CLAUDE_DIR/.claude-${file_suffix}.json"
        cred_file="$GBOX_CLAUDE_DIR/.credentials-${file_suffix}.json"
    fi

    # Check if files exist and are valid
    # Note: Docker bind mount creates empty directory when source file doesn't exist, need strict check
    if [[ ! -f "$cred_file" ]] || [[ -d "$cred_file" ]] || [[ ! -s "$cred_file" ]]; then
        if (( quiet_mode == 0 )); then
            echo -e "${RED}Error: credentials file does not exist or is invalid: $file_suffix${NC}"
            [[ -d "$cred_file" ]] && echo -e "${YELLOW}  Hint: Detected directory instead of file, may be mount leftover, please delete manually${NC}"
        fi
        return 1
    fi

    if [[ ! -f "$claude_file" ]] || [[ -d "$claude_file" ]] || [[ ! -s "$claude_file" ]]; then
        if (( quiet_mode == 0 )); then
            echo -e "${RED}Error: .claude.json file does not exist or is invalid: $file_suffix${NC}"
            [[ -d "$claude_file" ]] && echo -e "${YELLOW}  Hint: Detected directory instead of file, may be mount leftover, please delete manually${NC}"
        fi
        return 1
    fi

    # Check if container is already running
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        if (( quiet_mode == 0 )); then
            echo -e "${GREEN}✓ Container is already running: $container_name${NC}"
        fi
        return 0
    fi

    # Check if container exists but is stopped
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        # Delete and recreate (ensure mounts are up to date)
        if (( quiet_mode == 0 )); then
            echo -e "${YELLOW}Container exists but not running, deleting and recreating...${NC}"
        fi
        docker rm -f "$container_name" >/dev/null 2>&1
    fi

    # Create and start container
    if (( quiet_mode == 0 )); then
        echo -e "${GREEN}Creating keepalive container: $container_name${NC}"
    fi

    # Get host HOME path (consistent with main container)
    local host_home="$HOME"
    local container_claude_dir="${host_home}/.claude"

    docker run -d \
        --rm \
        --name "$container_name" \
        --network host \
        -v "$claude_file:${container_claude_dir}/.claude.json:ro" \
        -v "$cred_file:${container_claude_dir}/.credentials.json:rw" \
        -e HOME="$host_home" \
        -e KEEPALIVE_INTERVAL="${KEEPALIVE_INTERVAL:-3600}" \
        "$DOCKER_IMAGE" \
        bash -c '
            KEEPALIVE_INTERVAL=${KEEPALIVE_INTERVAL:-3600}

            echo "[$(date "+%Y-%m-%d %H:%M:%S")] Keepalive container started"

            while true; do
                # V5: Check if both config files exist
                if [[ ! -f "$HOME/.claude/.credentials.json" ]] || [[ ! -f "$HOME/.claude/.claude.json" ]]; then
                    echo "[$(date "+%Y-%m-%d %H:%M:%S")] Config files do not exist, exiting"
                    if [[ ! -f "$HOME/.claude/.credentials.json" ]]; then
                        echo "  - credentials.json: missing"
                    fi
                    if [[ ! -f "$HOME/.claude/.claude.json" ]]; then
                        echo "  - .claude.json: missing"
                    fi
                    exit 0
                fi

                echo "[$(date "+%Y-%m-%d %H:%M:%S")] Executing keepalive..."

                # Execute claude command and capture output
                output=$(claude -p "who are you" 2>&1)
                exit_code=$?

                # V5: Detection module based on output content
                should_exit=0
                exit_reason=""

                if [[ $exit_code -eq 0 ]]; then
                    echo "[$(date "+%Y-%m-%d %H:%M:%S")] Token is valid"
                    echo "[$(date "+%Y-%m-%d %H:%M:%S")] Output: $output"
                else
                    echo "[$(date "+%Y-%m-%d %H:%M:%S")] Execution failed (exit code: $exit_code)"
                    echo "[$(date "+%Y-%m-%d %H:%M:%S")] Output: $output"

                    # Detection module: Analyze output content to determine if exit is needed

                    # 1. HTTP error code detection
                    if echo "$output" | grep -qE "(403|401|404)"; then
                        should_exit=1
                        exit_reason="HTTP error - Token invalid or revoked"

                    # 2. Authentication failure detection
                    elif echo "$output" | grep -qi "Invalid API key"; then
                        should_exit=1
                        exit_reason="Invalid API key - Token expired or corrupted"

                    elif echo "$output" | grep -qi "Please run /login"; then
                        should_exit=1
                        exit_reason="Need to re-login - Token invalidated"

                    elif echo "$output" | grep -qi "authentication failed"; then
                        should_exit=1
                        exit_reason="Authentication failed"

                    # 3. Account limit detection
                    elif echo "$output" | grep -qi "rate limit"; then
                        should_exit=0  # Do not exit on rate limit, continue trying
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] Rate limit detected, continuing to wait..."

                    elif echo "$output" | grep -qi "weekly limit"; then
                        should_exit=0  # Do not exit on weekly limit, continue trying
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] Weekly limit detected, continuing to wait..."

                    # 4. Network error detection (retryable)
                    elif echo "$output" | grep -qiE "(connection refused|connection timeout|network error|failed to connect)"; then
                        should_exit=0  # Do not exit on network issues, continue trying
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] Network issue detected, continuing to try..."

                    # 5. Configuration error detection
                    elif echo "$output" | grep -qi "configuration error"; then
                        should_exit=1
                        exit_reason="Configuration error"

                    # 6. Other unknown errors
                    else
                        should_exit=0  # Default do not exit, continue trying
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] Unknown error, continuing to try..."
                    fi

                    # Decide whether to exit based on detection result
                    if [[ $should_exit -eq 1 ]]; then
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] ❌ Fatal error detected: $exit_reason"
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] Container exiting"
                        exit 1
                    fi
                fi

                sleep "$KEEPALIVE_INTERVAL"
            done
        ' >/dev/null 2>&1

    # Verify if container started successfully
    sleep 1
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        if (( quiet_mode == 0 )); then
            echo -e "${GREEN}✓ Keepalive container started${NC}"
        fi
        return 0
    else
        if (( quiet_mode == 0 )); then
            echo -e "${RED}✗ Keepalive container failed to start${NC}"
        fi
        return 1
    fi
}

# Stop keepalive container for account (V5 version)
stop_keepalive_for_account() {
    local suffix_input="$1"
    local quiet_mode="${2:-0}"

    # Try to get container name from state file
    local container_name=""
    if [[ -f "$KEEPALIVE_STATE_FILE" ]]; then
        container_name=$(jq -r ".accounts.\"$suffix_input\".containerName // empty" "$KEEPALIVE_STATE_FILE" 2>/dev/null)
    fi

    # If not found in state file, try to build container name based on suffix_input
    if [[ -z "$container_name" ]]; then
        if [[ "$suffix_input" == "current" ]]; then
            container_name="gbox-keepalive-current"
        else
            container_name="gbox-keepalive-${suffix_input}"
        fi
    fi

    if ! docker ps -q -f name="^${container_name}$" > /dev/null 2>&1; then
        # Container not running, check if stopped container exists
        if docker ps -a -q -f name="^${container_name}$" > /dev/null 2>&1; then
            docker rm "$container_name" >/dev/null 2>&1
        fi
        return 0
    fi

    docker stop "$container_name" >/dev/null 2>&1
    docker rm "$container_name" >/dev/null 2>&1

    if (( quiet_mode == 0 )); then
        echo -e "${GREEN}✓ Keepalive stopped: $container_name${NC}"
    fi

    return 0
}

# Keepalive Auto main process
keepalive_auto() {
    local quiet_mode="${1:-0}"

    if (( quiet_mode == 0 )); then
        echo -e "${GREEN}=== Keepalive Auto Management ===${NC}"
    fi

    # Initialize state file
    init_keepalive_state

    # 1. Scan all currently logged-in accounts (format: email_suffix|file_suffix)
    local scan_result=$(scan_logged_accounts)

    # 2. Extract email_suffix list for comparison
    local current_accounts=$(get_unique_email_suffixes "$scan_result")

    # 3. Read previously recorded account list
    local previous_accounts=$(read_keepalive_state)

    # 4. Compare differences
    local added_accounts=$(compare_accounts_added "$current_accounts" "$previous_accounts")
    local removed_accounts=$(compare_accounts_removed "$current_accounts" "$previous_accounts")
    local unchanged_accounts=$(compare_accounts_unchanged "$current_accounts" "$previous_accounts")

    if (( quiet_mode == 0 )); then
        local added_count=$(echo "$added_accounts" | grep -c '.' || echo "0")
        local removed_count=$(echo "$removed_accounts" | grep -c '.' || echo "0")
        local unchanged_count=$(echo "$unchanged_accounts" | grep -c '.' || echo "0")
        echo "✓ Added accounts: $added_count"
        echo "✓ Logged out accounts: $removed_count"
        echo "✓ Unchanged accounts: $unchanged_count"
        echo ""
    fi

    # 5. Handle added accounts - Start keepalive (V5: need to get file_suffix from scan_result)
    local started_count=0
    while IFS='|' read -r email_suffix file_suffix; do
        [[ -z "$email_suffix" ]] && continue

        # Check if in added_accounts
        if echo "$added_accounts" | grep -q "^${email_suffix}$"; then
            if (( quiet_mode == 0 )); then
                echo "  → Added account, starting keepalive: $file_suffix"
            fi

            if start_keepalive_for_account "$email_suffix" "$file_suffix" "1"; then
                ((started_count++))
            fi
        fi
    done <<< "$scan_result"

    # 6. Handle logged out accounts - Stop keepalive
    local stopped_count=0
    while IFS= read -r suffix; do
        [[ -z "$suffix" ]] && continue
        if (( quiet_mode == 0 )); then
            echo "  → Logged out account, stopping keepalive: $suffix"
        fi

        if stop_keepalive_for_account "$suffix" "1"; then
            ((stopped_count++))
        fi
    done <<< "$removed_accounts"

    # 7. Handle unchanged accounts - Ensure keepalive containers are running (V5: need to get file_suffix from scan_result)
    local checked_count=0
    local restarted_count=0
    while IFS='|' read -r email_suffix file_suffix; do
        [[ -z "$email_suffix" ]] && continue

        # Check if in unchanged_accounts
        if echo "$unchanged_accounts" | grep -q "^${email_suffix}$"; then
            local container_name
            if [[ "$file_suffix" == "current" ]]; then
                container_name="gbox-keepalive-current"
            else
                container_name="gbox-keepalive-${file_suffix}"
            fi

            if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
                ((checked_count++))
            else
                if (( quiet_mode == 0 )); then
                    echo "  → Unchanged account, container abnormal, restarting: $file_suffix"
                fi

                if start_keepalive_for_account "$email_suffix" "$file_suffix" "1"; then
                    ((restarted_count++))
                fi
            fi
        fi
    done <<< "$scan_result"

    # 8. Update state config file (pass complete scan result)
    update_keepalive_state "$scan_result"

    # 9. Output result
    if (( quiet_mode == 0 )); then
        echo ""
        echo -e "${GREEN}Completed:${NC}"
        echo "  - Newly started: $started_count"
        echo "  - Stopped: $stopped_count"
        echo "  - Kept running: $checked_count"
        if (( restarted_count > 0 )); then
            echo "  - Restarted: $restarted_count"
        fi
    fi
}

# Keepalive status display
keepalive_status() {
    echo -e "${GREEN}=== Keepalive Status ===${NC}"
    echo ""

    # Read state file
    if [[ ! -f "$KEEPALIVE_STATE_FILE" ]]; then
        echo -e "${YELLOW}State file does not exist${NC}"
        echo ""
        echo -e "${BLUE}Hint: Run 'gbox keepalive auto' to initialize${NC}"
        return 0
    fi

    # Display state file information
    local last_scan=$(jq -r '.lastScan // ""' "$KEEPALIVE_STATE_FILE" 2>/dev/null)
    echo -e "Last scan: ${BLUE}$last_scan${NC}"
    echo ""

    # Display all accounts
    local accounts=$(jq -r '.accounts | keys[]' "$KEEPALIVE_STATE_FILE" 2>/dev/null)

    if [[ -z "$accounts" ]]; then
        echo -e "${YELLOW}No logged in accounts${NC}"
        return 0
    fi

    echo -e "${GREEN}Logged in accounts:${NC}"

    while IFS= read -r suffix; do
        [[ -z "$suffix" ]] && continue

        local email=$(jq -r ".accounts.\"$suffix\".email // \"\"" "$KEEPALIVE_STATE_FILE" 2>/dev/null)
        local container_name=$(jq -r ".accounts.\"$suffix\".containerName // \"\"" "$KEEPALIVE_STATE_FILE" 2>/dev/null)
        local limit_time=$(jq -r ".accounts.\"$suffix\".limitTime // \"\"" "$KEEPALIVE_STATE_FILE" 2>/dev/null)
        local is_current=$(jq -r ".accounts.\"$suffix\".isCurrent // false" "$KEEPALIVE_STATE_FILE" 2>/dev/null)

        # Check container status
        local container_id=$(docker ps -q -f name="^${container_name}$" 2>/dev/null)

        if [[ -n "$container_id" ]]; then
            # Container is running
            local uptime=$(docker ps --format "{{.Status}}" -f name="^${container_name}$" 2>/dev/null)
            echo -e "  ✓ ${BLUE}$email${NC} (${GREEN}Running${NC}, $uptime)"
            if [[ "$is_current" == "true" ]]; then
                echo -e "    ${YELLOW}[Current account]${NC}"
            fi
            if [[ -n "$limit_time" && "$limit_time" != "null" ]]; then
                echo -e "    Limit time: $limit_time"
            fi
        else
            # Container not running
            echo -e "  ✗ ${BLUE}$email${NC} (${RED}Not running${NC})"
            if [[ "$is_current" == "true" ]]; then
                echo -e "    ${YELLOW}[Current account]${NC}"
            fi
            if [[ -n "$limit_time" && "$limit_time" != "null" ]]; then
                echo -e "    Limit time: $limit_time"
            fi
        fi
    done <<< "$accounts"
}

# Stop all keepalive containers
keepalive_stop_all() {
    echo -e "${GREEN}=== Stop All Keepalive Containers ===${NC}"
    echo ""

    # Find all keepalive containers
    local containers=$(docker ps -a --filter "name=^gbox-keepalive-" --format "{{.Names}}" 2>/dev/null)

    if [[ -z "$containers" ]]; then
        echo -e "${YELLOW}No keepalive containers found${NC}"
        return 0
    fi

    local count=0
    while IFS= read -r container; do
        [[ -z "$container" ]] && continue
        echo "  → Stopping: $container"
        docker stop "$container" >/dev/null 2>&1
        docker rm "$container" >/dev/null 2>&1
        ((count++))
    done <<< "$containers"

    echo ""
    echo -e "${GREEN}Completed: Stopped $count containers${NC}"

    # Clear state file
    if [[ -f "$KEEPALIVE_STATE_FILE" ]]; then
        echo '{"accounts":{},"currentAccount":"","lastScan":""}' > "$KEEPALIVE_STATE_FILE"
        echo -e "${BLUE}State file reset${NC}"
    fi
}

# View keepalive container logs (V5 version)
keepalive_logs() {
    local suffix_input="$1"

    if [[ -z "$suffix_input" ]]; then
        echo -e "${RED}Error: Please specify account suffix${NC}"
        echo -e "${YELLOW}Usage: gbox keepalive logs <suffix>${NC}"
        echo -e "${YELLOW}Examples:${NC}"
        echo -e "${YELLOW}  - Current account: gbox keepalive logs current${NC}"
        echo -e "${YELLOW}  - Backup account: gbox keepalive logs agent-at-gravtice-com-2025120115${NC}"
        return 1
    fi

    # Query state file to get container name
    if [[ ! -f "$KEEPALIVE_STATE_FILE" ]]; then
        echo -e "${RED}Error: State file does not exist${NC}"
        echo -e "${YELLOW}Hint: Run 'gbox keepalive auto' to initialize${NC}"
        return 1
    fi

    # Find container name from state file
    local container_name=$(jq -r ".accounts.\"$suffix_input\".containerName // empty" "$KEEPALIVE_STATE_FILE" 2>/dev/null)

    if [[ -z "$container_name" ]]; then
        echo -e "${RED}Error: Account not found: $suffix_input${NC}"
        echo ""
        echo -e "${YELLOW}Hint: Use 'gbox keepalive status' to view all accounts${NC}"
        return 1
    fi

    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${RED}Error: Container does not exist: $container_name${NC}"
        echo ""
        echo -e "${YELLOW}Hint: Use 'gbox keepalive status' to view all accounts${NC}"
        return 1
    fi

    echo -e "${GREEN}Displaying container logs: ${container_name}${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit${NC}"
    echo ""

    docker logs -f "$container_name"
}

# Keepalive container management command handler
function handle_keepalive_command() {
    local subcommand="${1:-help}"
    shift || true

    case "$subcommand" in
        auto)
            keepalive_auto "0"
            ;;
        status)
            keepalive_status
            ;;
        stop)
            local account="$1"
            if [[ -z "$account" ]]; then
                echo -e "${RED}Error: Please specify account suffix${NC}"
                echo -e "${YELLOW}Usage: gbox keepalive stop <suffix>${NC}"
                echo -e "${YELLOW}Examples:${NC}"
                echo -e "${YELLOW}  - Current account: gbox keepalive stop current${NC}"
                echo -e "${YELLOW}  - Backup account: gbox keepalive stop agent-at-gravtice-com-2025120115${NC}"
                exit 1
            fi
            stop_keepalive_for_account "$account" "0"
            ;;
        stop-all)
            keepalive_stop_all
            ;;
        logs)
            keepalive_logs "$1"
            ;;
        help|--help|-h)
            cat <<EOF
${GREEN}gbox keepalive - OAuth Session Maintenance Management${NC}

${YELLOW}Usage:${NC}
    gbox keepalive auto                      Automatically manage keepalive for all accounts
    gbox keepalive status                    View keepalive status
    gbox keepalive stop <suffix>             Stop keepalive for specified account
                                             Examples: stop current or stop agent-at-gravtice-com-2025120115
    gbox keepalive stop-all                  Stop all keepalive
    gbox keepalive logs <suffix>             View keepalive logs
                                             Examples: logs current or logs agent-at-gravtice-com-2025120115
    gbox keepalive help                      Display this help information

${YELLOW}What is Keepalive?${NC}
    Keepalive is an automated OAuth token maintenance system that periodically executes
    'claude -p "who"' in background containers to keep account sessions from expiring.

${YELLOW}Core Features:${NC}
    • Automatically detect account changes (login/logout/switch)
    • Start independent keepalive container for each account
    • State persistence, supports system restart
    • Intelligently handle account limit times

${YELLOW}Container Naming Convention:${NC}
    gbox-keepalive-<email-suffix>

    Examples:
    • gbox-keepalive-agent-at-gravtice-com
    • gbox-keepalive-team-at-gravtice-com

${YELLOW}Examples:${NC}
    gbox keepalive auto                      # Auto manage (recommended)
    gbox keepalive status                    # View status
    gbox keepalive stop agent-at-gravtice-com  # Stop specific account
    gbox keepalive stop-all                  # Stop all
    gbox keepalive logs agent-at-gravtice-com  # View logs

${YELLOW}Auto Trigger Timing:${NC}
    • Before and after gbox claude execution
    • After gbox oauth claude switch execution
    • First gbox command execution after system restart

${YELLOW}Notes:${NC}
    • Keepalive containers have very low resource usage
    • Container automatically exits when token is invalid (403)
    • Container automatically stops when account logs out
    • You can manually stop unwanted keepalive
EOF
            ;;
        *)
            echo -e "${RED}Error: Unknown subcommand '$subcommand'${NC}"
            echo ""
            echo -e "${YELLOW}Available subcommands:${NC}"
            echo -e "  auto        Automatically manage all accounts"
            echo -e "  status      View status"
            echo -e "  stop        Stop specified account"
            echo -e "  stop-all    Stop all"
            echo -e "  logs        View logs"
            echo -e "  help        Display help"
            echo ""
            echo -e "${YELLOW}Use 'gbox keepalive help' for detailed information${NC}"
            exit 1
            ;;
    esac
}
