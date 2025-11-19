# gbox Zsh 自动补全插件
# 支持 gbox 命令的智能补全，包括子命令、agents 和参数

# 主补全函数
_gbox() {
    local curcontext="$curcontext" state line
    typeset -A opt_args

    local -a commands agents gbox_opts keepalive_cmds oauth_cmds

    # 定义主命令
    commands=(
        'list:列出运行中的容器'
        'status:显示所有容器详细状态'
        'stop:停止并删除容器'
        'stop-all:停止所有容器'
        'clean:清理所有停止的容器'
        'oauth:OAuth 账号管理'
        'keepalive:维持容器管理'
        'pull:拉取预构建镜像'
        'push:推送镜像到 Docker Hub'
        'logs:查看容器日志'
        'exec:在容器中执行命令'
        'shell:登录到容器 shell'
        'build:构建容器镜像'
        'help:显示帮助信息'
        'happy:启动 AI Agent(远程协作模式)'
    )

    # 定义支持的 AI agents
    agents=(
        'claude:Claude Code'
        'codex:OpenAI Codex'
        'gemini:Google Gemini'
    )

    # keepalive 子命令
    keepalive_cmds=(
        'list:列出所有维持容器'
        'stop:停止指定维持容器'
        'stop-all:停止所有维持容器'
        'restart:重启维持容器'
        'logs:查看维持容器日志'
        'auto:自动管理维持容器'
        'help:显示维持容器帮助'
    )

    # oauth 子命令
    oauth_cmds=(
        'help:显示 OAuth 帮助'
    )

    _arguments -C \
        '1: :->command' \
        '*::arg:->args'

    case $state in
        command)
            # 第一个参数:可以是命令或 agent
            _describe -t commands 'gbox commands' commands
            _describe -t agents 'AI agents' agents
            ;;
        args)
            case $line[1] in
                happy)
                    # gbox happy <agent> 的补全
                    if (( CURRENT == 2 )); then
                        _describe -t agents 'AI agents' agents
                    else
                        # happy 后面的 agent 参数
                        _gbox_agent_options
                    fi
                    ;;
                claude|codex|gemini)
                    # gbox <agent> 的补全
                    _gbox_agent_options
                    ;;
                stop|logs|shell|exec)
                    # 需要容器名的命令,补全运行中的容器
                    _gbox_containers
                    ;;
                oauth)
                    # oauth 子命令补全
                    if (( CURRENT == 2 )); then
                        _describe -t agents 'AI agents' agents
                    elif (( CURRENT == 3 )); then
                        _describe -t oauth_cmds 'oauth commands' oauth_cmds
                    fi
                    ;;
                keepalive)
                    # keepalive 子命令补全
                    if (( CURRENT == 2 )); then
                        _describe -t keepalive_cmds 'keepalive commands' keepalive_cmds
                    elif (( CURRENT == 3 )); then
                        case $line[2] in
                            stop|restart|logs)
                                # 补全维持容器的账号后缀
                                _gbox_keepalive_accounts
                                ;;
                        esac
                    fi
                    ;;
                help)
                    # help 参数补全
                    if (( CURRENT == 2 )); then
                        _arguments '--full[显示完整帮助文档]'
                    fi
                    ;;
            esac
            ;;
    esac
}

# agent 参数选项补全
_gbox_agent_options() {
    local gbox_opts
    gbox_opts=(
        '--memory:内存限制(如 4g, 8g, 16g)'
        '-m:内存限制(如 4g, 8g, 16g)'
        '--cpu:CPU 核心数(如 2, 4, 8)'
        '-c:CPU 核心数(如 2, 4, 8)'
        '--ports:端口映射(如 "8000:8000;7000:7001")'
        '--ref-dirs:只读参考目录(如 "/path/to/ref1;/path/to/ref2")'
        '--proxy:Agent 网络代理(如 "http://127.0.0.1:7890")'
        '--api-key:Anthropic API Key(如 "sk-xxx")'
        '--debug:启用调试模式(happy:*)'
        '--model:指定模型(如 sonnet, opus, haiku)'
        '--keep:退出后保留容器'
        '--name:自定义容器名'
    )

    _describe -t gbox_opts 'gbox options' gbox_opts
}

# 补全运行中的容器名
_gbox_containers() {
    local -a containers
    # 从 docker ps 获取容器名
    containers=(${(f)"$(docker ps --filter 'name=gbox-' --format '{{.Names}}:{{.Status}}' 2>/dev/null)"})
    if (( ${#containers} > 0 )); then
        _describe -t containers 'running containers' containers
    fi
}

# 补全维持容器的账号后缀
_gbox_keepalive_accounts() {
    local -a accounts
    # 从 docker ps 获取维持容器的账号后缀
    accounts=(${(f)"$(docker ps --filter 'name=gbox-keepalive-' --format '{{.Names}}' 2>/dev/null | sed 's/gbox-keepalive-//')"})
    if (( ${#accounts} > 0 )); then
        _describe -t accounts 'keepalive accounts' accounts
    fi
}

# 注册补全函数
compdef _gbox gbox

# 添加常用别名(可选)
alias gb='gbox'
alias gbl='gbox list'
alias gbs='gbox status'
alias gbh='gbox happy'
alias gbc='gbox claude'
alias gbcd='gbox codex'
alias gbgm='gbox gemini'
