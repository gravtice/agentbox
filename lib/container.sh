#!/bin/bash
# lib/container.sh - 容器生命周期管理
# 依赖 common.sh/state.sh/docker.sh 提供的变量和函数

# ============================================
# 容器环境准备
# ============================================

function prepare_container_environment() {
    local container_name="$1"
    local user_id="$2"
    local group_id="$3"
    local quiet="${4:-0}"

    local prepare_cmd
    prepare_cmd=$(cat <<EOF
# 删除容器标识文件
rm -f /.dockerenv
rm -f /run/.containerenv

# Git 配置通过挂载 ~/.gbox/.gitconfig 提供
# 验证配置是否正确挂载
if [[ -f \$HOME/.gitconfig ]]; then
    echo '✅ Git配置已挂载'
else
    echo '⚠️  警告: Git配置文件未找到'
fi

# 创建用户（与宿主机UID/GID一致）
groupadd -g ${group_id} guser 2>/dev/null || true
useradd -u ${user_id} -g ${group_id} -d \$HOME -s /bin/bash guser 2>/dev/null || true

# 确保整个 HOME 目录归 guser 所有（包括所有挂载点和子目录）
# 这样任何程序都可以在 HOME 下创建配置文件和缓存目录
chown -R ${user_id}:${group_id} \$HOME 2>/dev/null || true

# 清理 Playwright 锁定目录（激进策略）
# Playwright MCP 使用固定的目录名，容易产生锁定问题
# 每次启动都清理，确保环境干净（用户数据不重要，可重新登录）
find /usr/local/share/playwright -maxdepth 1 -name "mcp-chrome-*" -type d -exec rm -rf {} + 2>/dev/null || true

# 同时清理可能残留的 Chrome 进程（使用 kill 而不是 pkill，避免挂起）
ps aux | grep -E 'chrome.*--user-data-dir=/usr/local/share/playwright' | grep -v grep | awk '{print \$2}' | xargs -r kill -9 2>/dev/null || true

# Claude Code 配置文件路径处理：
# - Claude Code 期望配置在 \$HOME/.claude.json
# - 为了所有容器共享配置，我们挂载 ~/.gbox/claude/ 到 \$HOME/.claude/
# - 实际配置文件在 \$HOME/.claude/.claude.json
# - 创建符号链接：\$HOME/.claude.json -> \$HOME/.claude/.claude.json

# 确保 .claude/.claude.json 存在
if [[ ! -f \$HOME/.claude/.claude.json ]]; then
    echo '{}' > \$HOME/.claude/.claude.json
    chown ${user_id}:${group_id} \$HOME/.claude/.claude.json
    echo '📝 创建新的 Claude 配置文件'
fi

# 创建符号链接（如果不存在）
if [[ ! -e \$HOME/.claude.json ]]; then
    ln -s \$HOME/.claude/.claude.json \$HOME/.claude.json
    echo '✅ 创建配置文件符号链接: \$HOME/.claude.json -> \$HOME/.claude/.claude.json'
fi

# 验证 OAuth 配置
if grep -q '\"oauthAccount\"' \$HOME/.claude/.claude.json 2>/dev/null; then
    echo '✅ 检测到 Claude OAuth 认证配置（所有容器共享）'
else
    echo '📝 首次使用 Claude，需要登录 Claude Code'
    echo '   启动后请完成 OAuth 登录，认证信息将保存在 ~/.gbox/claude/.claude.json'
fi

# Codex 配置文件路径处理：
# - Codex 使用 \$HOME/.codex/config.toml
# - 为了所有容器共享配置，我们挂载 ~/.gbox/codex/ 到 \$HOME/.codex/

# 确保 .codex 目录存在并属于 guser
if [[ ! -d \$HOME/.codex ]]; then
    mkdir -p \$HOME/.codex
    chown ${user_id}:${group_id} \$HOME/.codex
    echo '📝 创建 Codex 配置目录'
fi

# 如果 config.toml 不存在，创建一个基础配置
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
    echo '📝 创建默认 Codex 配置文件（包含 Playwright MCP 支持）'
fi

# Happy 登录态共享处理：
# - 每个容器有独立的 happy 配置目录（包含独立的 machineId 和 daemon state）
# - 但所有容器共享登录凭证（access.key）以避免重复登录
# - 通过符号链接实现：\$HOME/.happy/access.key -> \$HOME/.happy-shared/access.key

# 确保共享目录存在
if [[ ! -d \$HOME/.happy-shared ]]; then
    mkdir -p \$HOME/.happy-shared
    chown ${user_id}:${group_id} \$HOME/.happy-shared
    echo '📝 创建 Happy 共享配置目录'
fi

# 处理 access.key 的共享
# 场景1：当前容器有 access.key 但不是符号链接（旧数据或新登录）-> 移动到 shared/
if [[ -f \$HOME/.happy/access.key ]] && [[ ! -L \$HOME/.happy/access.key ]]; then
    mv \$HOME/.happy/access.key \$HOME/.happy-shared/access.key
    chown ${user_id}:${group_id} \$HOME/.happy-shared/access.key
    echo '📦 迁移登录凭证到共享目录'
fi

# 场景2：shared/ 有 access.key，但当前容器没有 -> 创建符号链接
if [[ -f \$HOME/.happy-shared/access.key ]] && [[ ! -e \$HOME/.happy/access.key ]]; then
    ln -s \$HOME/.happy-shared/access.key \$HOME/.happy/access.key
    echo '✅ 创建登录凭证符号链接（所有容器共享登录态）'
fi

# 验证登录态
if [[ -f \$HOME/.happy-shared/access.key ]]; then
    echo '✅ 检测到 Happy 登录凭证（所有容器共享）'
else
    echo '📝 首次使用 Happy，需要登录'
    echo '   启动后请运行: happy auth login'
fi

# 验证 Happy 环境变量配置
echo '✅ Happy 权限配置已设置（通过环境变量）'
echo '   HAPPY_AUTO_BYPASS_PERMISSIONS=1 将在所有模式下自动跳过权限'
EOF
    )

    if (( quiet == 0 )); then
        echo -e "${YELLOW}正在准备环境...${NC}"
        docker exec "$container_name" bash -c "$prepare_cmd"
        echo ""
        echo -e "${GREEN}✓ 环境准备完成！${NC}"
        echo ""
        echo -e "${BLUE}下一步：${NC}"
        echo -e "  ${YELLOW}./gbox claude $container_name${NC}  # 启动 Claude Code"
        echo ""
    else
        docker exec "$container_name" bash -c "$prepare_cmd" >/dev/null
    fi
}

# ============================================
# 容器创建与启动
# ============================================

function start_container() {
    local container_name="$1"
    local work_dir="${2:-.}"
    local run_mode="${3:-only-local}"  # only-local 或 local-remote
    local agent="${4:-claude}"  # claude 或 codex
    local quiet_mode=0

    # 确保镜像存在
    ensure_image

    # 验证容器名是否为空
    if [[ -z "$container_name" ]]; then
        echo -e "${RED}错误: 请指定容器名${NC}"
        echo -e "${YELLOW}用法: ./gbox new <容器名> [工作目录]${NC}"
        echo -e "${YELLOW}示例: ./gbox new myproject${NC}"
        exit 1
    fi

    # 验证容器名格式
    if ! validate_container_name "$container_name"; then
        exit 1
    fi

    # 转换为绝对路径
    work_dir=$(cd "$work_dir" && pwd)

    # 检查目录是否存在
    if [[ ! -d "$work_dir" ]]; then
        echo -e "${RED}错误: 工作目录不存在: $work_dir${NC}"
        exit 1
    fi

    # 检查是否是git仓库
    if [[ ! -d "$work_dir/.git" ]]; then
        if (( quiet_mode == 0 )); then
            echo -e "${YELLOW}警告: $work_dir 不是git仓库或worktree${NC}"
        fi
    fi

    # 检查容器名是否已存在
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${RED}错误: 容器名 $container_name 已存在${NC}"
        echo -e "${YELLOW}提示: 使用 './gbox list' 查看所有容器${NC}"
        echo -e "${YELLOW}或者: 使用不同的容器名${NC}"
        exit 1
    fi

    # 解析端口映射配置
    local port_mappings=$(parse_port_mappings "$CONTAINER_PORTS" "$run_mode")

    # 解析只读参考目录配置
    parse_ref_dirs "$CONTAINER_REF_DIRS" "$work_dir"
    local -a ref_dir_mappings=("${REF_DIR_MOUNT_ARGS[@]}")
    local -a ref_dir_sources=("${REF_DIR_SOURCE_DIRS[@]}")

    # 确保网络存在
    ensure_network

    # 获取主仓库目录（如果是 worktree，会返回主仓库目录）
    local main_dir=$(get_main_repo_dir "$work_dir")

    # 确保 worktrees 目录存在并获取路径（基于主仓库目录）
    local worktree_dir=$(ensure_worktree_dir "$main_dir" "$quiet_mode")

    # 容器日志文件
    local log_file="$LOGS_DIR/${container_name}.log"

    if (( quiet_mode == 0 )); then
        echo -e "${GREEN}启动新容器...${NC}"
        echo -e "  运行模式: ${BLUE}$run_mode${NC}"
        echo -e "  AI Agent: ${BLUE}$agent${NC}"
        echo -e "  主仓库目录: ${BLUE}$main_dir${NC}"
        echo -e "  工作目录: ${BLUE}$work_dir${NC}"
        echo -e "  Worktrees目录: ${BLUE}$worktree_dir${NC}"
        echo -e "  容器名: ${BLUE}$container_name${NC}"
        if [[ -n "$port_mappings" ]]; then
            echo -e "  端口映射: ${BLUE}${port_mappings//-p /}${NC}"
        else
            echo -e "  端口映射: ${BLUE}无 (仅容器内网络)${NC}"
        fi
        if (( ${#ref_dir_sources[@]} > 0 )); then
            # 统计参考目录数量
            local ref_count=${#ref_dir_sources[@]}
            echo -e "  参考目录: ${BLUE}${ref_count} 个只读目录${NC}"
            for src_dir in "${ref_dir_sources[@]}"; do
                echo -e "    - ${BLUE}${src_dir}${NC} (只读)"
            done
        fi
        echo -e "  用户权限: ${BLUE}$(id -u):$(id -g)${NC}"
        echo -e "  免权限模式: ${BLUE}启用${NC}"
        echo -e "  资源限制: ${BLUE}内存=${MEMORY_LIMIT}, CPU=${CPU_LIMIT}核${NC}"
        echo -e "  文件描述符: ${BLUE}65536${NC}"
        echo -e "  TCP Keepalive: ${BLUE}5分钟 (优化长连接稳定性)${NC}"
        echo -e "  依赖缓存: ${BLUE}启用 (pip/npm/uv)${NC}"
        echo -e "  容器日志: ${BLUE}$log_file${NC}"
        echo -e "  网络模式: ${BLUE}$NETWORK_NAME${NC}"
        echo -e "  Claude配置: ${BLUE}$GBOX_CLAUDE_DIR${NC}"
        echo -e "  Codex配置: ${BLUE}$GBOX_CODEX_DIR${NC}"
        echo -e "  Gemini配置: ${BLUE}$GBOX_GEMINI_DIR${NC}"
        echo -e "  Happy配置: ${BLUE}$GBOX_HAPPY_DIR${NC}"
        echo ""
    fi

    # 获取当前用户的UID和GID
    local user_id=$(id -u)
    local group_id=$(id -g)

    # 设置容器 hostname：使用容器名，确保每个容器都有独立的标识
    local container_hostname="$container_name"

    # 启动容器到后台
    # 新策略: gbox 独立配置体系
    #   - 所有 Claude 配置存储在宿主机 ~/.gbox/claude 目录
    #   - 所有 Codex 配置存储在宿主机 ~/.gbox/codex 目录
    #   - 所有 Gemini 配置存储在宿主机 ~/.gbox/gemini 目录
    #   - 所有 Happy 配置存储在宿主机 ~/.gbox/happy 目录
    #   - 直接 bind mount 到容器的 ~/.claude、~/.codex、~/.gemini 和 ~/.happy 目录
    #   - 所有容器共享同一份配置（OAuth、CLAUDE.md、config.toml 等）
    #   - 宿主机可以直接编辑 ~/.gbox/{claude,codex,gemini,happy} 下的文件
    #   - Linux 容器之间可以共享 OAuth 认证
    #   - worktrees 目录用于 git worktree 并行开发
    #   - 主目录和 worktrees 目录都挂载到容器中，确保 worktree 可以访问主仓库
    #   - 支持挂载只读参考目录，用于提供代码参考
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
        echo -e "${GREEN}✓ 容器已启动到后台${NC}"
        echo ""
    fi

    if ! wait_for_container_ready "$container_name"; then
        echo -e "${RED}错误: 容器 $container_name 启动后未能在预期时间内准备就绪${NC}"
        echo -e "${YELLOW}请检查容器日志: gbox logs $container_name${NC}"
        docker rm -f "$container_name" >/dev/null 2>&1 || true
        remove_container_mapping "$work_dir"
        exit 1
    fi

    # 准备容器环境（非交互式）
    prepare_container_environment "$container_name" "$user_id" "$group_id" "$quiet_mode"
}

# ============================================
# 容器查询与状态
# ============================================

function list_containers() {
    echo -e "${GREEN}运行中的gbox容器:${NC}"
    echo ""

    local containers=$(docker ps --filter "name=${CONTAINER_PREFIX}-" --format "{{.Names}}")

    if [[ -z "$containers" ]]; then
        echo -e "${YELLOW}没有运行中的容器${NC}"
        return
    fi

    printf "%-30s %-35s %-30s %-15s\n" "容器名" "工作目录" "镜像" "端口映射"
    echo "------------------------------------------------------------------------------------------------------------------------"

    while IFS= read -r container; do
        local workdir=$(get_workdir_by_container "$container")
        local port=$(docker port "$container" 8000 2>/dev/null | cut -d: -f2)
        local image=$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null)
        printf "%-30s %-35s %-30s %-15s\n" "$container" "${workdir:-未知}" "${image:-未知}" "$port:8000"
    done <<< "$containers"
}

function show_status() {
    echo -e "${GREEN}所有gbox容器状态:${NC}"
    echo ""

    printf "%-30s %-20s %-15s %-50s %-15s %-15s\n" "容器名" "运行模式" "Agent" "工作目录" "状态" "端口映射"
    echo "-----------------------------------------------------------------------------------------------------------------------------------"

    # 键格式为 "{workDir}:{run_mode}:{agent}"
    jq -r 'to_entries[] | "\(.key)|\(.value)"' "$STATE_FILE" | while IFS='|' read -r state_key container; do
        # 分离 workDir, run_mode, agent
        local workdir="${state_key%%:*}"
        local rest="${state_key#*:}"
        local run_mode="${rest%%:*}"
        local agent="${rest##*:}"

        if is_container_running "$container"; then
            local port=$(docker port "$container" 8000 2>/dev/null | cut -d: -f2)
            printf "%-30s %-20s %-15s %-50s %-15s %-15s\n" "$container" "$run_mode" "$agent" "$workdir" "运行中" "$port:8000"
        else
            printf "%-30s %-20s %-15s %-50s %-15s %-15s\n" "$container" "$run_mode" "$agent" "$workdir" "已停止" "-"
        fi
    done
}

# ============================================
# 容器停止与清理
# ============================================

function stop_container() {
    local container_name="$1"
    if [[ -z "$container_name" ]]; then
        echo -e "${RED}错误: 请指定容器名${NC}"
        echo -e "${YELLOW}提示: 使用 './gbox list' 查看运行中的容器${NC}"
        exit 1
    fi

    # 检查容器是否存在（运行中或已停止）
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${RED}错误: 容器 $container_name 不存在${NC}"
        exit 1
    fi

    # 如果容器正在运行，先停止
    if is_container_running "$container_name"; then
        echo -e "${YELLOW}停止容器: $container_name${NC}"
        docker stop "$container_name" > /dev/null
    else
        echo -e "${YELLOW}删除已停止的容器: $container_name${NC}"
    fi

    # 删除容器
    docker rm "$container_name" > /dev/null

    # 清理映射（使用容器名直接删除）
    remove_container_mapping_by_container "$container_name"

    echo -e "${GREEN}✓ 容器已删除${NC}"
}

function stop_all_containers() {
    echo -e "${YELLOW}停止并删除所有gbox容器...${NC}"
    local containers=$(docker ps --filter "name=${CONTAINER_PREFIX}-" -q)

    if [[ -z "$containers" ]]; then
        echo -e "${YELLOW}没有运行中的容器${NC}"
        return
    fi

    echo "$containers" | xargs docker stop
    echo "$containers" | xargs docker rm

    # 清理所有映射
    echo '{}' > "$STATE_FILE"

    echo -e "${GREEN}完成: 已停止并删除所有容器${NC}"
}

function clean_containers() {
    echo -e "${YELLOW}清理停止的容器和映射...${NC}"

    # 清理Docker容器
    local stopped=$(docker ps -a --filter "name=${CONTAINER_PREFIX}-" --filter "status=exited" -q)
    if [[ -n "$stopped" ]]; then
        echo "$stopped" | xargs docker rm
    fi

    # 清理失效的映射（使用 jq 直接过滤）
    # 注意：键格式为 "{workDir}:{agent}"
    local all_containers=$(docker ps -a --format '{{.Names}}')
    safe_jq_update 'to_entries | map(select($containers | contains(.value))) | from_entries' --arg containers "$all_containers"

    echo -e "${GREEN}完成${NC}"
}

# ============================================
# 日志与命令执行
# ============================================

function show_logs() {
    local container_name="$1"
    if [[ -z "$container_name" ]]; then
        echo -e "${RED}错误: 请指定容器名${NC}"
        exit 1
    fi

    docker logs -f "$container_name"
}

function exec_command() {
    local container_name="$1"
    shift
    local command="$@"

    if [[ -z "$container_name" ]]; then
        echo -e "${RED}错误: 请指定容器名${NC}"
        exit 1
    fi

    docker exec "${DOCKER_EXEC_TTY_ARGS[@]}" "$container_name" bash -c "$command"
}

function shell_command() {
    local container_name="$1"

    if [[ -z "$container_name" ]]; then
        echo -e "${RED}错误: 请指定容器名${NC}"
        echo -e "${YELLOW}用法: gbox shell <容器名>${NC}"
        echo -e "${YELLOW}提示: 使用 'gbox list' 查看运行中的容器${NC}"
        exit 1
    fi

    # 检查容器是否存在
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${RED}错误: 容器 '$container_name' 不存在${NC}"
        echo -e "${YELLOW}提示: 使用 'gbox list' 查看运行中的容器${NC}"
        exit 1
    fi

    # 检查容器是否运行
    local container_state=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
    if [[ "$container_state" != "running" ]]; then
        echo -e "${YELLOW}容器 '$container_name' 未运行，正在启动...${NC}"
        docker start "$container_name" >/dev/null 2>&1
        if ! wait_for_container_ready "$container_name"; then
            echo -e "${RED}错误: 容器启动失败${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ 容器已启动${NC}"
    fi

    echo -e "${GREEN}正在登录到容器 '$container_name'...${NC}"
    echo -e "${BLUE}提示: 使用 'exit' 或 Ctrl+D 退出容器 shell${NC}"
    echo ""

    # 以 guser 身份登录到容器的 bash shell
    docker exec "${DOCKER_EXEC_TTY_ARGS[@]}" --user guser "$container_name" bash
}

