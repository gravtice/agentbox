# lib/agent.sh
# Agent 会话管理相关函数（从 gbox.backup 提取，禁止修改逻辑）

# ========================
# 端口映射工具函数
# ========================
function parse_port_mappings() {
    local ports_config="$1"
    local run_mode="$2"  # "only-local" 或 "local-remote"
    local result=""

    # 如果为空，不映射任何端口（本地模式和 Happy 远程模式都不需要默认映射）
    if [[ -z "$ports_config" ]]; then
        return 0
    fi

    # 分割端口映射 (分号分隔)
    IFS=';' read -ra port_items <<< "$ports_config"

    for port_item in "${port_items[@]}"; do
        port_item=$(echo "$port_item" | xargs)  # 去除空格
        [[ -z "$port_item" ]] && continue

        # 只支持 host_port:container_port 格式
        if [[ "$port_item" =~ ^([0-9]+):([0-9]+)$ ]]; then
            local host_port="${BASH_REMATCH[1]}"
            local container_port="${BASH_REMATCH[2]}"
            result="$result -p 127.0.0.1:${host_port}:${container_port}"
        else
            echo -e "${YELLOW}警告: 端口配置格式错误 '$port_item'，应为 'host_port:container_port'${NC}" >&2
        fi
    done

    echo "$result"
}

# ========================
# 容器命名工具函数
# ========================
function generate_container_name() {
    local run_mode="$1"
    local agent="$2"
    local work_dir="$3"

    # 获取主仓库目录（如果是 worktree，会返回主仓库目录）
    # 这确保从主目录或 worktrees 子目录启动都使用同一个容器名
    local main_dir=$(get_main_repo_dir "$work_dir")

    # 获取主目录的basename
    local dir_name=$(basename "$main_dir")
    # 转换为小写，替换非法字符为连字符
    local dir_part=$(echo "$dir_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')

    # 根据运行模式生成不同的容器名
    if [[ "$run_mode" == "only-local" ]]; then
        # gbox-{agent}-{dirname}
        echo "${CONTAINER_PREFIX}-${agent}-${dir_part}"
    else
        # gbox-happy-{agent}-{dirname}
        echo "${CONTAINER_PREFIX}-happy-${agent}-${dir_part}"
    fi
}

# ========================
# Agent 参数附加工具函数
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
# Agent 会话管理
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

    # 使用当前目录作为工作目录
    local work_dir=$(pwd)

    # 需要注入的代理配置（若用户通过环境变量或参数提供）
    local agent_proxy_value="${AGENT_PROXY:-}"
    local agent_cmd_prefix="cd '$work_dir' && export PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/playwright"
    if [[ -n "$agent_proxy_value" ]]; then
        local agent_proxy_escaped
        agent_proxy_escaped=$(printf '%q' "$agent_proxy_value")
        agent_cmd_prefix="$agent_cmd_prefix && export GBOX_PROXY=$agent_proxy_escaped && export HTTP_PROXY=$agent_proxy_escaped && export HTTPS_PROXY=$agent_proxy_escaped && export ALL_PROXY=$agent_proxy_escaped && export http_proxy=$agent_proxy_escaped && export https_proxy=$agent_proxy_escaped && export all_proxy=$agent_proxy_escaped"
    fi
    agent_cmd_prefix="$agent_cmd_prefix && exec "

    # 根据运行模式、agent 和工作目录生成容器名
    local container_name=$(generate_container_name "$run_mode" "$agent" "$work_dir")

    # 检查容器是否已存在
    local existing_container=$(get_container_by_workdir_mode_agent "$work_dir" "$run_mode" "$agent")

    local actual_container=""
    local container_created=0
    local container_started=0
    local existed_before=false

    if [[ -n "$existing_container" ]]; then
        # 状态文件中有映射，检查容器是否真实存在
        if ! docker ps -a --format '{{.Names}}' | grep -q "^${existing_container}$"; then
            # 容器映射存在但容器实际不存在（可能被手动删除），清理映射
            echo -e "${YELLOW}容器映射存在但容器已被删除，清理状态...${NC}"
            remove_container_mapping "$work_dir" "$run_mode" "$agent"
            existing_container=""  # 清空，后续会重新创建
        fi
    fi

    if [[ -n "$existing_container" ]]; then
        # 容器存在，检查是否运行中
        if ! is_container_running "$existing_container"; then
            # 容器存在但未运行，启动它
            echo -e "${YELLOW}容器已停止，正在启动...${NC}"
            docker start "$existing_container" >/dev/null 2>&1

            # 等待容器就绪
            if ! wait_for_container_ready "$existing_container"; then
                echo -e "${RED}错误: 容器启动失败${NC}"
                exit 1
            fi

            container_started=1
        fi

        # 容器现在应该在运行中
        actual_container="$existing_container"
        existed_before=true

        # 显示提示并执行
        echo -e "${GREEN}连接到已有容器${NC}"
        echo -e "  运行模式: ${BLUE}$run_mode${NC}"
        echo -e "  Agent: ${BLUE}$agent${NC}"
        echo -e "  容器: ${BLUE}$existing_container${NC}"
        echo -e "  目录: ${BLUE}$work_dir${NC}"
        echo ""

        # 清理 Playwright 锁定目录和进程（每次连接都清理）
        docker exec "$existing_container" bash -c '
            # 停止 Chrome 和 Playwright 进程
            pkill -9 chrome 2>/dev/null || true
            pkill -9 playwright 2>/dev/null || true
            # 清理浏览器数据目录
            find /usr/local/share/playwright -maxdepth 1 -name "mcp-chrome-*" -type d -exec rm -rf {} + 2>/dev/null || true
        ' >/dev/null 2>&1

        # 根据运行模式和 agent 确定执行的命令
        local cmd="$agent_cmd_prefix"
        if [[ "$run_mode" == "local-remote" ]]; then
            # 远程协作模式：使用 happy
            cmd="${cmd}happy $agent"
            # claude 需要 --dangerously-skip-permissions
            if [[ "$agent" == "claude" ]]; then
                cmd="$cmd --dangerously-skip-permissions"
            # gemini 需要 --yolo 自动化模式
            elif [[ "$agent" == "gemini" ]]; then
                cmd="$cmd --yolo"
            fi
        else
            # 本地模式：直接运行 agent
            cmd="${cmd}$agent"
            # claude 需要 --dangerously-skip-permissions
            if [[ "$agent" == "claude" ]]; then
                cmd="$cmd --dangerously-skip-permissions"
            # gemini 需要 --yolo 自动化模式
            elif [[ "$agent" == "gemini" ]]; then
                cmd="$cmd --yolo"
            fi
        fi

        # 添加用户传递的参数
        cmd=$(append_agent_args_to_cmd "$cmd" "$agent_args_skip_delimiter" "${agent_args[@]}")

        echo -e "${YELLOW}提示: 使用 Ctrl+C 可以退出${NC}"
        echo ""

        docker exec "${DOCKER_EXEC_TTY_ARGS[@]}" --user guser "$existing_container" bash -c "$cmd"

    else
        # 容器映射不存在，但检查是否有同名容器（可能是孤儿容器）
        if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
            # 同名容器存在，尝试使用它
            echo -e "${YELLOW}检测到同名容器（可能是孤儿容器），正在恢复...${NC}"

            # 检查容器是否运行中
            if ! is_container_running "$container_name"; then
                # 容器存在但未运行，启动它
                echo -e "${YELLOW}容器已停止，正在启动...${NC}"
                docker start "$container_name" >/dev/null 2>&1

                # 等待容器就绪
                if ! wait_for_container_ready "$container_name"; then
                    echo -e "${RED}错误: 容器启动失败${NC}"
                    exit 1
                fi

                container_started=1
            fi

            # 恢复映射关系
            save_container_mapping "$work_dir" "$run_mode" "$agent" "$container_name"
            actual_container="$container_name"
            existed_before=true

            echo -e "${GREEN}连接到已有容器${NC}"
            echo -e "  运行模式: ${BLUE}$run_mode${NC}"
            echo -e "  Agent: ${BLUE}$agent${NC}"
            echo -e "  容器: ${BLUE}$container_name${NC}"
            echo -e "  目录: ${BLUE}$work_dir${NC}"
            echo ""

            # 清理 Playwright 锁定目录和进程
            docker exec "$container_name" bash -c '
                pkill -9 chrome 2>/dev/null || true
                pkill -9 playwright 2>/dev/null || true
                find /usr/local/share/playwright -maxdepth 1 -name "mcp-chrome-*" -type d -exec rm -rf {} + 2>/dev/null || true
            ' >/dev/null 2>&1

            # 执行 agent 命令
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

            echo -e "${YELLOW}提示: 使用 Ctrl+C 可以退出${NC}"
            echo ""

            docker exec "${DOCKER_EXEC_TTY_ARGS[@]}" --user guser "$container_name" bash -c "$cmd"

        else
            # 容器不存在，自动创建
            actual_container="$container_name"
            container_created=1
            container_started=1

            echo -e "${YELLOW}容器不存在，正在创建...${NC}"
            echo ""

            # 调用 start_container 创建容器
            start_container "$container_name" "$work_dir" "$run_mode" "$agent"

            # 保存映射关系
            save_container_mapping "$work_dir" "$run_mode" "$agent" "$container_name"
        fi

        # 显示提示并执行
        echo ""
        echo -e "${GREEN}容器创建完成，正在启动...${NC}"
        echo -e "  运行模式: ${BLUE}$run_mode${NC}"
        echo -e "  Agent: ${BLUE}$agent${NC}"
        echo -e "  容器: ${BLUE}$container_name${NC}"
        echo -e "  目录: ${BLUE}$work_dir${NC}"
        echo ""

        # 根据运行模式和 agent 确定执行的命令
        local cmd="$agent_cmd_prefix"
        if [[ "$run_mode" == "local-remote" ]]; then
            # 远程协作模式：使用 happy
            cmd="${cmd}happy $agent"
            # claude 需要 --dangerously-skip-permissions
            if [[ "$agent" == "claude" ]]; then
                cmd="$cmd --dangerously-skip-permissions"
            # gemini 需要 --yolo 自动化模式
            elif [[ "$agent" == "gemini" ]]; then
                cmd="$cmd --yolo"
            fi
        else
            # 本地模式：直接运行 agent
            cmd="${cmd}$agent"
            # claude 需要 --dangerously-skip-permissions
            if [[ "$agent" == "claude" ]]; then
                cmd="$cmd --dangerously-skip-permissions"
            # gemini 需要 --yolo 自动化模式
            elif [[ "$agent" == "gemini" ]]; then
                cmd="$cmd --yolo"
            fi
        fi

        # 添加用户传递的参数
        cmd=$(append_agent_args_to_cmd "$cmd" "$agent_args_skip_delimiter" "${agent_args[@]}")

        echo -e "${YELLOW}提示: 使用 Ctrl+C 可以退出${NC}"
        echo ""

        docker exec "${DOCKER_EXEC_TTY_ARGS[@]}" --user guser "$container_name" bash -c "$cmd"
    fi

    # 退出后的提示和清理
    echo ""
    echo -e "${GREEN}已退出${NC}"
    echo ""

    # 检查是否需要自动清理（默认保留容器）
    local auto_cleanup=0
    if [[ "${GBOX_AUTO_CLEANUP:-0}" == "1" ]]; then
        auto_cleanup=1
    fi

    if (( auto_cleanup == 1 )); then
        # 自动删除容器
        echo -e "${YELLOW}正在清理容器...${NC}"

        # 停止并删除容器
        if is_container_running "$actual_container"; then
            docker stop "$actual_container" > /dev/null 2>&1
        fi
        docker rm "$actual_container" > /dev/null 2>&1

        # 清理映射关系
        remove_container_mapping "$work_dir" "$run_mode" "$agent"

        echo -e "${GREEN}✓ 容器已清理${NC}"
    else
        echo -e "${BLUE}容器已保留: $actual_container${NC}"
        echo -e "${YELLOW}提示: 使用 'gbox stop $actual_container' 停止容器${NC}"
        echo -e "${YELLOW}提示: 使用 'gbox $agent' 或 'gbox happy $agent' 继续使用${NC}"
    fi
}
