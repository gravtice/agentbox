#!/bin/bash
# lib/common.sh - 通用工具和常量
# 这个模块包含全局常量、颜色定义、环境检查和工具函数

# ============================================
# 全局常量定义
# ============================================

# 从 VERSION 文件读取版本号
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
    VERSION=$(cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')
else
    # 回退到默认版本号
    VERSION="1.0.0"
    echo "警告: 找不到 VERSION 文件，使用默认版本号 $VERSION" >&2
fi

# 镜像配置
IMAGE_NAME="gravtice/agentbox"
IMAGE_TAG="$VERSION"
IMAGE_FULL="${IMAGE_NAME}:${IMAGE_TAG}"

# 容器配置
CONTAINER_PREFIX="gbox"
NETWORK_NAME="gbox-network"

# 目录配置
GBOX_CONFIG_DIR="$HOME/.gbox"                     # gbox 配置根目录
GBOX_CLAUDE_DIR="$GBOX_CONFIG_DIR/claude"         # Claude 配置目录
GBOX_CODEX_DIR="$GBOX_CONFIG_DIR/codex"           # Codex 配置目录
GBOX_GEMINI_DIR="$GBOX_CONFIG_DIR/gemini"         # Gemini 配置目录
GBOX_HAPPY_DIR="$GBOX_CONFIG_DIR/happy"           # Happy 配置目录
STATE_FILE="$GBOX_CONFIG_DIR/containers.json"     # 容器状态文件
LOGS_DIR="$GBOX_CONFIG_DIR/logs"                  # 日志目录
CACHE_DIR="$GBOX_CONFIG_DIR/cache"                # 缓存目录

# 资源限制配置（默认值，可被环境变量或命令行参数覆盖）
DEFAULT_MEMORY_LIMIT="4g"
DEFAULT_CPU_LIMIT="2"

# 实际使用的资源限制（优先级：命令行 > 环境变量 > 默认值）
MEMORY_LIMIT="${GBOX_MEMORY:-${DEFAULT_MEMORY_LIMIT}}"
CPU_LIMIT="${GBOX_CPU:-${DEFAULT_CPU_LIMIT}}"
CONTAINER_PORTS="${GBOX_PORTS:-}"                 # 端口映射配置
CONTAINER_KEEP="${GBOX_KEEP:-false}"              # 是否保留容器
CONTAINER_NAME="${GBOX_NAME:-}"                   # 自定义容器名
CONTAINER_REF_DIRS="${GBOX_REF_DIRS:-}"           # 只读参考目录列表
AGENT_PROXY="${GBOX_PROXY:-}"                     # 代理地址（传递给 Agent）
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"        # Anthropic API Key
DEBUG="${DEBUG:-}"                                # 调试模式（如 happy:*）
REF_DIR_MOUNT_ARGS=()                             # Docker -v 参数（数组）
REF_DIR_SOURCE_DIRS=()                            # 用于展示的参考目录列表

# 支持的 AI Agent 列表
SUPPORTED_AGENTS=("claude" "codex" "gemini")

# ============================================
# 颜色输出
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# ============================================
# 系统检测
# ============================================

# 检查是否支持 flock（Linux 有，macOS 默认没有）
HAS_FLOCK=0
if command -v flock &> /dev/null; then
    HAS_FLOCK=1
fi

# ============================================
# 环境检查函数
# ============================================

function check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误: Docker未安装或未运行${NC}"
        exit 1
    fi
}

function check_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}错误: jq未安装，请先安装: brew install jq${NC}"
        exit 1
    fi
}

# ============================================
# 环境变量加载
# ============================================

# 加载 .env 文件
# 优先级: 命令行参数 > .env.local > .env > 默认值
function load_env_files() {
    local env_file="$SCRIPT_DIR/.env"
    local env_local_file="$SCRIPT_DIR/.env.local"

    # 加载 .env 文件
    if [[ -f "$env_file" ]]; then
        if [[ "${GBOX_DEBUG:-0}" == "1" ]]; then
            echo -e "${BLUE}加载配置文件: $env_file${NC}" >&2
        fi

        # 逐行读取并导出变量（跳过注释和空行）
        while IFS= read -r line || [[ -n "$line" ]]; do
            # 跳过注释和空行
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # 解析变量名和值
            if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
                local var_name="${BASH_REMATCH[1]}"
                local var_value="${BASH_REMATCH[2]}"

                # 移除值两边的引号（如果有）
                var_value="${var_value#\"}"
                var_value="${var_value%\"}"
                var_value="${var_value#\'}"
                var_value="${var_value%\'}"

                # 只在变量未设置时才导出（命令行参数优先）
                if [[ -z "${!var_name}" ]]; then
                    export "$var_name=$var_value"
                    if [[ "${GBOX_DEBUG:-0}" == "1" ]]; then
                        echo -e "${BLUE}  导出: $var_name=$var_value${NC}" >&2
                    fi
                fi
            fi
        done < "$env_file"
    fi

    # 加载 .env.local 文件（优先级更高）
    if [[ -f "$env_local_file" ]]; then
        if [[ "${GBOX_DEBUG:-0}" == "1" ]]; then
            echo -e "${BLUE}加载配置文件: $env_local_file${NC}" >&2
        fi

        # 逐行读取并导出变量（跳过注释和空行）
        while IFS= read -r line || [[ -n "$line" ]]; do
            # 跳过注释和空行
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # 解析变量名和值
            if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
                local var_name="${BASH_REMATCH[1]}"
                local var_value="${BASH_REMATCH[2]}"

                # 移除值两边的引号（如果有）
                var_value="${var_value#\"}"
                var_value="${var_value%\"}"
                var_value="${var_value#\'}"
                var_value="${var_value%\'}"

                # .env.local 会覆盖 .env 中的设置，但不会覆盖命令行参数
                # 通过检查变量是否在环境中已存在来判断是否来自命令行
                if [[ -z "${!var_name}" ]]; then
                    export "$var_name=$var_value"
                    if [[ "${GBOX_DEBUG:-0}" == "1" ]]; then
                        echo -e "${BLUE}  导出: $var_name=$var_value${NC}" >&2
                    fi
                fi
            fi
        done < "$env_local_file"
    fi
}

# ============================================
# 工具函数
# ============================================

# 验证容器名是否符合 Docker 命名规范
function validate_container_name() {
    local name="$1"
    # 只允许：字母、数字、下划线、点、连字符
    # 不能以点或连字符开头
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        echo -e "${RED}错误: 容器名 '$name' 不符合命名规范${NC}"
        echo -e "${YELLOW}容器名只能包含: 字母、数字、下划线、点、连字符${NC}"
        echo -e "${YELLOW}且必须以字母或数字开头${NC}"
        return 1
    fi
    return 0
}

# 验证 agent 是否支持
function is_valid_agent() {
    local agent="$1"
    for supported in "${SUPPORTED_AGENTS[@]}"; do
        if [[ "$agent" == "$supported" ]]; then
            return 0
        fi
    done
    return 1
}

# 查找可用端口
function find_available_port() {
    local start_port=8001
    local end_port=8010

    for port in $(seq $start_port $end_port); do
        if ! lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo $port
            return 0
        fi
    done

    echo -e "${RED}错误: 端口 $start_port-$end_port 全部被占用${NC}" >&2
    return 1
}

# Email 转 suffix（email-safe 格式）
# 示例: agent@gravtice.com -> agent-at-gravtice-com
function email_to_suffix() {
    local email="$1"
    echo "$email" | tr '[:upper:]' '[:lower:]' | sed 's/@/-at-/g' | sed 's/\./-/g'
}

# 解析并验证只读参考目录列表，并填充 REF_DIR_MOUNT_ARGS/REF_DIR_SOURCE_DIRS 数组
function parse_ref_dirs() {
    local ref_dirs_config="$1"
    local work_dir="$2"       # 当前工作目录，用于避免冲突
    REF_DIR_MOUNT_ARGS=()
    REF_DIR_SOURCE_DIRS=()

    # 如果为空，不挂载任何参考目录
    if [[ -z "$ref_dirs_config" ]]; then
        return 0
    fi

    # 将分号替换为换行符，保存到临时文件避免子 shell 问题
    local temp_file=$(mktemp)
    echo "$ref_dirs_config" | tr ';' '\n' > "$temp_file"

    # 逐行读取并处理
    while IFS= read -r dir_item; do
        dir_item=$(echo "$dir_item" | xargs)  # 去除空格
        [[ -z "$dir_item" ]] && continue

        # 转换为绝对路径
        local abs_dir
        if [[ "$dir_item" =~ ^/ ]]; then
            # 已经是绝对路径
            abs_dir="$dir_item"
        else
            # 相对路径，转换为绝对路径
            abs_dir=$(cd "$dir_item" 2>/dev/null && pwd)
            if [[ $? -ne 0 ]]; then
                echo -e "${YELLOW}警告: 目录不存在或无法访问 '$dir_item'，跳过${NC}" >&2
                continue
            fi
        fi

        # 验证目录存在
        if [[ ! -d "$abs_dir" ]]; then
            echo -e "${YELLOW}警告: 目录不存在 '$abs_dir'，跳过${NC}" >&2
            continue
        fi

        # 验证不与工作目录冲突
        if [[ "$abs_dir" == "$work_dir" ]]; then
            echo -e "${YELLOW}警告: 参考目录与工作目录相同 '$abs_dir'，跳过（工作目录已自动挂载）${NC}" >&2
            continue
        fi

        # 验证不是工作目录的子目录或父目录
        if [[ "$abs_dir" == "$work_dir"/* ]] || [[ "$work_dir" == "$abs_dir"/* ]]; then
            echo -e "${YELLOW}警告: 参考目录与工作目录有包含关系 '$abs_dir'，跳过${NC}" >&2
            continue
        fi

        # 添加到结果（以只读模式挂载到相同路径）
        REF_DIR_MOUNT_ARGS+=(-v "$abs_dir:$abs_dir:ro")
        REF_DIR_SOURCE_DIRS+=("$abs_dir")
    done < "$temp_file"

    # 清理临时文件
    rm -f "$temp_file"
}

# ============================================
# 帮助文档
# ============================================

function print_usage() {
    local show_full="${1:-}"

    cat <<EOF
gbox - Gravtice AgentBox v${VERSION}

快速开始:
    cd ~/myproject
    gbox claude                                 # 运行 Claude Code（本地模式）
    gbox happy claude                           # 运行 Claude Code（远程协作模式）

常用命令:
    gbox <agent> [-- <参数>]                    启动 AI Agent（本地模式）
    gbox happy <agent> [-- <参数>]              启动 AI Agent（远程协作模式）
    gbox list                                   列出运行中的容器
    gbox stop <容器名>                          停止并删除容器
    gbox stop-all                               停止所有容器
    gbox logs <容器名>                          查看容器日志
    gbox shell <容器名>                         登录到容器 shell

高级功能:
    gbox oauth <cmd>                            OAuth 账号管理
    gbox keepalive <cmd>                        维持容器管理
    gbox build                                  构建容器镜像
    gbox pull [tag]                             拉取预构建镜像
    gbox status                                 显示所有容器详细状态
    gbox exec <容器名> <命令>                   在容器中执行命令
    gbox clean                                  清理所有停止的容器

支持的 AI Agent:
    claude          Claude Code
    codex           Codex
    gemini          Google Gemini

使用示例:
    gbox claude -- --model=sonnet               # 传递参数给 claude
    gbox happy claude -- --resume <id>          # 恢复远程会话
    gbox gemini                                  # 运行 Gemini CLI
    gbox oauth claude help                      # OAuth 帮助

更多帮助:
    gbox help --full                            # 显示完整帮助文档
    gbox oauth help                             # OAuth 详细帮助
    gbox keepalive help                         # 维持容器帮助
EOF

    # 显示详细帮助
    if [[ "$show_full" == "--full" ]]; then
        cat <<'FULLEOF'

═══════════════════════════════════════════════════════════════
                        完整帮助文档
═══════════════════════════════════════════════════════════════

运行模式详解:
    only-local      本地模式 - 直接在容器内运行 AI Agent
    local-remote    远程协作模式 - 支持远程客户端协作（基于 happy-coder）

容器管理详解:
    # 退出 agent 后容器默认保留，可直接再次运行复用
    # 如需自动清理：GBOX_AUTO_CLEANUP=1 gbox claude

    gbox list                                   # 查看运行中的容器
    gbox status                                 # 查看所有容器状态
    gbox stop gbox-claude-myproject            # 停止并删除容器
    gbox stop-all                               # 停止所有容器
    gbox shell gbox-claude-myproject           # 登录到容器 shell
    gbox exec gbox-claude-myproject "ls -la"   # 在容器中执行命令
    gbox logs gbox-claude-myproject            # 查看容器日志

OAuth 账号管理:
    gbox oauth claude switch --limit 2025120111                         # 账号达到限制时切换(指定时间)
    gbox oauth claude switch --limit-str "resets Nov 9, 5pm"           # 账号达到限制时切换(自动解析)
    gbox oauth claude switch                                            # 主动切换账号
    gbox oauth claude help                                              # 显示 OAuth 帮助

    # 支持多账号管理,在账号达到使用限制时自动切换到可用账号
    # 账号配置存储在 ~/.gbox/claude,所有容器共享

维持容器管理:
    gbox keepalive list                         # 列出所有维持容器
    gbox keepalive stop <account-suffix>        # 停止指定维持容器
    gbox keepalive stop-all                     # 停止所有维持容器
    gbox keepalive logs <account-suffix>        # 查看维持容器日志
    gbox keepalive help                         # 显示维持容器帮助

    # 维持容器用于保持非活跃账号的登录态
    # 切换账号时自动启动,切换回来时自动停止
    # 资源占用低(256MB内存,0.25核CPU)

镜像构建与分发:
    gbox build                                  # 构建镜像（包含 Playwright）
    gbox pull [tag]                             # 拉取预构建镜像
    gbox push [tag]                             # 推送镜像到 Docker Hub

    # 镜像仓库: docker.io/gravtice/agentbox
    # 推送需要先登录: docker login

容器资源配置:
    # 方式1: 使用 .env 文件（推荐）
    # 复制 .env.example 为 .env 或 .env.local 进行配置
    # 优先级: 命令行参数 > .env.local > .env > 默认值
    cp .env.example .env
    # 编辑 .env 文件设置常用配置
    # 编辑 .env.local 文件设置本地特定配置（不提交到git）

    # 方式2: 通过环境变量设置
    GBOX_MEMORY=8g                              容器内存限制（默认: 4g）
    GBOX_CPU=4                                  容器 CPU 核心数（默认: 2）
    GBOX_PORTS="8000:8000;7000:7001"            端口映射配置（默认: 不映射任何端口）
    GBOX_REF_DIRS="/path/to/ref1;/path/to/ref2" 只读参考目录（默认: 无）
    GBOX_PROXY="http://127.0.0.1:7890"          Agent 网络代理（默认: 无）
    ANTHROPIC_API_KEY=sk-xxx                    Anthropic API Key（默认: 无）
    DEBUG=happy:*                               调试模式（默认: 无）
    GBOX_KEEP=true                              退出后保留容器（默认: false）
    GBOX_NAME=my-container                      自定义容器名（默认: 自动生成）

    # 端口映射格式说明:
    # - 格式: "host_port:container_port" (分号分隔多个端口)
    # - 示例:
    #   GBOX_PORTS="8000:8000"              # 宿主机 8000 -> 容器 8000
    #   GBOX_PORTS="8080:8000"              # 宿主机 8080 -> 容器 8000
    #   GBOX_PORTS="8000:8000;7000:7001"    # 多端口: 8000->8000, 7000->7001
    # - 所有端口映射到 127.0.0.1 (仅本地访问)
    # - 默认不映射任何端口，需要时通过 GBOX_PORTS 显式配置

    # 只读参考目录格式说明:
    # - 格式: "目录路径" (分号分隔多个目录)
    # - 示例:
    #   GBOX_REF_DIRS="/Users/me/project1"                        # 单个参考目录
    #   GBOX_REF_DIRS="/Users/me/project1;/Users/me/project2"    # 多个参考目录
    # - 所有目录以只读方式挂载到容器中的相同路径
    # - 用于为 AI Agent 提供其他项目的代码参考
    # - 自动验证目录存在性和路径冲突

    # 通过命令行参数设置（优先级高于环境变量）
    gbox claude --memory 8g --cpu 4 -- --model sonnet
    gbox happy claude -m 16g -c 8 -- --resume <session-id>
    gbox claude --ref-dirs "/path/to/ref1;/path/to/ref2"
    gbox claude --api-key sk-xxx --debug

    # 可用参数:
    --memory, -m <value>       内存限制（如 4g, 8g, 16g）
    --cpu, -c <value>          CPU 核心数（如 2, 4, 8）
    --ports <value>            端口映射（如 "8000:8000;7000:7001"）
    --ref-dirs <value>         只读参考目录（如 "/path/to/ref1;/path/to/ref2"）
    --proxy <value>            Agent 网络代理（如 "http://127.0.0.1:7890"）
    --api-key <value>          Anthropic API Key（如 "sk-xxx"）
    --debug                    启用调试模式（happy:*）
    --keep                     退出后保留容器
    --name <value>             自定义容器名

其他环境变量:
    GBOX_AUTO_CLEANUP=1       退出后自动清理容器（默认保留容器）
    GBOX_DEBUG=1              启用调试模式
    GBOX_READY_ATTEMPTS=30    容器就绪检查次数
    GBOX_READY_DELAY=0.2      检查间隔（秒）

特性列表:
    ✅ 两种运行模式：本地模式（only-local）和远程协作模式（local-remote）
    ✅ 多个 AI Agent：支持 claude、codex、gemini 等
    ✅ 自动管理：基于当前目录和运行模式自动管理容器
    ✅ 参数透传：支持 -- 分隔符传递参数
    ✅ 配置持久化：配置存储在 ~/.gbox/{claude,happy}
    ✅ 容器隔离：每个项目+模式独立容器，互不干扰
    ✅ 资源限制：自动限制内存和CPU，启用依赖缓存
FULLEOF
    fi
}
