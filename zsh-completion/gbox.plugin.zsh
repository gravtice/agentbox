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
    local gbox_opts
    gbox_opts=(
        '--memory:Memory limit (e.g., 4g, 8g, 16g)'
        '-m:Memory limit (e.g., 4g, 8g, 16g)'
        '--cpu:CPU cores (e.g., 2, 4, 8)'
        '-c:CPU cores (e.g., 2, 4, 8)'
        '--ports:Port mapping (e.g., "8000:8000;7000:7001")'
        '--ref-dirs:Read-only reference directories (e.g., "/path/to/ref1;/path/to/ref2")'
        '--proxy:Agent network proxy (e.g., "http://127.0.0.1:7890")'
        '--api-key:Anthropic API Key (e.g., "sk-xxx")'
        '--debug:Enable debug mode (happy:*)'
        '--model:Specify model (e.g., sonnet, opus, haiku)'
        '--keep:Keep container after exit'
        '--name:Custom container name'
    )

    _describe -t gbox_opts 'gbox options' gbox_opts
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
