#!/bin/bash
# Copyright 2024-2025 Gravtice
# SPDX-License-Identifier: Apache-2.0
#
# lib/oauth.sh - OAuth account management module
# Responsible for email parsing, account finding, limit parsing, account switching, and command routing (depends on directory and color constants provided by lib/common.sh)

# ============================================
# Email Parsing
# ============================================
# Extract email address from .claude.json and convert to filename-safe format
function extract_email_safe() {
    local claude_json="$GBOX_CLAUDE_DIR/.claude.json"

    if [[ ! -f "$claude_json" ]]; then
        echo ""
        return 1
    fi

    # Try to extract from emailAddress field
    local email=$(jq -r '.oauthAccount.emailAddress // empty' "$claude_json" 2>/dev/null)

    if [[ -z "$email" ]]; then
        # Try other possible fields
        email=$(jq -r '.oauthAccount.Email // .Email // .email // .emailAddress // empty' "$claude_json" 2>/dev/null)
    fi

    if [[ -n "$email" ]]; then
        # Convert email address to filename-safe format
        # 1. Convert to lowercase
        # 2. Replace @ with -at-
        # 3. Replace . with -
        # 4. Replace other special characters with -
        local safe_email=$(echo "$email" | tr '[:upper:]' '[:lower:]' | sed 's/@/-at-/g' | sed 's/\./-/g' | sed 's/[^a-z0-9-]/-/g')
        echo "$safe_email"
        return 0
    fi

    echo ""
    return 1
}

# ============================================
# Account Finding and Token Status
# ============================================
# Find available account configuration files (V5 version - uses .claude-*.json)
# Parameter: current_account (optional, current account to exclude)
# Return format: account suffix (e.g., user-at-example-com or user-at-example-com-2025110611)
# Priority:
#   1. Unlimited + token not expired (best: unlimited and immediately available)
#   2. Limit lifted + token not expired (good: immediately available)
#   3. Unlimited + token expired (needs re-authentication but unlimited)
#   4. Limit lifted + token expired (needs re-authentication)
function find_available_account() {
    local current_account="${1:-}"
    local current_datetime=$(date +%Y%m%d%H)

    # Candidate account array
    # Format: "priority:suffix:token_status"
    local candidates=()

    # Step 1: Collect unlimited accounts (without date suffix)
    for file in "$GBOX_CLAUDE_DIR"/.claude-*.json; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file")
            # Check if it does not contain date suffix (format: .claude-prefix.json)
            # Exclude filenames ending with 10 digits (date format: YYYYMMDDHH)
            if [[ "$basename" =~ ^\.claude-[a-z0-9_-]+\.json$ ]] && [[ ! "$basename" =~ -[0-9]{10}\.json$ ]]; then
                # Extract prefix: .claude-{prefix}.json -> {prefix}
                local prefix="${basename#.claude-}"
                prefix="${prefix%.json}"

                # Exclude current account
                if [[ -n "$current_account" && "$prefix" == "$current_account" ]]; then
                    continue
                fi

                # Verify if corresponding credentials file exists
                if [[ -f "$GBOX_CLAUDE_DIR/.credentials-$prefix.json" ]]; then
                    # Check if token is expired
                    local token_status=$(check_token_expiry "$GBOX_CLAUDE_DIR/.credentials-$prefix.json")

                    if [[ "$token_status" =~ ^valid: ]]; then
                        # Priority 1: Unlimited + token not expired
                        candidates+=("1:$prefix:valid")
                    else
                        # Priority 3: Unlimited + token expired
                        candidates+=("3:$prefix:expired")
                    fi
                fi
            fi
        fi
    done

    # Step 2: Collect accounts with lifted limit (date suffix expired)
    for file in "$GBOX_CLAUDE_DIR"/.claude-*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].json; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file")
            # Extract date part: .claude-prefix-2025110611.json -> 2025110611
            local date_part="${basename##*-}"
            date_part="${date_part%.json}"

            # Check if the date/time is expired or reached
            # Use <= instead of <, because once the limit time is reached it can be used
            # Example: limit until 2025110511 (11am), so 11am sharp can be used
            if [[ "$date_part" -le "$current_datetime" ]]; then
                # Extract full suffix: .claude-{prefix-YYYYMMDDHH}.json -> prefix-YYYYMMDDHH
                local suffix="${basename#.claude-}"
                suffix="${suffix%.json}"

                # Exclude current account
                if [[ -n "$current_account" && "$suffix" == "$current_account" ]]; then
                    continue
                fi

                # Verify if corresponding credentials file exists
                if [[ -f "$GBOX_CLAUDE_DIR/.credentials-$suffix.json" ]]; then
                    # Check if token is expired
                    local token_status=$(check_token_expiry "$GBOX_CLAUDE_DIR/.credentials-$suffix.json")

                    if [[ "$token_status" =~ ^valid: ]]; then
                        # Priority 2: Limit lifted + token not expired
                        candidates+=("2:$suffix:valid")
                    else
                        # Priority 4: Limit lifted + token expired
                        candidates+=("4:$suffix:expired")
                    fi
                fi
            fi
        fi
    done

    # Step 3: If there are candidate accounts, sort by priority and return the first one
    if [[ ${#candidates[@]} -gt 0 ]]; then
        # Sort by priority number (1 < 2 < 3 < 4)
        local sorted=($(printf '%s\n' "${candidates[@]}" | sort -t: -k1,1n))
        local best="${sorted[0]}"

        # Extract suffix part
        local suffix=$(echo "$best" | cut -d: -f2)
        local token_state=$(echo "$best" | cut -d: -f3)

        # Output diagnostic information to stderr (does not affect function return value)
        local priority=$(echo "$best" | cut -d: -f1)
        case "$priority" in
            1) echo "  (Priority 1/4: Unlimited account, Token valid)" >&2 ;;
            2) echo "  (Priority 2/4: Limit lifted, Token valid)" >&2 ;;
            3) echo "  (Priority 3/4: Unlimited account, Token expired)" >&2 ;;
            4) echo "  (Priority 4/4: Limit lifted, Token expired)" >&2 ;;
        esac

        echo "$suffix"
        return 0
    fi

    # No available account found
    return 1
}

# Check if token is expired
# Parameter: credentials.json file path
# Return: "valid:remaining_hours" | "expired:expired_hours" | "unknown" | "missing"
function check_token_expiry() {
    local credentials_file="$1"

    if [[ ! -f "$credentials_file" ]]; then
        echo "missing"
        return
    fi

    local expires_at=$(jq -r '.claudeAiOauth.expiresAt // empty' "$credentials_file" 2>/dev/null)
    if [[ -z "$expires_at" ]]; then
        echo "unknown"
        return
    fi

    local current_time=$(($(date +%s) * 1000))

    if [[ $current_time -gt $expires_at ]]; then
        local expired_hours=$(( ($current_time - $expires_at) / 1000 / 3600 ))
        echo "expired:$expired_hours"
    else
        local remaining_hours=$(( ($expires_at - $current_time) / 1000 / 3600 ))
        echo "valid:$remaining_hours"
    fi
}

# ============================================
# Limit Parsing
# ============================================
# OAuth switch subcommand (new version - only switch OAuth field)
# Parse limit string, extract time and convert to YYYYMMDDHH format
# Parameter: limit_str - limit string, e.g., "Weekly limit reached ∙ resets Nov 9, 5pm"
# Return: time string in YYYYMMDDHH format, empty on failure
function parse_limit_str() {
    local limit_str="$1"

    # Extract month, day, and time
    # Supported formats: "resets Nov 9, 5pm" or "resets Nov 9, 5:00pm"
    if [[ "$limit_str" =~ resets[[:space:]]+([A-Za-z]+)[[:space:]]+([0-9]+),[[:space:]]+([0-9]+):?([0-9]+)?(am|pm) ]]; then
        local month_str="${BASH_REMATCH[1]}"
        local day="${BASH_REMATCH[2]}"
        local hour="${BASH_REMATCH[3]}"
        local minute="${BASH_REMATCH[4]}"
        local ampm="${BASH_REMATCH[5]}"

        # Convert month name to number
        local month=""
        local month_lower=$(echo "$month_str" | tr '[:upper:]' '[:lower:]')
        case "$month_lower" in
            jan|january) month="01" ;;
            feb|february) month="02" ;;
            mar|march) month="03" ;;
            apr|april) month="04" ;;
            may) month="05" ;;
            jun|june) month="06" ;;
            jul|july) month="07" ;;
            aug|august) month="08" ;;
            sep|september) month="09" ;;
            oct|october) month="10" ;;
            nov|november) month="11" ;;
            dec|december) month="12" ;;
            *) return 1 ;;
        esac

        # Convert 12-hour format to 24-hour format
        if [[ "$ampm" == "pm" ]] && [[ "$hour" != "12" ]]; then
            hour=$((hour + 12))
        elif [[ "$ampm" == "am" ]] && [[ "$hour" == "12" ]]; then
            hour="00"
        fi

        # Pad to two digits
        day=$(printf "%02d" "$day")
        hour=$(printf "%02d" "$hour")

        # Determine year (if month is less than current month, use next year)
        local current_year=$(date +%Y)
        local current_month=$(date +%m)
        local year="$current_year"

        if [[ "$month" -lt "$current_month" ]]; then
            year=$((current_year + 1))
        fi

        # Return YYYYMMDDHH format
        echo "${year}${month}${day}${hour}"
        return 0
    fi

    return 1
}

# ============================================
# Account Switching
# ============================================
function oauth_switch() {
    local limit_param=""

    # Parse parameters
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit)
                shift
                if [[ $# -eq 0 ]]; then
                    echo -e "${RED}Error: --limit requires an argument${NC}"
                    exit 1
                fi
                limit_param="$1"

                # Validate format: must be 10 digits (YYYYMMDDHH)
                if [[ ! "$limit_param" =~ ^[0-9]{10}$ ]]; then
                    echo -e "${RED}Error: --limit argument format is incorrect${NC}"
                    echo -e "${YELLOW}Expected format: YYYYMMDDHH (10 digits)${NC}"
                    echo -e "${YELLOW}Example: 2025120111 (represents 2025 Dec 01 11am)${NC}"
                    echo -e "${YELLOW}You entered: $limit_param${NC}"
                    exit 1
                fi

                shift
                ;;
            --limit-str)
                shift
                if [[ $# -eq 0 ]]; then
                    echo -e "${RED}Error: --limit-str requires an argument${NC}"
                    exit 1
                fi
                local limit_str="$1"
                echo -e "${BLUE}Parsing limit string: $limit_str${NC}"

                limit_param=$(parse_limit_str "$limit_str")
                if [[ -z "$limit_param" ]]; then
                    echo -e "${RED}Error: Unable to parse limit string${NC}"
                    echo -e "${YELLOW}Expected format: 'Weekly limit reached ∙ resets Nov 9, 5pm'${NC}"
                    echo -e "${YELLOW}You entered: $limit_str${NC}"
                    exit 1
                fi

                echo -e "${GREEN}✓ Parse successful: $limit_param${NC}"
                shift
                ;;
            *)
                echo -e "${RED}Error: Unknown argument '$1'${NC}"
                echo -e "${YELLOW}Usage: gbox oauth claude switch [--limit YYYYMMDDHH] [--limit-str STRING]${NC}"
                exit 1
                ;;
        esac
    done

    echo -e "${GREEN}OAuth Account Switching (Smart Config Retention)${NC}"
    echo ""

    # Check if current config file exists
    local claude_json="$GBOX_CLAUDE_DIR/.claude.json"
    local credentials_json="$GBOX_CLAUDE_DIR/.credentials.json"

    if [[ ! -f "$claude_json" ]]; then
        echo -e "${YELLOW}Warning: No Claude config file currently${NC}"
        echo -e "${YELLOW}Will search for available accounts directly...${NC}"
        echo ""
        local backup_suffix=""
        local email_safe=""
    else
        # Extract current account email (filename-safe format)
        local email_safe=$(extract_email_safe)

        if [[ -z "$email_safe" ]]; then
            echo -e "${YELLOW}Warning: Unable to extract email from config file${NC}"
            # Use timestamp as backup suffix
            email_safe="backup-$(date +%Y%m%d%H%M%S)"
        fi

        echo -e "${BLUE}Current account: ${email_safe}${NC}"

        # Determine backup filename
        local backup_suffix="$email_safe"
        if [[ -n "$limit_param" ]]; then
            # Extract date part (YYYYMMDDHH)
            local date_part="${limit_param:0:10}"
            backup_suffix="${email_safe}-${date_part}"
            echo -e "${YELLOW}Limit date: ${date_part} (${limit_param})${NC}"
        fi

        echo -e "${BLUE}Backup suffix: ${backup_suffix}${NC}"
        echo ""

        # V5: Backup complete config (including oauthAccount)
        echo -e "${YELLOW}Backing up current account config...${NC}"

        # Backup complete .claude.json (including oauthAccount)
        local claude_backup="$GBOX_CLAUDE_DIR/.claude-${backup_suffix}.json"
        cp "$claude_json" "$claude_backup"
        echo -e "${GREEN}✓ Config backed up: .claude-${backup_suffix}.json${NC}"

        # Backup credentials.json (complete file)
        if [[ -f "$credentials_json" ]]; then
            cp "$credentials_json" "$GBOX_CLAUDE_DIR/.credentials-${backup_suffix}.json"
            echo -e "${GREEN}✓ Token backed up: .credentials-${backup_suffix}.json${NC}"
        fi

        echo ""
    fi

    # Find available account (exclude current account)
    echo -e "${YELLOW}Finding available accounts...${NC}"
    local available_account=$(find_available_account "$backup_suffix")

    if [[ -z "$available_account" ]]; then
        echo -e "${RED}Error: No available accounts found${NC}"
        echo ""
        echo -e "${YELLOW}Available account rules:${NC}"
        echo -e "  1. Unlimited account: .claude-{email-safe}.json"
        echo -e "  2. Limit expired: .claude-{email-safe}-{YYYYMMDDHH}.json (date/time has passed)"
        echo -e "  email-safe example: team-at-gravtice-com"
        echo ""
        echo -e "${BLUE}Hint: Please check the ${GBOX_CLAUDE_DIR} directory${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Found available account: ${available_account}${NC}"
    echo ""

    # V5: Switch account (only replace oauthAccount field, keep other configs)
    echo -e "${YELLOW}Switching OAuth account (preserving other configs)...${NC}"

    local claude_source="$GBOX_CLAUDE_DIR/.claude-${available_account}.json"
    local credentials_source="$GBOX_CLAUDE_DIR/.credentials-${available_account}.json"

    if [[ ! -f "$claude_source" ]]; then
        echo -e "${RED}Error: Config backup file does not exist: $claude_source${NC}"
        exit 1
    fi

    # Restore credentials.json
    if [[ -f "$credentials_source" ]]; then
        cp "$credentials_source" "$credentials_json"
        echo -e "${GREEN}✓ Updated .credentials.json${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: credentials backup file not found, skipping${NC}"
    fi

    # Extract oauthAccount from .claude-{suffix}.json, replace oauthAccount in .claude.json
    jq --argfile oauth_data "$claude_source" \
       '.oauthAccount = $oauth_data.oauthAccount' \
       "$claude_json" > "$claude_json.tmp"
    mv "$claude_json.tmp" "$claude_json"
    echo -e "${GREEN}✓ Updated .claude.json OAuth field (other configs preserved)${NC}"

    echo ""

    # Show token status after recovery
    echo -e "${YELLOW}Token status:${NC}"
    local token_status=$(check_token_expiry "$credentials_json")

    case "$token_status" in
        valid:*)
            local hours="${token_status#valid:}"
            echo -e "${GREEN}✓ Token valid (approx $hours hours remaining)${NC}"
            ;;
        expired:*)
            local hours="${token_status#expired:}"
            echo -e "${YELLOW}⚠ Token expired (expired approx $hours hours ago)${NC}"
            echo -e "${YELLOW}  Next use will require Claude Code re-authentication${NC}"
            ;;
        *)
            echo -e "${YELLOW}⚠ Unable to determine token status${NC}"
            ;;
    esac
    echo ""

    # Delete used backup files
    echo -e "${YELLOW}Cleaning up used account backups...${NC}"
    rm -f "$claude_source"
    echo -e "${GREEN}✓ Deleted: .claude-${available_account}.json${NC}"

    if [[ -f "$credentials_source" ]]; then
        rm -f "$credentials_source"
        echo -e "${GREEN}✓ Deleted: .credentials-${available_account}.json${NC}"
    fi
    echo ""

    echo -e "${GREEN}✓ OAuth account switching complete${NC}"
    echo ""
    echo -e "${BLUE}Switched to account: ${available_account}${NC}"
    echo -e "${GREEN}✓ Preserved: MCP configs, UI settings, history, etc${NC}"
    echo -e "${YELLOW}Hint: New Claude Code session will use this account${NC}"
}

# ============================================
# Command Handling
# ============================================
# OAuth command handler (entry point)
function handle_oauth_command() {
    local agent="${1:-help}"
    shift || true

    case "$agent" in
        claude)
            handle_oauth_claude_command "$@"
            ;;
        help|--help|-h)
            cat <<EOF
${GREEN}gbox oauth - OAuth Account Management${NC}

${YELLOW}Usage:${NC}
    gbox oauth <agent> <subcommand>    Manage OAuth account for specified agent
    gbox oauth help                     Show this help message

${YELLOW}Supported Agents:${NC}
    claude    Claude Code OAuth Management

${YELLOW}Examples:${NC}
    gbox oauth claude switch [--limit YYYYMMDDHH | --limit-str STRING]
                                                       Switch Claude account
    gbox oauth claude status                          Check Claude account status
    gbox oauth claude help                            Show Claude OAuth help

${YELLOW}Details:${NC}
    Use ${GREEN}gbox oauth claude help${NC} to view detailed Claude OAuth management instructions
EOF
            ;;
        *)
            echo -e "${RED}Error: Unknown agent '$agent'${NC}"
            echo ""
            echo -e "${YELLOW}Supported agents:${NC}"
            echo -e "  claude    Claude Code OAuth Management"
            echo ""
            echo -e "${YELLOW}Examples:${NC}"
            echo -e "  gbox oauth claude switch"
            echo -e "  gbox oauth claude status"
            exit 1
            ;;
    esac
}

# OAuth Claude command handler
function handle_oauth_claude_command() {
    local subcommand="${1:-help}"
    shift || true

    case "$subcommand" in
        switch)
            oauth_switch "$@"
            ;;
        status)
            # Check token status of current account
            local credentials_json="$GBOX_CLAUDE_DIR/.credentials.json"
            local claude_json="$GBOX_CLAUDE_DIR/.claude.json"

            echo -e "${GREEN}OAuth Token Status Check${NC}"
            echo ""

            # Get current account email
            local email=$(jq -r '.oauthAccount.emailAddress // .oauthAccount.Email // .Email // .email // .emailAddress // empty' "$claude_json" 2>/dev/null)
            if [[ -n "$email" ]]; then
                echo -e "${BLUE}Current account: ${email}${NC}"
            else
                echo -e "${YELLOW}⚠ Unable to retrieve account email${NC}"
            fi

            # Check token status
            local token_status=$(check_token_expiry "$credentials_json")

            case "$token_status" in
                valid:*)
                    local hours="${token_status#valid:}"
                    local expires_at=$(jq -r '.claudeAiOauth.expiresAt' "$credentials_json" 2>/dev/null)
                    local expire_date=$(date -r $((expires_at / 1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
                    echo -e "${GREEN}✓ Token valid${NC}"
                    echo -e "${BLUE}Remaining time: approx $hours hours${NC}"
                    echo -e "${BLUE}Expiration time: $expire_date${NC}"
                    ;;
                expired:*)
                    local hours="${token_status#expired:}"
                    echo -e "${RED}✗ Token expired${NC}"
                    echo -e "${YELLOW}Expired: approx $hours hours ago${NC}"
                    echo -e "${YELLOW}Recommendation: Run 'claude' command to re-authenticate${NC}"
                    ;;
                unknown)
                    echo -e "${YELLOW}⚠ Unable to determine token status${NC}"
                    echo -e "${YELLOW}Possible reason: credentials.json format anomaly${NC}"
                    ;;
                missing)
                    echo -e "${RED}✗ credentials.json file does not exist${NC}"
                    echo -e "${YELLOW}Recommendation: Run 'claude' command for initial authentication${NC}"
                    ;;
            esac
            echo ""

            # Show backup account information
            local backup_count=$(ls -1 "$GBOX_CLAUDE_DIR"/.oauth-account-*.json 2>/dev/null | wc -l | tr -d ' ')
            if [[ $backup_count -gt 0 ]]; then
                echo -e "${BLUE}Backup account count: $backup_count${NC}"
                echo -e "${YELLOW}Use 'ls -la ~/.gbox/claude/.oauth-account-*.json' for details${NC}"
            else
                echo -e "${YELLOW}No backup accounts currently${NC}"
            fi
            ;;
        help|--help|-h)
            cat <<EOF
${GREEN}gbox oauth claude - Claude OAuth Account Management${NC}

${YELLOW}Usage:${NC}
    gbox oauth claude switch [--limit YYYYMMDDHH | --limit-str STRING]
    gbox oauth claude status
    gbox oauth claude help

${YELLOW}Description:${NC}

    ${BLUE}Account Switching (switch) - Smart Config Retention${NC}
    Supports multi-account management for Claude Code. Switch to another available account when current account reaches usage limit.

    ${GREEN}✨ New Feature: Only switch OAuth info, preserve other configs${NC}
    - ✅ Preserve MCP configs (shared across all containers)
    - ✅ Preserve UI settings (theme, shortcuts, etc)
    - ✅ Preserve usage history and statistics
    - ✅ Only replace OAuth authentication info

    ${YELLOW}Use Cases:${NC}
    1. Account reached limit (specified time): gbox oauth claude switch --limit 2025120111
       - Backup current OAuth as .oauth-account-{email-safe}-2025120111.json
       - Switch to unlimited or limit-lifted account
       - Preserve all other configs (MCP, UI, etc)
       - email-safe: filename-safe format of email (e.g. team-at-gravtice-com)

    2. Account reached limit (auto-parse): gbox oauth claude switch --limit-str "Weekly limit reached ∙ resets Nov 9, 5pm"
       - Auto-extract time from limit message and convert to YYYYMMDDHH format
       - Other behavior same as method 1

    3. Manually switch account: gbox oauth claude switch
       - Backup current OAuth as .oauth-account-{email-safe}.json
       - Switch to unlimited or limit-lifted account
       - Preserve all other configs

    ${YELLOW}Account Selection Priority:${NC}
    1. Prefer unlimited accounts (.oauth-account-{email-safe}.json)
    2. Then use limit-lifted accounts (.oauth-account-{email-safe}-YYYYMMDDHH.json)
    3. Also prefer accounts with valid tokens

    ${YELLOW}Token Management:${NC}
    - Token expiration is automatically checked when switching
    - If token is expired, re-authentication is prompted
    - Token expiration is normal, OAuth tokens need periodic refresh

    ${YELLOW}File Description:${NC}
    - .oauth-account-*.json        OAuth account info (oauthAccount field only)
    - .credentials-*.json          OAuth token (accessToken, refreshToken)
    - .claude.json.backup-*        Complete config backup (for disaster recovery)
    - .claude.json                 Current config (contains OAuth + MCP + UI, etc)

    ${BLUE}Token Status Check (status)${NC}
    Check OAuth token status of current account, including:
    - Currently logged-in account email
    - Token validity and remaining time
    - Number of backup accounts

${YELLOW}Examples:${NC}

    # Check current token status
    gbox oauth claude status

    # Account reached limit, limit reset time is 2025 Dec 01 11am
    gbox oauth claude switch --limit 2025120111
    # Generated backup: .oauth-account-team-at-gravtice-com-2025120111.json

    # Account reached limit, auto-parse from limit string
    gbox oauth claude switch --limit-str "Weekly limit reached ∙ resets Nov 9, 5pm"
    # Auto-parse to 2025110917, generated backup: .oauth-account-team-at-gravtice-com-2025110917.json

    # Manually switch to unlimited account
    gbox oauth claude switch
    # Generated backup: .oauth-account-team-at-gravtice-com.json

    # View OAuth backup accounts
    ls -la ~/.gbox/claude/.oauth-account-*.json

${YELLOW}Config File Location:${NC}
    ${BLUE}${GBOX_CLAUDE_DIR}${NC}

    File Format:
    - .claude.json                          Current config in use
    - .credentials.json                     Current credentials in use
    - .claude.json-{email-safe}             Unlimited account backup
    - .credentials.json-{email-safe}
    - .claude.json-{email-safe}-YYYYMMDDHH  Limited account backup
    - .credentials.json-{email-safe}-YYYYMMDDHH

    {email-safe} Format Explanation:
    - Original: team@gravtice.com
    - Converted: team-at-gravtice-com (lowercase, @ -> -at-, . -> -, other special chars -> -)
EOF
            ;;
        *)
            echo -e "${RED}Error: Unknown oauth subcommand '$subcommand'${NC}"
            echo ""
            echo -e "${YELLOW}Usage: gbox oauth <subcommand> [options]${NC}"
            echo -e "${YELLOW}Available subcommands: switch, help${NC}"
            exit 1
            ;;
    esac
}

