#!/bin/bash
# Copyright 2024-2025 Gravtice
# SPDX-License-Identifier: Apache-2.0
#
# lib/apikey.sh - Unified provider management module

# ============================================
# Constants
# ============================================

UNIFIED_PROVIDERS_FILE="$HOME/.gbox/providers.json"
CLAUDE_SETTINGS_FILE="$GBOX_CLAUDE_DIR/settings.json"
CODEX_CONFIG_FILE="$GBOX_CODEX_DIR/config.toml"

DEFAULT_CLAUDE_TIMEOUT_MS=3000000
DEFAULT_CODEX_MODEL="gpt-5.1-codex-max"

# ============================================
# Basic helpers (kept for compatibility)
# ============================================

function validate_api_key_basic() {
    local api_key="$1"

    if [[ -z "$api_key" ]]; then
        error "API key cannot be empty."
        return 1
    fi

    return 0
}

function mask_apikey() {
    local key="$1"
    if [[ -z "$key" ]]; then
        echo ""
        return 0
    fi
    if [[ ${#key} -le 7 ]]; then
        echo "$key"
    else
        echo "${key:0:7}..."
    fi
}

# Escape TOML strings to avoid breaking config output
function escape_toml_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    echo "$value"
}

# ============================================
# Core Storage Functions
# ============================================

function init_unified_providers_storage() {
    mkdir -p "$GBOX_CONFIG_DIR" || { error "Failed to create config directory: $GBOX_CONFIG_DIR"; return 1; }

    if [[ -f "$UNIFIED_PROVIDERS_FILE" ]]; then
        chmod 600 "$UNIFIED_PROVIDERS_FILE" 2>/dev/null || true
        return 0
    fi

    local default_content='{"providers":{},"agents":{}}'
    local tmp="${UNIFIED_PROVIDERS_FILE}.tmp"

    if ! echo "$default_content" | jq '.' > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        error "Failed to initialize provider storage."
        return 1
    fi

    if ! mv "$tmp" "$UNIFIED_PROVIDERS_FILE"; then
        rm -f "$tmp"
        error "Failed to finalize provider storage."
        return 1
    fi

    chmod 600 "$UNIFIED_PROVIDERS_FILE" 2>/dev/null || warn "Unable to set permissions on $UNIFIED_PROVIDERS_FILE"
    success "Initialized provider storage at $UNIFIED_PROVIDERS_FILE"
}

function read_providers_config() {
    init_unified_providers_storage || return 1

    local config
    config=$(cat "$UNIFIED_PROVIDERS_FILE" 2>/dev/null) || { error "Failed to read $UNIFIED_PROVIDERS_FILE"; return 1; }

    if ! echo "$config" | jq -e 'type=="object" and has("providers") and (.providers|type=="object") and has("agents") and (.agents|type=="object")' >/dev/null 2>&1; then
        error "Invalid provider config format at $UNIFIED_PROVIDERS_FILE"
        return 1
    fi

    echo "$config"
}

function update_providers_config() {
    local new_config="$1"

    if [[ -z "$new_config" ]]; then
        error "Config content is empty, aborting update."
        return 1
    fi

    mkdir -p "$GBOX_CONFIG_DIR" || { error "Failed to create config directory: $GBOX_CONFIG_DIR"; return 1; }
    local tmp="${UNIFIED_PROVIDERS_FILE}.tmp"

    if ! echo "$new_config" | jq -e 'select(type=="object" and has("providers") and (.providers|type=="object") and has("agents") and (.agents|type=="object"))' > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        error "Invalid JSON structure for providers config."
        return 1
    fi

    if ! mv "$tmp" "$UNIFIED_PROVIDERS_FILE"; then
        rm -f "$tmp"
        error "Failed to persist providers config."
        return 1
    fi

    chmod 600 "$UNIFIED_PROVIDERS_FILE" 2>/dev/null || warn "Unable to set permissions on $UNIFIED_PROVIDERS_FILE"
    return 0
}

# ============================================
# Helper Functions
# ============================================

function ensure_supported_agent() {
    local agent="$1"
    case "$agent" in
        claude|codex)
            return 0
            ;;
        *)
            error "Unsupported agent '$agent'. Supported agents: claude, codex."
            return 1
            ;;
    esac
}

function check_provider_exists() {
    local config="$1"
    local name="$2"
    echo "$config" | jq -e --arg name "$name" '.providers[$name] != null' >/dev/null 2>&1
}

function get_provider_data() {
    local config="$1"
    local name="$2"
    echo "$config" | jq -c --arg name "$name" '.providers[$name] // empty'
}

function get_agent_config() {
    local config="$1"
    local agent="$2"
    echo "$config" | jq -c --arg agent "$agent" '.agents[$agent] // empty'
}

function check_provider_usage() {
    local config="$1"
    local name="$2"

    echo "$config" | jq -r --arg name "$name" '
        .agents
        | to_entries[]
        | . as $agent
        | ($agent.value.defaultProvider == $name) as $isDefault
        | ($agent.value.providerConfigs != null and $agent.value.providerConfigs[$name] != null) as $hasConfig
        | select($isDefault or $hasConfig)
        | "\($agent.key):" + ([
            (if $isDefault then "default" else empty end),
            (if $hasConfig then "config" else empty end)
        ] | join(","))
    '
}

# ============================================
# Provider Management
# ============================================

function provider_add() {
    local name=""
    local api_key=""
    local description=""
    local claude_url=""
    local codex_url=""
    local claude_set=0
    local codex_set=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description)
                shift
                [[ $# -eq 0 ]] && { error "--description requires a value."; return 1; }
                description="$1"
                shift
                ;;
            --claude-url)
                shift
                [[ $# -eq 0 ]] && { error "--claude-url requires a value."; return 1; }
                claude_url="$1"
                claude_set=1
                shift
                ;;
            --codex-url)
                shift
                [[ $# -eq 0 ]] && { error "--codex-url requires a value."; return 1; }
                codex_url="$1"
                codex_set=1
                shift
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                elif [[ -z "$api_key" ]]; then
                    api_key="$1"
                else
                    error "Unknown argument '$1'"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$name" || -z "$api_key" || "$claude_set" -ne 1 || "$codex_set" -ne 1 ]]; then
        error "Usage: gbox apikey provider add <name> <api_key> --claude-url <url> --codex-url <url> [--description <text>]"
        return 1
    fi

    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
        error "Provider name must use letters, numbers, dots, dashes or underscores."
        return 1
    fi

    validate_api_key_basic "$api_key" || return 1

    local config
    config=$(read_providers_config) || return 1

    if check_provider_exists "$config" "$name"; then
        error "Provider '$name' already exists."
        return 1
    fi

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local updated
    updated=$(echo "$config" | jq \
        --arg name "$name" --arg apiKey "$api_key" \
        --arg claudeUrl "$claude_url" --arg codexUrl "$codex_url" \
        --arg desc "$description" --arg now "$now" '
        .providers[$name] = {
            name: $name,
            apiKey: $apiKey,
            claudeUrl: $claudeUrl,
            codexUrl: $codexUrl,
            description: ($desc // ""),
            createdAt: $now,
            updatedAt: $now
        } |
        .agents = (.agents // {})
    ') || { error "Failed to add provider."; return 1; }

    if update_providers_config "$updated"; then
        success "Provider '$name' added."
        regenerate_agent_config "claude" || warn "Failed to regenerate Claude settings."
        regenerate_agent_config "codex" || warn "Failed to regenerate Codex config."
    fi
}

function provider_update() {
    local name=""
    local api_key=""
    local description=""
    local claude_url=""
    local codex_url=""

    local api_key_set=0
    local desc_set=0
    local claude_set=0
    local codex_set=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description)
                shift
                [[ $# -eq 0 ]] && { error "--description requires a value."; return 1; }
                description="$1"
                desc_set=1
                shift
                ;;
            --claude-url)
                shift
                [[ $# -eq 0 ]] && { error "--claude-url requires a value."; return 1; }
                claude_url="$1"
                claude_set=1
                shift
                ;;
            --codex-url)
                shift
                [[ $# -eq 0 ]] && { error "--codex-url requires a value."; return 1; }
                codex_url="$1"
                codex_set=1
                shift
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                elif [[ -z "$api_key" && "$api_key_set" -eq 0 ]]; then
                    api_key="$1"
                    api_key_set=1
                else
                    error "Unknown argument '$1'"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$name" ]]; then
        error "Usage: gbox apikey provider update <name> [<api_key>] [--claude-url <url>] [--codex-url <url>] [--description <text>]"
        return 1
    fi

    if [[ "$api_key_set" -ne 1 && "$desc_set" -ne 1 && "$claude_set" -ne 1 && "$codex_set" -ne 1 ]]; then
        error "No updates specified. Provide an api key or metadata flag to update."
        return 1
    fi

    if [[ "$api_key_set" -eq 1 ]]; then
        validate_api_key_basic "$api_key" || return 1
    fi

    local config
    config=$(read_providers_config) || return 1

    if ! check_provider_exists "$config" "$name"; then
        error "Provider '$name' not found."
        return 1
    fi

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local updated
    updated=$(echo "$config" | jq \
        --arg name "$name" \
        --arg apiKey "$api_key" --arg hasApiKey "$api_key_set" \
        --arg claudeUrl "$claude_url" --arg hasClaude "$claude_set" \
        --arg codexUrl "$codex_url" --arg hasCodex "$codex_set" \
        --arg desc "$description" --arg descSet "$desc_set" \
        --arg now "$now" '
        .providers[$name] = (.providers[$name] // {}) |
        (if $hasApiKey == "1" then .providers[$name].apiKey = $apiKey else . end) |
        (if $hasClaude == "1" then .providers[$name].claudeUrl = $claudeUrl else . end) |
        (if $hasCodex == "1" then .providers[$name].codexUrl = $codexUrl else . end) |
        (if $descSet == "1" then .providers[$name].description = $desc else . end) |
        .providers[$name].updatedAt = $now
    ') || { error "Failed to update provider."; return 1; }

    if update_providers_config "$updated"; then
        success "Provider '$name' updated."
        regenerate_agent_config "claude" || warn "Failed to regenerate Claude settings."
        regenerate_agent_config "codex" || warn "Failed to regenerate Codex config."
    fi
}

function provider_remove() {
    local name="$1"

    if [[ -z "$name" ]]; then
        error "Usage: gbox apikey provider remove <name>"
        return 1
    fi

    local config
    config=$(read_providers_config) || return 1

    if ! check_provider_exists "$config" "$name"; then
        error "Provider '$name' not found."
        return 1
    fi

    local usage
    usage=$(check_provider_usage "$config" "$name")
    if [[ -n "$usage" ]]; then
        error "Provider '$name' is still used by:"
        echo "$usage" | while read -r line; do
            [[ -n "$line" ]] && warn "  $line"
        done
        warn "Remove the dependent agent configs first."
        return 1
    fi

    local updated
    updated=$(echo "$config" | jq --arg name "$name" '
        del(.providers[$name]) |
        .agents = (.agents // {}) |
        .agents |= with_entries(
            .value.providerConfigs = (.value.providerConfigs // {}) |
            .value.defaultProvider = (if .value.defaultProvider == $name then "" else .value.defaultProvider end) |
            .value.providerConfigs = (.value.providerConfigs | with_entries(select(.key != $name))) |
            .
        )
    ') || { error "Failed to remove provider."; return 1; }

    if update_providers_config "$updated"; then
        success "Provider '$name' removed."
        regenerate_agent_config "claude" || warn "Failed to regenerate Claude settings."
        regenerate_agent_config "codex" || warn "Failed to regenerate Codex config."
    fi
}

function provider_list() {
    local config
    config=$(read_providers_config) || return 1

    local total
    total=$(echo "$config" | jq '.providers | length')

    if [[ "$total" -eq 0 ]]; then
        warn "No providers configured. Add one with: gbox apikey provider add <name> <api_key> --claude-url <url> --codex-url <url> [--description <text>]"
        return 0
    fi

    echo -e "${BLUE}Providers ($total total):${NC}"

    echo "$config" | jq -c '.providers | to_entries[]' | while read -r entry; do
        local name api_key description created updated usage claude_url codex_url
        name=$(echo "$entry" | jq -r '.key')
        api_key=$(echo "$entry" | jq -r '.value.apiKey // ""')
        description=$(echo "$entry" | jq -r '.value.description // ""')
        claude_url=$(echo "$entry" | jq -r '.value.claudeUrl // ""')
        codex_url=$(echo "$entry" | jq -r '.value.codexUrl // ""')
        created=$(echo "$entry" | jq -r '.value.createdAt // ""')
        updated=$(echo "$entry" | jq -r '.value.updatedAt // ""')
        usage=$(check_provider_usage "$config" "$name")

        echo -e "  ${GREEN}${name}${NC}"
        [[ -n "$description" ]] && echo "      Description: $description"
        echo "      API Key:     $(mask_apikey "$api_key")"
        echo "      Claude URL:  ${claude_url:-"-"}"
        echo "      Codex URL:   ${codex_url:-"-"}"
        echo "      Created:     ${created:-"-"}"
        echo "      Updated:     ${updated:-"-"}"
        if [[ -n "$usage" ]]; then
            echo "      Usage:"
            echo "$usage" | while read -r line; do
                [[ -n "$line" ]] && echo "        - $line"
            done
        else
            echo "      Usage:       not used"
        fi
        echo ""
    done
}

function provider_info() {
    local name="$1"

    if [[ -z "$name" ]]; then
        error "Usage: gbox apikey provider info <name>"
        return 1
    fi

    local config
    config=$(read_providers_config) || return 1

    local provider_json
    provider_json=$(get_provider_data "$config" "$name")
    if [[ -z "$provider_json" ]]; then
        error "Provider '$name' not found."
        return 1
    fi

    local api_key description created updated claude_url codex_url
    api_key=$(echo "$provider_json" | jq -r '.apiKey // ""')
    description=$(echo "$provider_json" | jq -r '.description // ""')
    claude_url=$(echo "$provider_json" | jq -r '.claudeUrl // ""')
    codex_url=$(echo "$provider_json" | jq -r '.codexUrl // ""')
    created=$(echo "$provider_json" | jq -r '.createdAt // ""')
    updated=$(echo "$provider_json" | jq -r '.updatedAt // ""')
    local usage
    usage=$(check_provider_usage "$config" "$name")

    echo -e "${GREEN}Provider:${NC} $name"
    [[ -n "$description" ]] && echo -e "${BLUE}Description:${NC} $description"
    echo -e "${BLUE}API Key:${NC} $(mask_apikey "$api_key")"
    echo -e "${BLUE}Claude URL:${NC} ${claude_url:-"-"}"
    echo -e "${BLUE}Codex URL:${NC} ${codex_url:-"-"}"
    echo -e "${BLUE}Created:${NC} ${created:-"-"}"
    echo -e "${BLUE}Updated:${NC} ${updated:-"-"}"

    if [[ -n "$usage" ]]; then
        echo -e "${BLUE}Usage:${NC}"
        echo "$usage" | while read -r line; do
            [[ -n "$line" ]] && echo "  - $line"
        done
    else
        echo -e "${BLUE}Usage:${NC} not used"
    fi
}

# ============================================
# Agent Configuration Management
# ============================================

function agent_config_set() {
    local agent=""
    local provider=""

    local timeout="" haiku_model="" sonnet_model="" opus_model="" subagent_model=""
    local model="" display_name=""

    local timeout_set=0 haiku_set=0 sonnet_set=0 opus_set=0 subagent_set=0
    local model_set=0 display_set=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                shift
                [[ $# -eq 0 ]] && { error "--timeout requires a value."; return 1; }
                timeout="$1"
                timeout_set=1
                shift
                ;;
            --haiku-model)
                shift
                [[ $# -eq 0 ]] && { error "--haiku-model requires a value."; return 1; }
                haiku_model="$1"
                haiku_set=1
                shift
                ;;
            --sonnet-model)
                shift
                [[ $# -eq 0 ]] && { error "--sonnet-model requires a value."; return 1; }
                sonnet_model="$1"
                sonnet_set=1
                shift
                ;;
            --opus-model)
                shift
                [[ $# -eq 0 ]] && { error "--opus-model requires a value."; return 1; }
                opus_model="$1"
                opus_set=1
                shift
                ;;
            --subagent-model)
                shift
                [[ $# -eq 0 ]] && { error "--subagent-model requires a value."; return 1; }
                subagent_model="$1"
                subagent_set=1
                shift
                ;;
            --model)
                shift
                [[ $# -eq 0 ]] && { error "--model requires a value."; return 1; }
                model="$1"
                model_set=1
                shift
                ;;
            --display-name)
                shift
                [[ $# -eq 0 ]] && { error "--display-name requires a value."; return 1; }
                display_name="$1"
                display_set=1
                shift
                ;;
            --base-url)
                error "'--base-url' is no longer supported. Provider URLs are taken from the provider record."
                return 1
                ;;
            *)
                if [[ -z "$agent" ]]; then
                    agent="$1"
                elif [[ -z "$provider" ]]; then
                    provider="$1"
                else
                    error "Unknown argument '$1'"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$agent" || -z "$provider" ]]; then
        error "Usage: gbox apikey <agent> set <provider> [options]"
        echo "  claude options: --timeout --haiku-model --sonnet-model --opus-model --subagent-model"
        echo "  codex options:  --model --display-name"
        return 1
    fi

    ensure_supported_agent "$agent" || return 1

    local config
    config=$(read_providers_config) || return 1

    if ! check_provider_exists "$config" "$provider"; then
        error "Provider '$provider' not found. Add it first with: gbox apikey provider add"
        return 1
    fi

    local provider_data
    provider_data=$(get_provider_data "$config" "$provider")

    local updated
    if [[ "$agent" == "claude" ]]; then
        local claude_url
        claude_url=$(echo "$provider_data" | jq -r '.claudeUrl // ""')
        if [[ -z "$claude_url" ]]; then
            error "Provider '$provider' does not support claude (claudeUrl is missing or empty)"
            info "Use: gbox apikey provider update $provider --claude-url <url>"
            return 1
        fi

        updated=$(echo "$config" | jq \
            --arg agent "$agent" --arg provider "$provider" \
            --arg baseUrl "$claude_url" \
            --arg timeout "$timeout" --arg hasTimeout "$timeout_set" \
            --arg haiku "$haiku_model" --arg hasHaiku "$haiku_set" \
            --arg sonnet "$sonnet_model" --arg hasSonnet "$sonnet_set" \
            --arg opus "$opus_model" --arg hasOpus "$opus_set" \
            --arg subagent "$subagent_model" --arg hasSubagent "$subagent_set" '
            .agents[$agent] = (.agents[$agent] // {enabled: true, defaultProvider: "", providerConfigs: {}}) |
            .agents[$agent].providerConfigs = (.agents[$agent].providerConfigs // {}) |
            .agents[$agent].providerConfigs[$provider] = (.agents[$agent].providerConfigs[$provider] // {}) |
            .agents[$agent].providerConfigs[$provider].baseUrl = $baseUrl |
            (if $hasTimeout == "1" then .agents[$agent].providerConfigs[$provider].timeout = (try ($timeout | tonumber) catch $timeout) else . end) |
            (if $hasHaiku == "1" then .agents[$agent].providerConfigs[$provider].haikuModel = $haiku else . end) |
            (if $hasSonnet == "1" then .agents[$agent].providerConfigs[$provider].sonnetModel = $sonnet else . end) |
            (if $hasOpus == "1" then .agents[$agent].providerConfigs[$provider].opusModel = $opus else . end) |
            (if $hasSubagent == "1" then .agents[$agent].providerConfigs[$provider].subagentModel = $subagent else . end) |
            if (.agents[$agent].defaultProvider // "") == "" then .agents[$agent].defaultProvider = $provider else . end
        ') || { error "Failed to update agent config."; return 1; }
    else
        local codex_url
        codex_url=$(echo "$provider_data" | jq -r '.codexUrl // ""')
        if [[ -z "$codex_url" ]]; then
            error "Provider '$provider' does not support codex (codexUrl is missing or empty)"
            info "Use: gbox apikey provider update $provider --codex-url <url>"
            return 1
        fi

        updated=$(echo "$config" | jq \
            --arg agent "$agent" --arg provider "$provider" \
            --arg baseUrl "$codex_url" \
            --arg model "$model" --arg hasModel "$model_set" \
            --arg display "$display_name" --arg hasDisplay "$display_set" '
            .agents[$agent] = (.agents[$agent] // {enabled: true, defaultProvider: "", providerConfigs: {}}) |
            .agents[$agent].providerConfigs = (.agents[$agent].providerConfigs // {}) |
            .agents[$agent].providerConfigs[$provider] = (.agents[$agent].providerConfigs[$provider] // {}) |
            .agents[$agent].providerConfigs[$provider].baseUrl = $baseUrl |
            (if $hasModel == "1" then .agents[$agent].providerConfigs[$provider].model = $model else . end) |
            (if $hasDisplay == "1" then .agents[$agent].providerConfigs[$provider].displayName = $display else . end) |
            if (.agents[$agent].defaultProvider // "") == "" then .agents[$agent].defaultProvider = $provider else . end
        ') || { error "Failed to update agent config."; return 1; }
    fi

    if update_providers_config "$updated"; then
        success "Updated $agent configuration for provider '$provider'."
        regenerate_agent_config "$agent" || warn "Failed to regenerate config for $agent."
    fi
}

function agent_config_remove() {
    local agent="$1"
    local provider="$2"

    if [[ -z "$agent" || -z "$provider" ]]; then
        error "Usage: gbox apikey <agent> remove <provider>"
        return 1
    fi

    ensure_supported_agent "$agent" || return 1

    local config
    config=$(read_providers_config) || return 1

    local agent_json
    agent_json=$(get_agent_config "$config" "$agent")
    if [[ -z "$agent_json" ]]; then
        warn "Agent '$agent' has no configuration to remove."
        return 0
    fi

    if ! echo "$agent_json" | jq -e --arg provider "$provider" '.providerConfigs != null and .providerConfigs[$provider] != null' >/dev/null 2>&1; then
        warn "No configuration found for provider '$provider' under agent '$agent'."
        return 0
    fi

    local updated
    updated=$(echo "$config" | jq --arg agent "$agent" --arg provider "$provider" '
        .agents[$agent] = (.agents[$agent] // {enabled: true, defaultProvider: "", providerConfigs: {}}) |
        .agents[$agent].providerConfigs = (.agents[$agent].providerConfigs // {}) |
        .agents[$agent].providerConfigs = (.agents[$agent].providerConfigs | with_entries(select(.key != $provider))) |
        if (.agents[$agent].defaultProvider // "") == $provider then .agents[$agent].defaultProvider = "" else . end
    ') || { error "Failed to remove agent configuration."; return 1; }

    if update_providers_config "$updated"; then
        success "Removed $agent configuration for provider '$provider'."
        regenerate_agent_config "$agent" || warn "Failed to regenerate config for $agent."
    fi
}

function agent_config_set_default() {
    local agent="$1"
    local provider="$2"

    if [[ -z "$agent" || -z "$provider" ]]; then
        error "Usage: gbox apikey <agent> set-default <provider>"
        return 1
    fi

    ensure_supported_agent "$agent" || return 1

    local config
    config=$(read_providers_config) || return 1

    if ! check_provider_exists "$config" "$provider"; then
        error "Provider '$provider' not found."
        return 1
    fi

    local agent_json
    agent_json=$(get_agent_config "$config" "$agent")
    local has_config=1
    if [[ -n "$agent_json" ]]; then
        echo "$agent_json" | jq -e --arg provider "$provider" '.providerConfigs != null and .providerConfigs[$provider] != null' >/dev/null 2>&1
        has_config=$?
    fi

    if [[ "$has_config" -ne 0 ]]; then
        warn "Provider '$provider' has no configuration for agent '$agent'. Set it first with: gbox apikey $agent set $provider ..."
        return 1
    fi

    local updated
    updated=$(echo "$config" | jq --arg agent "$agent" --arg provider "$provider" '
        .agents[$agent] = (.agents[$agent] // {enabled: true, defaultProvider: "", providerConfigs: {}}) |
        .agents[$agent].defaultProvider = $provider
    ') || { error "Failed to set default provider."; return 1; }

    if update_providers_config "$updated"; then
        success "Set default provider for $agent to '$provider'."
        regenerate_agent_config "$agent" || warn "Failed to regenerate config for $agent."
    fi
}

function agent_config_enable() {
    local agent="$1"
    if [[ -z "$agent" ]]; then
        error "Usage: gbox apikey <agent> enable"
        return 1
    fi

    ensure_supported_agent "$agent" || return 1

    local config
    config=$(read_providers_config) || return 1

    local updated
    updated=$(echo "$config" | jq --arg agent "$agent" '
        .agents[$agent] = (.agents[$agent] // {defaultProvider: "", providerConfigs: {}}) |
        .agents[$agent].enabled = true
    ') || { error "Failed to enable agent '$agent'."; return 1; }

    if update_providers_config "$updated"; then
        success "Enabled $agent provider mode."
        regenerate_agent_config "$agent" || warn "Failed to regenerate config for $agent."
    fi
}

function agent_config_disable() {
    local agent="$1"
    if [[ -z "$agent" ]]; then
        error "Usage: gbox apikey <agent> disable"
        return 1
    fi

    ensure_supported_agent "$agent" || return 1

    local config
    config=$(read_providers_config) || return 1

    local updated
    updated=$(echo "$config" | jq --arg agent "$agent" '
        .agents[$agent] = (.agents[$agent] // {defaultProvider: "", providerConfigs: {}}) |
        .agents[$agent].enabled = false
    ') || { error "Failed to disable agent '$agent'."; return 1; }

    if update_providers_config "$updated"; then
        success "Disabled $agent provider mode."
        regenerate_agent_config "$agent" || warn "Failed to regenerate config for $agent."
    fi
}

function agent_config_list() {
    local agent="$1"
    if [[ -z "$agent" ]]; then
        error "Usage: gbox apikey <agent> list"
        return 1
    fi

    ensure_supported_agent "$agent" || return 1

    local config
    config=$(read_providers_config) || return 1

    local agent_json
    agent_json=$(get_agent_config "$config" "$agent")
    if [[ -z "$agent_json" ]]; then
        warn "No configuration found for agent '$agent'."
        return 0
    fi

    local enabled default_provider
    enabled=$(echo "$agent_json" | jq -r 'if .enabled == null then "true" else (.enabled | tostring) end')
    default_provider=$(echo "$agent_json" | jq -r '.defaultProvider // ""')

    local agent_display
    agent_display=$(echo "$agent" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
    echo -e "${GREEN}${agent_display} configuration${NC}"
    echo -e "${BLUE}Enabled:${NC} $enabled"
    echo -e "${BLUE}Default provider:${NC} ${default_provider:-"-"}"

    local provider_count
    provider_count=$(echo "$agent_json" | jq '.providerConfigs | if . == null then 0 else (. | length) end')
    if [[ "$provider_count" -eq 0 ]]; then
        warn "No provider configs found for $agent."
        return 0
    fi

    echo ""
    echo -e "${BLUE}Provider configs:${NC}"
    echo "$agent_json" | jq -c '.providerConfigs | to_entries[]' | while read -r entry; do
        local name cfg provider_data
        name=$(echo "$entry" | jq -r '.key')
        cfg=$(echo "$entry" | jq -c '.value')
        provider_data=$(get_provider_data "$config" "$name")

        local marker=" "
        [[ "$name" == "$default_provider" ]] && marker="*"

        printf "  %s \033[0;32m%s\033[0m\n" "$marker" "$name"
        if [[ -n "$provider_data" ]]; then
            local api_key description
            api_key=$(echo "$provider_data" | jq -r '.apiKey // ""')
            description=$(echo "$provider_data" | jq -r '.description // ""')
            [[ -n "$description" ]] && echo "      Description: $description"
            echo "      API Key:     $(mask_apikey "$api_key")"
        else
            warn "      Provider record missing from catalog."
        fi

        if [[ "$agent" == "claude" ]]; then
            echo "      Base URL:    $(echo "$cfg" | jq -r '.baseUrl // "-"')"
            local timeout
            timeout=$(echo "$cfg" | jq -r '.timeout // empty')
            [[ -z "$timeout" || "$timeout" == "null" ]] && timeout="$DEFAULT_CLAUDE_TIMEOUT_MS"
            echo "      Timeout:     ${timeout} ms"
            echo "      Haiku:       $(echo "$cfg" | jq -r '.haikuModel // "-"')"
            echo "      Sonnet:      $(echo "$cfg" | jq -r '.sonnetModel // "-"')"
            echo "      Opus:        $(echo "$cfg" | jq -r '.opusModel // "-"')"
            echo "      Subagent:    $(echo "$cfg" | jq -r '.subagentModel // "-"')"
        else
            echo "      Base URL:    $(echo "$cfg" | jq -r '.baseUrl // "-"')"
            echo "      Model:       $(echo "$cfg" | jq -r '.model // "-"')"
            echo "      Display:     $(echo "$cfg" | jq -r '.displayName // "-"')"
        fi
        echo ""
    done
}

function agent_config_status() {
    local agent="$1"
    if [[ -z "$agent" ]]; then
        error "Usage: gbox apikey <agent> status"
        return 1
    fi

    ensure_supported_agent "$agent" || return 1

    local config
    config=$(read_providers_config) || return 1

    local agent_json
    agent_json=$(get_agent_config "$config" "$agent")
    if [[ -z "$agent_json" ]]; then
        warn "No configuration found for agent '$agent'."
        return 0
    fi

    local enabled default_provider
    enabled=$(echo "$agent_json" | jq -r 'if .enabled == null then "true" else (.enabled | tostring) end')
    default_provider=$(echo "$agent_json" | jq -r '.defaultProvider // ""')

    local agent_display
    agent_display=$(echo "$agent" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
    echo -e "${GREEN}${agent_display} status${NC}"
    echo -e "${BLUE}Enabled:${NC} $enabled"
    echo -e "${BLUE}Default provider:${NC} ${default_provider:-"-"}"

    if [[ -z "$default_provider" ]]; then
        warn "Default provider not set for $agent."
        return 0
    fi

    local provider_data provider_cfg
    provider_data=$(get_provider_data "$config" "$default_provider")
    provider_cfg=$(echo "$agent_json" | jq -c --arg provider "$default_provider" '.providerConfigs[$provider] // {}')

    if [[ -z "$provider_data" ]]; then
        error "Default provider '$default_provider' is missing from provider catalog."
        return 1
    fi

    if [[ "$agent" == "claude" ]]; then
        local api_key base_url timeout haiku sonnet opus subagent
        api_key=$(echo "$provider_data" | jq -r '.apiKey // ""')
        base_url=$(echo "$provider_cfg" | jq -r '.baseUrl // ""')
        timeout=$(echo "$provider_cfg" | jq -r '.timeout // empty')
        [[ -z "$timeout" || "$timeout" == "null" ]] && timeout="$DEFAULT_CLAUDE_TIMEOUT_MS"
        haiku=$(echo "$provider_cfg" | jq -r '.haikuModel // ""')
        sonnet=$(echo "$provider_cfg" | jq -r '.sonnetModel // ""')
        opus=$(echo "$provider_cfg" | jq -r '.opusModel // ""')
        subagent=$(echo "$provider_cfg" | jq -r '.subagentModel // ""')

        echo -e "${BLUE}Base URL:${NC} ${base_url:-"-"}"
        echo -e "${BLUE}Timeout:${NC} ${timeout} ms"
        [[ -n "$haiku" ]] && echo -e "${BLUE}Haiku model:${NC} $haiku"
        [[ -n "$sonnet" ]] && echo -e "${BLUE}Sonnet model:${NC} $sonnet"
        [[ -n "$opus" ]] && echo -e "${BLUE}Opus model:${NC} $opus"
        [[ -n "$subagent" ]] && echo -e "${BLUE}Subagent model:${NC} $subagent"
        echo -e "${BLUE}API Key:${NC} $(mask_apikey "$api_key")"
    else
        local api_key base_url model display_name
        api_key=$(echo "$provider_data" | jq -r '.apiKey // ""')
        base_url=$(echo "$provider_cfg" | jq -r '.baseUrl // ""')
        model=$(echo "$provider_cfg" | jq -r '.model // ""')
        display_name=$(echo "$provider_cfg" | jq -r '.displayName // ""')

        echo -e "${BLUE}Display name:${NC} ${display_name:-$default_provider}"
        echo -e "${BLUE}Model:${NC} ${model:-$DEFAULT_CODEX_MODEL}"
        echo -e "${BLUE}Base URL:${NC} ${base_url:-"-"}"
        echo -e "${BLUE}API Key:${NC} $(mask_apikey "$api_key")"
    fi
}

# ============================================
# Auto-Generation Functions
# ============================================

function generate_claude_settings_json() {
    local config
    config=$(read_providers_config) || return 1

    local agent_json
    agent_json=$(get_agent_config "$config" "claude")
    [[ -z "$agent_json" ]] && agent_json="{}"

    local enabled
    enabled=$(echo "$agent_json" | jq -r 'if .enabled == null then "true" else (.enabled | tostring) end')

    local default_provider
    default_provider=$(echo "$agent_json" | jq -r '.defaultProvider // ""')

    local existing_settings="{}"
    if [[ -f "$CLAUDE_SETTINGS_FILE" ]]; then
        existing_settings=$(cat "$CLAUDE_SETTINGS_FILE" 2>/dev/null || echo "{}")
    fi

    if [[ "$enabled" != "true" || -z "$default_provider" ]]; then
        local cleaned
        cleaned=$(echo "$existing_settings" | jq '
            if .env then
                .env |= del(
                    .ANTHROPIC_AUTH_TOKEN,
                    .ANTHROPIC_BASE_URL,
                    .API_TIMEOUT_MS,
                    .ANTHROPIC_DEFAULT_HAIKU_MODEL,
                    .ANTHROPIC_DEFAULT_SONNET_MODEL,
                    .ANTHROPIC_DEFAULT_OPUS_MODEL,
                    .CLAUDE_CODE_SUBAGENT_MODEL,
                    .CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                )
            else . end
            | (if .env == {} then del(.env) else . end)
        ' 2>/dev/null)

        if [[ "$cleaned" == "{}" ]]; then
            rm -f "$CLAUDE_SETTINGS_FILE"
            return 0
        fi

        local tmp="${CLAUDE_SETTINGS_FILE}.tmp"
        if echo "$cleaned" | jq '.' > "$tmp" 2>/dev/null; then
            mv "$tmp" "$CLAUDE_SETTINGS_FILE"
            chmod 600 "$CLAUDE_SETTINGS_FILE" 2>/dev/null || warn "Unable to set permissions on $CLAUDE_SETTINGS_FILE"
        else
            rm -f "$tmp"
            error "Failed to clean Claude settings.json"
            return 1
        fi
        return 0
    fi

    local provider_data
    provider_data=$(get_provider_data "$config" "$default_provider")
    if [[ -z "$provider_data" ]]; then
        error "Default provider '$default_provider' not found in provider catalog."
        return 1
    fi

    local provider_cfg
    provider_cfg=$(echo "$agent_json" | jq -c --arg provider "$default_provider" '.providerConfigs[$provider] // {}')

    local api_key base_url timeout haiku sonnet opus subagent
    api_key=$(echo "$provider_data" | jq -r '.apiKey // ""')
    base_url=$(echo "$provider_cfg" | jq -r '.baseUrl // ""')
    timeout=$(echo "$provider_cfg" | jq -r '.timeout // empty')
    [[ -z "$timeout" || "$timeout" == "null" ]] && timeout="$DEFAULT_CLAUDE_TIMEOUT_MS"
    haiku=$(echo "$provider_cfg" | jq -r '.haikuModel // ""')
    sonnet=$(echo "$provider_cfg" | jq -r '.sonnetModel // ""')
    opus=$(echo "$provider_cfg" | jq -r '.opusModel // ""')
    subagent=$(echo "$provider_cfg" | jq -r '.subagentModel // ""')

    if [[ -z "$api_key" ]]; then
        error "Default provider '$default_provider' is missing apiKey."
        return 1
    fi

    mkdir -p "$GBOX_CLAUDE_DIR" || { error "Failed to create Claude config directory: $GBOX_CLAUDE_DIR"; return 1; }

    local settings_json
    settings_json=$(echo "$existing_settings" | jq \
        --arg api_key "$api_key" \
        --arg base_url "$base_url" \
        --arg timeout "$timeout" \
        --arg haiku "$haiku" \
        --arg sonnet "$sonnet" \
        --arg opus "$opus" \
        --arg subagent "$subagent" '
        if .env == null then .env = {} else . end |
        .env.ANTHROPIC_AUTH_TOKEN = $api_key |
        .env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = 1 |
        .env.API_TIMEOUT_MS = ($timeout | tostring) |
        (if ($base_url | length) > 0 then .env.ANTHROPIC_BASE_URL = $base_url else .env |= del(.ANTHROPIC_BASE_URL) end) |
        (if ($haiku | length) > 0 then .env.ANTHROPIC_DEFAULT_HAIKU_MODEL = $haiku else .env |= del(.ANTHROPIC_DEFAULT_HAIKU_MODEL) end) |
        (if ($sonnet | length) > 0 then .env.ANTHROPIC_DEFAULT_SONNET_MODEL = $sonnet else .env |= del(.ANTHROPIC_DEFAULT_SONNET_MODEL) end) |
        (if ($opus | length) > 0 then .env.ANTHROPIC_DEFAULT_OPUS_MODEL = $opus else .env |= del(.ANTHROPIC_DEFAULT_OPUS_MODEL) end) |
        (if ($subagent | length) > 0 then .env.CLAUDE_CODE_SUBAGENT_MODEL = $subagent else .env |= del(.CLAUDE_CODE_SUBAGENT_MODEL) end)
    ') || { error "Failed to build settings.json content."; return 1; }

    local tmp="${CLAUDE_SETTINGS_FILE}.tmp"
    if echo "$settings_json" | jq '.' > "$tmp" 2>/dev/null; then
        mv "$tmp" "$CLAUDE_SETTINGS_FILE"
        chmod 600 "$CLAUDE_SETTINGS_FILE" 2>/dev/null || warn "Unable to set permissions on $CLAUDE_SETTINGS_FILE"
        return 0
    else
        rm -f "$tmp"
        error "Failed to write settings.json to $CLAUDE_SETTINGS_FILE"
        return 1
    fi
}

function generate_codex_config_toml() {
    local config
    config=$(read_providers_config) || return 1

    local agent_json
    agent_json=$(get_agent_config "$config" "codex")
    [[ -z "$agent_json" ]] && agent_json="{}"

    local enabled
    enabled=$(echo "$agent_json" | jq -r 'if .enabled == null then "true" else (.enabled | tostring) end')

    local default_provider
    default_provider=$(echo "$agent_json" | jq -r '.defaultProvider // ""')

    mkdir -p "$GBOX_CODEX_DIR" || { error "Failed to create Codex config directory: $GBOX_CODEX_DIR"; return 1; }

    local tmp="${CODEX_CONFIG_FILE}.tmp"
    local preserved_config=""
    local mcp_servers_content=""

    if [[ -f "$CODEX_CONFIG_FILE" ]]; then
        preserved_config=$(awk '
            /^[[:space:]]*$/ { next }
            /^[[:space:]]*#/ { next }

            /^model_provider[[:space:]]*=/ { next }
            /^model[[:space:]]*=/ { next }

            /^\[model_providers\./ { in_model_providers=1; next }
            /^\[mcp_servers\./ { in_mcp=1; next }

            /^\[/ {
                in_model_providers=0
                in_mcp=0
                if (!/^\[model_providers/ && !/^\[mcp_servers/) {
                    print
                    next
                }
            }

            in_model_providers || in_mcp { next }

            { print }
        ' "$CODEX_CONFIG_FILE")

        mcp_servers_content=$(awk '
            /^\[mcp_servers\./ {
                in_mcp=1
                print
                next
            }
            /^\[/ && !/^\[mcp_servers\./ {
                in_mcp=0
            }
            in_mcp {
                print
            }
        ' "$CODEX_CONFIG_FILE")
    fi

    if [[ "$enabled" != "true" || -z "$default_provider" ]]; then
        {
            echo "# Generated by gbox (codex provider mode disabled)"
            echo "model = \"$DEFAULT_CODEX_MODEL\""
            if [[ -n "$preserved_config" ]]; then
                echo "$preserved_config"
            fi
            if [[ -n "$mcp_servers_content" ]]; then
                echo ""
                echo "# MCP Servers (preserved from previous config)"
                echo "$mcp_servers_content"
            fi
        } > "$tmp" || { rm -f "$tmp"; error "Failed to build Codex config."; return 1; }

        mv "$tmp" "$CODEX_CONFIG_FILE"
        chmod 600 "$CODEX_CONFIG_FILE" 2>/dev/null || warn "Unable to set permissions on $CODEX_CONFIG_FILE"
        return 0
    fi

    local provider_data
    provider_data=$(get_provider_data "$config" "$default_provider")
    if [[ -z "$provider_data" ]]; then
        error "Default provider '$default_provider' not found in provider catalog."
        return 1
    fi

    local provider_cfg
    provider_cfg=$(echo "$agent_json" | jq -c --arg provider "$default_provider" '.providerConfigs[$provider] // {}')

    local api_key base_url model display_name
    api_key=$(echo "$provider_data" | jq -r '.apiKey // ""')
    base_url=$(echo "$provider_cfg" | jq -r '.baseUrl // ""')
    model=$(echo "$provider_cfg" | jq -r '.model // ""')
    display_name=$(echo "$provider_cfg" | jq -r '.displayName // ""')

    if [[ -z "$api_key" ]]; then
        error "Default provider '$default_provider' is missing apiKey."
        return 1
    fi

    local default_model="$model"
    [[ -z "$default_model" || "$default_model" == "null" ]] && default_model="$DEFAULT_CODEX_MODEL"
    local escaped_model
    escaped_model=$(escape_toml_string "$default_model")

    {
        echo "model = \"$escaped_model\""

        if [[ -n "$preserved_config" ]]; then
            echo "$preserved_config"
        fi

        echo ""
        echo "model_provider = \"$(escape_toml_string "$default_provider")\""
        echo ""

        echo "[model_providers.${default_provider}]"
        local dn
        dn=$(escape_toml_string "${display_name:-$default_provider}")
        echo "name = \"${dn}\""
        echo "model = \"${escaped_model}\""
        if [[ -n "$base_url" && "$base_url" != "null" ]]; then
            echo "base_url = \"$(escape_toml_string "$base_url")\""
        fi
        echo "http_headers = {\"Authorization\" = \"Bearer $(escape_toml_string "$api_key")\"}"
        if [[ -n "$mcp_servers_content" ]]; then
            echo ""
            echo "# MCP Servers (preserved from previous config)"
            echo "$mcp_servers_content"
        fi
    } > "$tmp" || { rm -f "$tmp"; error "Failed to build Codex config content."; return 1; }

    mv "$tmp" "$CODEX_CONFIG_FILE"
    chmod 600 "$CODEX_CONFIG_FILE" 2>/dev/null || warn "Unable to set permissions on $CODEX_CONFIG_FILE"
}

function regenerate_agent_config() {
    local agent="${1:-all}"
    case "$agent" in
        claude)
            generate_claude_settings_json
            ;;
        codex)
            generate_codex_config_toml
            ;;
        all|"")
            generate_claude_settings_json || warn "Failed to regenerate Claude settings."
            generate_codex_config_toml || warn "Failed to regenerate Codex config."
            ;;
        *)
            error "Unknown agent '$agent' for regeneration. Supported: claude, codex."
            return 1
            ;;
    esac
}

# ============================================
# Command Handlers
# ============================================

function handle_provider_command() {
    local subcommand="${1:-help}"
    shift || true

    case "$subcommand" in
        add)
            provider_add "$@"
            ;;
        update)
            provider_update "$@"
            ;;
        remove)
            provider_remove "$@"
            ;;
        list)
            provider_list
            ;;
        info)
            provider_info "$@"
            ;;
        help|--help|-h)
            echo -e "${GREEN}gbox apikey provider - Provider catalog management${NC}"
            echo
            echo -e "${YELLOW}Usage:${NC}"
            echo "  gbox apikey provider add <name> <api_key> --claude-url <url> --codex-url <url> [--description <text>]"
            echo "  gbox apikey provider update <name> [<api_key>] [--claude-url <url>] [--codex-url <url>] [--description <text>]"
            echo "  gbox apikey provider remove <name>"
            echo "  gbox apikey provider list"
            echo "  gbox apikey provider info <name>"
            ;;
        *)
            error "Unknown provider subcommand '$subcommand'"
            return 1
            ;;
    esac
}

function handle_agent_command() {
    local agent="$1"
    local subcommand="${2:-help}"
    shift 2 || shift || true

    case "$subcommand" in
        set)
            agent_config_set "$agent" "$@"
            ;;
        remove)
            agent_config_remove "$agent" "$@"
            ;;
        set-default|default)
            agent_config_set_default "$agent" "$@"
            ;;
        enable)
            agent_config_enable "$agent"
            ;;
        disable)
            agent_config_disable "$agent"
            ;;
        list)
            agent_config_list "$agent"
            ;;
        status)
            agent_config_status "$agent"
            ;;
        help|--help|-h)
            echo -e "${GREEN}gbox apikey $agent - Configure $agent provider settings${NC}"
            echo
            echo -e "${YELLOW}Usage:${NC}"
            echo "  gbox apikey $agent set <provider> [options]"
            echo "  gbox apikey $agent remove <provider>"
            echo "  gbox apikey $agent set-default <provider>"
            echo "  gbox apikey $agent enable"
            echo "  gbox apikey $agent disable"
            echo "  gbox apikey $agent list"
            echo "  gbox apikey $agent status"
            echo
            echo -e "${YELLOW}Options for 'set':${NC}"
            if [[ "$agent" == "claude" ]]; then
                echo "  --timeout <ms> --haiku-model <model> --sonnet-model <model> --opus-model <model> --subagent-model <model>"
            else
                echo "  --model <model> --display-name <name>"
            fi
            ;;
        *)
            error "Unknown $agent subcommand '$subcommand'"
            return 1
            ;;
    esac
}

function handle_apikey_command() {
    local first="${1:-help}"
    shift || true

    case "$first" in
        provider)
            handle_provider_command "$@"
            ;;
        claude|codex)
            handle_agent_command "$first" "$@"
            ;;
        regenerate|regen)
            regenerate_agent_config "$@"
            ;;
        help|--help|-h)
            echo -e "${GREEN}gbox apikey - Unified provider management${NC}"
            echo
            echo -e "${YELLOW}Usage:${NC}"
            echo "  gbox apikey provider <subcommand>  Manage provider catalog (api keys, metadata)"
            echo "  gbox apikey <agent> <subcommand>   Configure agent provider settings"
            echo "  gbox apikey regenerate [agent]     Regenerate agent configs from catalog"
            echo
            echo -e "${YELLOW}Examples:${NC}"
            echo "  # Manage providers"
            echo "  gbox apikey provider add zhipu sk-xxx --claude-url https://open.bigmodel.cn/api/anthropic --codex-url https://open.bigmodel.cn/api/coding/paas/v4 --description \"ZhipuAI API\""
            echo "  gbox apikey provider list"
            echo "  gbox apikey provider info zhipu"
            echo
            echo "  # Configure Claude"
            echo "  gbox apikey claude set zhipu --timeout 3000000 --haiku-model glm-4.5-air"
            echo "  gbox apikey claude set-default zhipu"
            echo "  gbox apikey claude enable"
            echo "  gbox apikey claude status"
            echo
            echo "  # Configure Codex"
            echo "  gbox apikey codex set zhipu --model GLM-4.5-Air --display-name \"Zhi Pu\""
            echo "  gbox apikey codex enable"
            echo "  gbox apikey codex status"
            ;;
        *)
            error "Unknown command '$first'. Use 'provider', 'claude', or 'codex'."
            return 1
            ;;
    esac
}
