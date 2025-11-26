# gbox Zsh auto-completion plugin
# Support intelligent completion for gbox commands, including sub-commands, agents, and parameters

# Main completion function
_gbox() {
    local curcontext="$curcontext" state line
    typeset -A opt_args

    local -a commands agents gbox_opts keepalive_cmds oauth_cmds

    # Define main commands
    commands=(
        'list:List running containers'
        'status:Show detailed status of all containers'
        'stop:Stop and delete a container'
        'stop-all:Stop all containers'
        'clean:Clean up all stopped containers'
        'oauth:OAuth account management'
        'keepalive:Container keep-alive management'
        'pull:Pull pre-built image'
        'push:Push image to Docker Hub'
        'logs:View container logs'
        'exec:Execute command in container'
        'shell:Login to container shell'
        'build:Build container image'
        'apikey:API key and provider management'
        'help:Show help information'
        'happy:Start AI Agent (remote collaboration mode)'
    )

    # Define supported AI agents
    agents=(
        'claude:Claude Code'
        'codex:OpenAI Codex'
        'gemini:Google Gemini'
    )

    # keepalive sub-commands
    keepalive_cmds=(
        'list:List all keep-alive containers'
        'stop:Stop a specified keep-alive container'
        'stop-all:Stop all keep-alive containers'
        'restart:Restart keep-alive container'
        'logs:View keep-alive container logs'
        'auto:Automatically manage keep-alive containers'
        'help:Show keep-alive container help'
    )

    # oauth sub-commands
    oauth_cmds=(
        'help:Show OAuth help'
    )

    _arguments -C \
        '1: :->command' \
        '*::arg:->args'

    case $state in
        command)
            # First parameter: can be a command or agent
            _describe -t commands 'gbox commands' commands
            _describe -t agents 'AI agents' agents
            ;;
        args)
            case $line[1] in
                happy)
                    # Completion for gbox happy <agent>
                    if (( CURRENT == 2 )); then
                        _describe -t agents 'AI agents' agents
                    else
                        # Agent parameter following happy
                        _gbox_agent_options
                    fi
                    ;;
                claude|codex|gemini)
                    # Completion for gbox <agent>
                    _gbox_agent_options
                    ;;
                stop|logs|shell|exec)
                    # Commands that need container name, complete running containers
                    _gbox_containers
                    ;;
                oauth)
                    # oauth sub-command completion
                    if (( CURRENT == 2 )); then
                        _describe -t agents 'AI agents' agents
                    elif (( CURRENT == 3 )); then
                        _describe -t oauth_cmds 'oauth commands' oauth_cmds
                    fi
                    ;;
                apikey)
                    # apikey sub-command completion
                    _gbox_apikey
                    ;;
                keepalive)
                    # keepalive sub-command completion
                    if (( CURRENT == 2 )); then
                        _describe -t keepalive_cmds 'keepalive commands' keepalive_cmds
                    elif (( CURRENT == 3 )); then
                        case $line[2] in
                            stop|restart|logs)
                                # Complete account suffix for keep-alive container
                                _gbox_keepalive_accounts
                                ;;
                        esac
                    fi
                    ;;
                build)
                    # build parameter completion
                    if (( CURRENT == 2 )); then
                        _arguments '--no-cache[Force rebuild without using Docker cache]'
                    fi
                    ;;
                help)
                    # help parameter completion
                    if (( CURRENT == 2 )); then
                        _arguments '--full[Show full help documentation]'
                    fi
                    ;;
            esac
            ;;
    esac
}

# Agent parameter options completion
_gbox_agent_options() {
    # Check if the previous word was --ref-dir, if so complete directories
    if [[ "${words[CURRENT-1]}" == "--ref-dir" ]]; then
        _files -/
        return
    fi

    # Check if the previous word was other options that need values
    case "${words[CURRENT-1]}" in
        --memory|-m|--cpu|-c|--ports|--proxy|--name)
            # These options need values, don't complete options
            return
            ;;
    esac

    _arguments -s \
        '(--memory -m)'{--memory,-m}'[Memory limit (e.g., 4g, 8g, 16g)]:memory:' \
        '(--cpu -c)'{--cpu,-c}'[CPU cores (e.g., 2, 4, 8)]:cpus:' \
        '--ports[Port mapping (e.g., "8000:8000;7000:7001")]:ports:' \
        '*--ref-dir[Read-only reference directory (repeatable)]:directory:_files -/' \
        '--proxy[Agent network proxy (e.g., "http://127.0.0.1:7890")]:proxy:' \
        '--debug[Enable debug mode (happy:*)]' \
        '--keep[Keep container after exit]' \
        '--name[Custom container name]:name:' \
        '--[Pass remaining args to agent]'
}

# Complete running container names
_gbox_containers() {
    local -a containers
    # Get container names from docker ps
    containers=(${(f)"$(docker ps --filter 'name=gbox-' --format '{{.Names}}:{{.Status}}' 2>/dev/null)"})
    if (( ${#containers} > 0 )); then
        _describe -t containers 'running containers' containers
    fi
}

# Complete account suffix for keep-alive containers
_gbox_keepalive_accounts() {
    local -a accounts
    # Get account suffix for keep-alive containers from docker ps
    accounts=(${(f)"$(docker ps --filter 'name=gbox-keepalive-' --format '{{.Names}}' 2>/dev/null | sed 's/gbox-keepalive-//')"})
    if (( ${#accounts} > 0 )); then
        _describe -t accounts 'keepalive accounts' accounts
    fi
}

# apikey command completion
_gbox_apikey() {
    local -a apikey_cmds provider_cmds claude_cmds codex_cmds apikey_agents
    apikey_cmds=(
        'provider:Manage providers'
        'claude:Configure Claude provider'
        'codex:Configure Codex provider'
        'regenerate:Regenerate agent configs'
        'regen:Regenerate agent configs'
        'help:Show apikey help'
    )

    provider_cmds=(
        'add:Add new provider'
        'update:Update provider'
        'remove:Remove provider'
        'list:List all providers'
        'info:Show provider details'
        'help:Show provider help'
    )

    claude_cmds=(
        'set:Set provider for Claude'
        'remove:Remove Claude provider config'
        'set-default:Set default Claude provider'
        'default:Set default Claude provider'
        'enable:Enable Claude provider mode'
        'disable:Disable Claude provider mode'
        'list:List Claude configurations'
        'status:Show Claude status'
        'help:Show Claude help'
    )

    codex_cmds=(
        'set:Set provider for Codex'
        'remove:Remove Codex provider config'
        'set-default:Set default Codex provider'
        'default:Set default Codex provider'
        'enable:Enable Codex provider mode'
        'disable:Disable Codex provider mode'
        'list:List Codex configurations'
        'status:Show Codex status'
        'help:Show Codex help'
    )

    apikey_agents=(
        'claude:Claude Code'
        'codex:OpenAI Codex'
    )

    if (( CURRENT == 2 )); then
        _describe -t apikey_cmds 'apikey commands' apikey_cmds
        return
    fi

    case $line[2] in
        provider)
            if (( CURRENT == 3 )); then
                _describe -t provider_cmds 'provider commands' provider_cmds
                return
            fi

            case $line[3] in
                add)
                    if (( CURRENT == 4 || CURRENT == 5 )); then
                        _gbox_provider_names
                    else
                        _gbox_apikey_provider_opts
                    fi
                    ;;
                update)
                    if (( CURRENT == 4 )); then
                        _gbox_provider_names
                    elif (( CURRENT == 5 )); then
                        _gbox_provider_names
                        _gbox_apikey_provider_opts
                    else
                        _gbox_apikey_provider_opts
                    fi
                    ;;
                remove|info)
                    if (( CURRENT == 4 )); then
                        _gbox_provider_names
                    fi
                    ;;
                list|help)
                    ;;
            esac
            ;;
        claude|codex)
            local agent="$line[2]"
            local -a agent_cmds
            if [[ "$agent" == "claude" ]]; then
                agent_cmds=("${claude_cmds[@]}")
            else
                agent_cmds=("${codex_cmds[@]}")
            fi

            if (( CURRENT == 3 )); then
                _describe -t agent_cmds 'agent commands' agent_cmds
                return
            fi

            case $line[3] in
                set)
                    if (( CURRENT == 4 )); then
                        _gbox_provider_names
                    else
                        _gbox_apikey_agent_opts "$agent"
                    fi
                    ;;
                remove|set-default|default)
                    if (( CURRENT == 4 )); then
                        _gbox_provider_names
                    fi
                    ;;
                list|status|enable|disable|help)
                    ;;
            esac
            ;;
        regenerate|regen)
            if (( CURRENT == 3 )); then
                _describe -t apikey_agents 'agents' apikey_agents
            fi
            ;;
        help)
            ;;
    esac
}

# apikey provider options
_gbox_apikey_provider_opts() {
    local provider_opts
    provider_opts=(
        '--claude-url:Claude endpoint URL'
        '--codex-url:Codex endpoint URL'
        '--description:Provider description'
    )
    _describe -t provider_opts 'provider options' provider_opts
}

# apikey agent options
_gbox_apikey_agent_opts() {
    local agent="$1"
    local -a opts
    case "$agent" in
        claude)
            opts=(
                '--timeout:Request timeout (ms)'
                '--haiku-model:Claude Haiku model'
                '--sonnet-model:Claude Sonnet model'
                '--opus-model:Claude Opus model'
                '--subagent-model:Claude Subagent model'
            )
            ;;
        codex)
            opts=(
                '--model:Codex model ID'
                '--display-name:Provider display name'
            )
            ;;
    esac

    if (( ${#opts} > 0 )); then
        _describe -t agent_opts 'agent options' opts
    fi
}

# provider names from unified config
_gbox_provider_names() {
    local provider_file="$HOME/.gbox/providers.json"
    local -a providers

    if [[ -f "$provider_file" ]]; then
        if command -v jq >/dev/null 2>&1; then
            providers=(${(f)"$(jq -r '.providers | keys[]?' "$provider_file" 2>/dev/null)"})
        else
            providers=(${(f)"$(python - <<'PY'
import json
import pathlib
path = pathlib.Path("~/.gbox/providers.json").expanduser()
try:
    data = json.loads(path.read_text())
    providers = data.get("providers", {})
    if isinstance(providers, dict):
        for name in providers.keys():
            print(name)
except Exception:
    pass
PY
)"})
        fi
    fi

    if (( ${#providers} > 0 )); then
        _describe -t providers 'providers' providers
    fi
}

# Register completion function
compdef _gbox gbox

# Add common aliases (optional)
alias gb='gbox'
alias gbl='gbox list'
alias gbs='gbox status'
alias gbh='gbox happy'
alias gbc='gbox claude'
alias gbcd='gbox codex'
alias gbgm='gbox gemini'
