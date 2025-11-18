#!/bin/bash
# lib/keepalive.sh - Keepalive 账号登录态维持模块
# 负责账号扫描、状态管理、容器生命周期与命令处理，依赖 common/state/docker/oauth 模块提供的变量与工具

# ============================================
# Keepalive 账号登录态维持
# ============================================

# Keepalive 状态文件
KEEPALIVE_STATE_FILE="$GBOX_CONFIG_DIR/keepalive-state.json"
KEEPALIVE_INTERVAL="${KEEPALIVE_INTERVAL:-3600}"  # 默认 1 小时
DOCKER_IMAGE="${IMAGE_FULL}"

# Email 转 suffix（email-safe 格式）
# 示例: agent@gravtice.com -> agent-at-gravtice-com
email_to_suffix() {
    local email="$1"
    echo "$email" | tr '[:upper:]' '[:lower:]' | sed 's/@/-at-/g' | sed 's/\./-/g'
}

# 获取当前账号的 suffix
get_current_account_suffix() {
    local claude_json="$GBOX_CLAUDE_DIR/.claude.json"
    if [[ ! -f "$claude_json" ]]; then
        echo ""
        return 1
    fi

    # 读取当前账号的 email
    local email=$(jq -r '.oauthAccount.emailAddress // empty' "$claude_json" 2>/dev/null)
    if [[ -z "$email" ]]; then
        echo ""
        return 1
    fi

    # 转换 email 为 suffix
    email_to_suffix "$email"
}

# 扫描所有已登录账号 (V5 版本)
# V5 改动：使用 .claude-{suffix}.json 替代 .oauth-account-{suffix}.json
# 输出格式：每行一个账号信息，格式为 "email-suffix|filepath-suffix"
# 示例输出：
# current|current                                    # 当前账号
# agent-at-gravtice-com|agent-at-gravtice-com-2025120115  # 备份账号（带限制时间）
scan_logged_accounts() {
    local accounts=()

    # 1. 检查当前账号
    if [[ -f "$GBOX_CLAUDE_DIR/.credentials.json" ]]; then
        local email=$(jq -r '.oauthAccount.emailAddress // empty' "$GBOX_CLAUDE_DIR/.claude.json" 2>/dev/null)
        if [[ -n "$email" ]]; then
            # 使用 "current" 作为特殊标识
            accounts+=("current|current")
        fi
    fi

    # 2. 扫描备份账号（基于 .credentials-{suffix}.json）
    for cred_file in "$GBOX_CLAUDE_DIR"/.credentials-*.json; do
        [[ -f "$cred_file" ]] || continue

        local basename=$(basename "$cred_file")
        local suffix="${basename#.credentials-}"
        suffix="${suffix%.json}"

        # 检查对应的 .claude-{suffix}.json 是否存在 (V5 改动)
        if [[ -f "$GBOX_CLAUDE_DIR/.claude-${suffix}.json" ]]; then
            # 提取 email_suffix（去掉 limitTime）
            local email_suffix="$suffix"
            if [[ "$suffix" =~ ^(.+)-([0-9]{10})$ ]]; then
                email_suffix="${BASH_REMATCH[1]}"
            fi

            accounts+=("${email_suffix}|${suffix}")
        fi
    done

    # 输出所有账号（每行一个）
    printf '%s\n' "${accounts[@]}"
}

# 辅助函数：从 scan 结果中提取唯一的 email_suffix 列表
get_unique_email_suffixes() {
    local scan_result="$1"
    echo "$scan_result" | cut -d'|' -f1 | sort -u
}

# 获取账号的 email 和文件 suffix (V5 版本)
# V5 改动：使用 .claude-{suffix}.json 替代 .oauth-account-{suffix}.json
# 参数：email_suffix (不含限制时间) 或 "current"
# 返回：JSON 格式的账号信息
get_account_info() {
    local email_suffix="$1"

    # 如果是当前账号（email_suffix == "current"）
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

    # 从备份文件读取，查找匹配的 .claude-{suffix}.json（可能带限制时间）
    for claude_file in "$GBOX_CLAUDE_DIR"/.claude-${email_suffix}*.json; do
        [[ -f "$claude_file" ]] || continue

        # 提取文件名中的 suffix
        local basename=$(basename "$claude_file")
        local file_suffix="${basename#.claude-}"
        file_suffix="${file_suffix%.json}"

        # 读取账号信息（从 oauthAccount 字段）
        local info=$(jq -r '.oauthAccount | {
            email: .emailAddress,
            accountUuid: .accountUuid
        }' "$claude_file" 2>/dev/null)

        # 添加 fileSuffix 字段
        echo "$info" | jq --arg fs "$file_suffix" '. + {fileSuffix: $fs}' 2>/dev/null
        return 0
    done

    echo "{}"
}

# 获取账号的限制时间（从文件名提取）
# 参数：file_suffix (可能包含限制时间)
# 返回：限制时间字符串或空
get_account_limit_time() {
    local file_suffix="$1"

    # 从 file_suffix 提取限制时间
    if [[ "$file_suffix" =~ -([0-9]{10})$ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# 初始化状态文件
init_keepalive_state() {
    if [[ ! -f "$KEEPALIVE_STATE_FILE" ]]; then
        mkdir -p "$(dirname "$KEEPALIVE_STATE_FILE")"
        echo '{"accounts":{},"currentAccount":"","lastScan":""}' > "$KEEPALIVE_STATE_FILE"
    fi
}

# 读取状态文件
# 输出格式：每行一个 suffix
read_keepalive_state() {
    if [[ ! -f "$KEEPALIVE_STATE_FILE" ]]; then
        # 文件不存在，返回空
        return 0
    fi

    # 提取所有账号的 key
    jq -r '.accounts | keys[]' "$KEEPALIVE_STATE_FILE" 2>/dev/null || true
}

# 更新状态文件 (V5 版本)
# 参数：scan 结果（每行格式：email_suffix|file_suffix）
# V5 改动：正确处理 "current" 账号
update_keepalive_state() {
    local scan_result="$1"

    local accounts_json="{}"

    # 为每个账号构建 JSON 对象
    while IFS='|' read -r email_suffix file_suffix; do
        [[ -z "$email_suffix" ]] && continue

        # 获取账号信息
        local account_info=$(get_account_info "$email_suffix")
        local email=$(echo "$account_info" | jq -r '.email // ""' 2>/dev/null)

        # 构建容器名称（V5：current 账号使用 gbox-keepalive-current）
        local container_name
        if [[ "$file_suffix" == "current" ]]; then
            container_name="gbox-keepalive-current"
        else
            container_name="gbox-keepalive-${file_suffix}"
        fi

        local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # 获取限制时间（从 file_suffix 提取）
        local limit_time=""
        if [[ "$file_suffix" != "current" ]]; then
            limit_time=$(get_account_limit_time "$file_suffix")
        fi

        # 判断是否是当前账号
        local is_current=false
        if [[ "$email_suffix" == "current" ]]; then
            is_current=true
        fi

        # 更新 JSON
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

    # 写入状态文件
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

# 对比账号列表 - 找出新增账号
compare_accounts_added() {
    local current="$1"
    local previous="$2"

    # 使用 comm 命令找出差异
    comm -23 <(echo "$current" | sort) <(echo "$previous" | sort)
}

# 对比账号列表 - 找出登出账号
compare_accounts_removed() {
    local current="$1"
    local previous="$2"

    # comm -13: 只在第二个文件中出现的行（登出账号）
    comm -13 <(echo "$current" | sort) <(echo "$previous" | sort)
}

# 对比账号列表 - 找出不变账号
compare_accounts_unchanged() {
    local current="$1"
    local previous="$2"

    # comm -12: 同时在两个文件中出现的行（不变账号）
    comm -12 <(echo "$current" | sort) <(echo "$previous" | sort)
}

# 为账号启动 keepalive 容器 (V5 版本)
# V5 核心改动：每个容器独立挂载配置文件到固定路径
start_keepalive_for_account() {
    local email_suffix="$1"
    local file_suffix="$2"  # 可能与 email_suffix 相同或带 limitTime
    local quiet_mode="${3:-0}"

    local container_name
    local claude_file
    local cred_file

    # 确定容器名称和文件路径
    if [[ "$file_suffix" == "current" ]]; then
        container_name="gbox-keepalive-current"
        claude_file="$GBOX_CLAUDE_DIR/.claude.json"
        cred_file="$GBOX_CLAUDE_DIR/.credentials.json"
    else
        container_name="gbox-keepalive-${file_suffix}"
        claude_file="$GBOX_CLAUDE_DIR/.claude-${file_suffix}.json"
        cred_file="$GBOX_CLAUDE_DIR/.credentials-${file_suffix}.json"
    fi

    # 检查文件是否存在且有效
    # 注意：Docker bind mount 在源文件不存在时会创建空目录，需要严格检查
    if [[ ! -f "$cred_file" ]] || [[ -d "$cred_file" ]] || [[ ! -s "$cred_file" ]]; then
        if (( quiet_mode == 0 )); then
            echo -e "${RED}错误: credentials 文件不存在或无效: $file_suffix${NC}"
            [[ -d "$cred_file" ]] && echo -e "${YELLOW}  提示: 检测到目录而非文件，可能是之前挂载残留，请手动删除${NC}"
        fi
        return 1
    fi

    if [[ ! -f "$claude_file" ]] || [[ -d "$claude_file" ]] || [[ ! -s "$claude_file" ]]; then
        if (( quiet_mode == 0 )); then
            echo -e "${RED}错误: .claude.json 文件不存在或无效: $file_suffix${NC}"
            [[ -d "$claude_file" ]] && echo -e "${YELLOW}  提示: 检测到目录而非文件，可能是之前挂载残留，请手动删除${NC}"
        fi
        return 1
    fi

    # 检查容器是否已运行
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        if (( quiet_mode == 0 )); then
            echo -e "${GREEN}✓ 容器已在运行中: $container_name${NC}"
        fi
        return 0
    fi

    # 检查容器是否存在但已停止
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        # 删除后重新创建（确保挂载是最新的）
        if (( quiet_mode == 0 )); then
            echo -e "${YELLOW}容器已存在但未运行，删除后重新创建...${NC}"
        fi
        docker rm -f "$container_name" >/dev/null 2>&1
    fi

    # 创建并启动容器
    if (( quiet_mode == 0 )); then
        echo -e "${GREEN}创建 keepalive 容器: $container_name${NC}"
    fi

    # 获取宿主机 HOME 路径（与主容器保持一致）
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

            echo "[$(date "+%Y-%m-%d %H:%M:%S")] Keepalive 容器启动"

            while true; do
                # V5: 检查两个配置文件是否存在
                if [[ ! -f "$HOME/.claude/.credentials.json" ]] || [[ ! -f "$HOME/.claude/.claude.json" ]]; then
                    echo "[$(date "+%Y-%m-%d %H:%M:%S")] 配置文件不存在，退出"
                    if [[ ! -f "$HOME/.claude/.credentials.json" ]]; then
                        echo "  - credentials.json: 缺失"
                    fi
                    if [[ ! -f "$HOME/.claude/.claude.json" ]]; then
                        echo "  - .claude.json: 缺失"
                    fi
                    exit 0
                fi

                echo "[$(date "+%Y-%m-%d %H:%M:%S")] 执行 keepalive..."

                # 执行 claude 命令并捕获输出
                output=$(claude -p "who are you" 2>&1)
                exit_code=$?

                # V5: 基于输出内容的检测模块
                should_exit=0
                exit_reason=""

                if [[ $exit_code -eq 0 ]]; then
                    echo "[$(date "+%Y-%m-%d %H:%M:%S")] Token 有效"
                    echo "[$(date "+%Y-%m-%d %H:%M:%S")] 输出: $output"
                else
                    echo "[$(date "+%Y-%m-%d %H:%M:%S")] 执行失败 (exit code: $exit_code)"
                    echo "[$(date "+%Y-%m-%d %H:%M:%S")] 输出: $output"

                    # 检测模块：分析输出内容判断是否需要退出

                    # 1. HTTP 错误码检测
                    if echo "$output" | grep -qE "(403|401|404)"; then
                        should_exit=1
                        exit_reason="HTTP 错误 - Token 无效或已被吊销"

                    # 2. 认证失败检测
                    elif echo "$output" | grep -qi "Invalid API key"; then
                        should_exit=1
                        exit_reason="API Key 无效 - Token 已过期或损坏"

                    elif echo "$output" | grep -qi "Please run /login"; then
                        should_exit=1
                        exit_reason="需要重新登录 - Token 失效"

                    elif echo "$output" | grep -qi "authentication failed"; then
                        should_exit=1
                        exit_reason="认证失败"

                    # 3. 账号限制检测
                    elif echo "$output" | grep -qi "rate limit"; then
                        should_exit=0  # 速率限制不退出，继续尝试
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] 检测到速率限制，继续等待..."

                    elif echo "$output" | grep -qi "weekly limit"; then
                        should_exit=0  # 周限制不退出，继续尝试
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] 检测到周限制，继续等待..."

                    # 4. 网络错误检测（可重试）
                    elif echo "$output" | grep -qiE "(connection refused|connection timeout|network error|failed to connect)"; then
                        should_exit=0  # 网络问题不退出，继续尝试
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] 检测到网络问题，继续尝试..."

                    # 5. 配置错误检测
                    elif echo "$output" | grep -qi "configuration error"; then
                        should_exit=1
                        exit_reason="配置错误"

                    # 6. 其他未知错误
                    else
                        should_exit=0  # 默认不退出，继续尝试
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] 未知错误，继续尝试..."
                    fi

                    # 根据检测结果决定是否退出
                    if [[ $should_exit -eq 1 ]]; then
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] ❌ 检测到致命错误: $exit_reason"
                        echo "[$(date "+%Y-%m-%d %H:%M:%S")] 容器退出"
                        exit 1
                    fi
                fi

                sleep "$KEEPALIVE_INTERVAL"
            done
        ' >/dev/null 2>&1

    # 验证容器是否成功启动
    sleep 1
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        if (( quiet_mode == 0 )); then
            echo -e "${GREEN}✓ Keepalive 容器已启动${NC}"
        fi
        return 0
    else
        if (( quiet_mode == 0 )); then
            echo -e "${RED}✗ Keepalive 容器启动失败${NC}"
        fi
        return 1
    fi
}

# 为账号停止 keepalive 容器 (V5 版本)
stop_keepalive_for_account() {
    local suffix_input="$1"
    local quiet_mode="${2:-0}"

    # 尝试从状态文件获取容器名称
    local container_name=""
    if [[ -f "$KEEPALIVE_STATE_FILE" ]]; then
        container_name=$(jq -r ".accounts.\"$suffix_input\".containerName // empty" "$KEEPALIVE_STATE_FILE" 2>/dev/null)
    fi

    # 如果状态文件中找不到，尝试根据 suffix_input 构建容器名
    if [[ -z "$container_name" ]]; then
        if [[ "$suffix_input" == "current" ]]; then
            container_name="gbox-keepalive-current"
        else
            container_name="gbox-keepalive-${suffix_input}"
        fi
    fi

    if ! docker ps -q -f name="^${container_name}$" > /dev/null 2>&1; then
        # 容器不在运行，检查是否存在已停止的容器
        if docker ps -a -q -f name="^${container_name}$" > /dev/null 2>&1; then
            docker rm "$container_name" >/dev/null 2>&1
        fi
        return 0
    fi

    docker stop "$container_name" >/dev/null 2>&1
    docker rm "$container_name" >/dev/null 2>&1

    if (( quiet_mode == 0 )); then
        echo -e "${GREEN}✓ Keepalive 已停止: $container_name${NC}"
    fi

    return 0
}

# Keepalive Auto 主流程
keepalive_auto() {
    local quiet_mode="${1:-0}"

    if (( quiet_mode == 0 )); then
        echo -e "${GREEN}=== Keepalive Auto 自动管理 ===${NC}"
    fi

    # 初始化状态文件
    init_keepalive_state

    # 1. 扫描当前所有登录账号（格式：email_suffix|file_suffix）
    local scan_result=$(scan_logged_accounts)

    # 2. 提取 email_suffix 列表用于对比
    local current_accounts=$(get_unique_email_suffixes "$scan_result")

    # 3. 读取上次记录的账号列表
    local previous_accounts=$(read_keepalive_state)

    # 4. 对比差异
    local added_accounts=$(compare_accounts_added "$current_accounts" "$previous_accounts")
    local removed_accounts=$(compare_accounts_removed "$current_accounts" "$previous_accounts")
    local unchanged_accounts=$(compare_accounts_unchanged "$current_accounts" "$previous_accounts")

    if (( quiet_mode == 0 )); then
        local added_count=$(echo "$added_accounts" | grep -c '.' || echo "0")
        local removed_count=$(echo "$removed_accounts" | grep -c '.' || echo "0")
        local unchanged_count=$(echo "$unchanged_accounts" | grep -c '.' || echo "0")
        echo "✓ 新增账号: $added_count"
        echo "✓ 登出账号: $removed_count"
        echo "✓ 不变账号: $unchanged_count"
        echo ""
    fi

    # 5. 处理新增账号 - 启动 keepalive (V5: 需要从 scan_result 获取 file_suffix)
    local started_count=0
    while IFS='|' read -r email_suffix file_suffix; do
        [[ -z "$email_suffix" ]] && continue

        # 检查是否在 added_accounts 中
        if echo "$added_accounts" | grep -q "^${email_suffix}$"; then
            if (( quiet_mode == 0 )); then
                echo "  → 新增账号，启动 keepalive: $file_suffix"
            fi

            if start_keepalive_for_account "$email_suffix" "$file_suffix" "1"; then
                ((started_count++))
            fi
        fi
    done <<< "$scan_result"

    # 6. 处理登出账号 - 停止 keepalive
    local stopped_count=0
    while IFS= read -r suffix; do
        [[ -z "$suffix" ]] && continue
        if (( quiet_mode == 0 )); then
            echo "  → 登出账号，停止 keepalive: $suffix"
        fi

        if stop_keepalive_for_account "$suffix" "1"; then
            ((stopped_count++))
        fi
    done <<< "$removed_accounts"

    # 7. 处理不变账号 - 确保 keepalive 容器运行 (V5: 需要从 scan_result 获取 file_suffix)
    local checked_count=0
    local restarted_count=0
    while IFS='|' read -r email_suffix file_suffix; do
        [[ -z "$email_suffix" ]] && continue

        # 检查是否在 unchanged_accounts 中
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
                    echo "  → 不变账号，容器异常，重新启动: $file_suffix"
                fi

                if start_keepalive_for_account "$email_suffix" "$file_suffix" "1"; then
                    ((restarted_count++))
                fi
            fi
        fi
    done <<< "$scan_result"

    # 8. 更新状态配置文件（传入完整的 scan 结果）
    update_keepalive_state "$scan_result"

    # 9. 输出结果
    if (( quiet_mode == 0 )); then
        echo ""
        echo -e "${GREEN}完成:${NC}"
        echo "  - 新启动: $started_count"
        echo "  - 已停止: $stopped_count"
        echo "  - 保持运行: $checked_count"
        if (( restarted_count > 0 )); then
            echo "  - 重新启动: $restarted_count"
        fi
    fi
}

# Keepalive 状态显示
keepalive_status() {
    echo -e "${GREEN}=== Keepalive 状态 ===${NC}"
    echo ""

    # 读取状态文件
    if [[ ! -f "$KEEPALIVE_STATE_FILE" ]]; then
        echo -e "${YELLOW}状态文件不存在${NC}"
        echo ""
        echo -e "${BLUE}提示: 运行 'gbox keepalive auto' 初始化${NC}"
        return 0
    fi

    # 显示状态文件信息
    local last_scan=$(jq -r '.lastScan // ""' "$KEEPALIVE_STATE_FILE" 2>/dev/null)
    echo -e "最后扫描: ${BLUE}$last_scan${NC}"
    echo ""

    # 显示所有账号
    local accounts=$(jq -r '.accounts | keys[]' "$KEEPALIVE_STATE_FILE" 2>/dev/null)

    if [[ -z "$accounts" ]]; then
        echo -e "${YELLOW}没有已登录账号${NC}"
        return 0
    fi

    echo -e "${GREEN}已登录账号:${NC}"

    while IFS= read -r suffix; do
        [[ -z "$suffix" ]] && continue

        local email=$(jq -r ".accounts.\"$suffix\".email // \"\"" "$KEEPALIVE_STATE_FILE" 2>/dev/null)
        local container_name=$(jq -r ".accounts.\"$suffix\".containerName // \"\"" "$KEEPALIVE_STATE_FILE" 2>/dev/null)
        local limit_time=$(jq -r ".accounts.\"$suffix\".limitTime // \"\"" "$KEEPALIVE_STATE_FILE" 2>/dev/null)
        local is_current=$(jq -r ".accounts.\"$suffix\".isCurrent // false" "$KEEPALIVE_STATE_FILE" 2>/dev/null)

        # 检查容器状态
        local container_id=$(docker ps -q -f name="^${container_name}$" 2>/dev/null)

        if [[ -n "$container_id" ]]; then
            # 容器运行中
            local uptime=$(docker ps --format "{{.Status}}" -f name="^${container_name}$" 2>/dev/null)
            echo -e "  ✓ ${BLUE}$email${NC} (${GREEN}运行中${NC}, $uptime)"
            if [[ "$is_current" == "true" ]]; then
                echo -e "    ${YELLOW}[当前账号]${NC}"
            fi
            if [[ -n "$limit_time" && "$limit_time" != "null" ]]; then
                echo -e "    限制时间: $limit_time"
            fi
        else
            # 容器未运行
            echo -e "  ✗ ${BLUE}$email${NC} (${RED}未运行${NC})"
            if [[ "$is_current" == "true" ]]; then
                echo -e "    ${YELLOW}[当前账号]${NC}"
            fi
            if [[ -n "$limit_time" && "$limit_time" != "null" ]]; then
                echo -e "    限制时间: $limit_time"
            fi
        fi
    done <<< "$accounts"
}

# 停止所有 keepalive 容器
keepalive_stop_all() {
    echo -e "${GREEN}=== 停止所有 Keepalive 容器 ===${NC}"
    echo ""

    # 查找所有 keepalive 容器
    local containers=$(docker ps -a --filter "name=^gbox-keepalive-" --format "{{.Names}}" 2>/dev/null)

    if [[ -z "$containers" ]]; then
        echo -e "${YELLOW}没有找到 keepalive 容器${NC}"
        return 0
    fi

    local count=0
    while IFS= read -r container; do
        [[ -z "$container" ]] && continue
        echo "  → 停止: $container"
        docker stop "$container" >/dev/null 2>&1
        docker rm "$container" >/dev/null 2>&1
        ((count++))
    done <<< "$containers"

    echo ""
    echo -e "${GREEN}完成: 已停止 $count 个容器${NC}"

    # 清空状态文件
    if [[ -f "$KEEPALIVE_STATE_FILE" ]]; then
        echo '{"accounts":{},"currentAccount":"","lastScan":""}' > "$KEEPALIVE_STATE_FILE"
        echo -e "${BLUE}已重置状态文件${NC}"
    fi
}

# 查看 keepalive 容器日志 (V5 版本)
keepalive_logs() {
    local suffix_input="$1"

    if [[ -z "$suffix_input" ]]; then
        echo -e "${RED}错误: 请指定账号 suffix${NC}"
        echo -e "${YELLOW}用法: gbox keepalive logs <suffix>${NC}"
        echo -e "${YELLOW}示例:${NC}"
        echo -e "${YELLOW}  - 当前账号: gbox keepalive logs current${NC}"
        echo -e "${YELLOW}  - 备份账号: gbox keepalive logs agent-at-gravtice-com-2025120115${NC}"
        return 1
    fi

    # 查询状态文件获取容器名称
    if [[ ! -f "$KEEPALIVE_STATE_FILE" ]]; then
        echo -e "${RED}错误: 状态文件不存在${NC}"
        echo -e "${YELLOW}提示: 运行 'gbox keepalive auto' 初始化${NC}"
        return 1
    fi

    # 从状态文件中查找容器名称
    local container_name=$(jq -r ".accounts.\"$suffix_input\".containerName // empty" "$KEEPALIVE_STATE_FILE" 2>/dev/null)

    if [[ -z "$container_name" ]]; then
        echo -e "${RED}错误: 未找到账号: $suffix_input${NC}"
        echo ""
        echo -e "${YELLOW}提示: 使用 'gbox keepalive status' 查看所有账号${NC}"
        return 1
    fi

    # 检查容器是否存在
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo -e "${RED}错误: 容器不存在: $container_name${NC}"
        echo ""
        echo -e "${YELLOW}提示: 使用 'gbox keepalive status' 查看所有账号${NC}"
        return 1
    fi

    echo -e "${GREEN}显示容器日志: ${container_name}${NC}"
    echo -e "${YELLOW}按 Ctrl+C 退出${NC}"
    echo ""

    docker logs -f "$container_name"
}

# Keepalive 容器管理命令处理
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
                echo -e "${RED}错误: 请指定账号 suffix${NC}"
                echo -e "${YELLOW}用法: gbox keepalive stop <suffix>${NC}"
                echo -e "${YELLOW}示例:${NC}"
                echo -e "${YELLOW}  - 当前账号: gbox keepalive stop current${NC}"
                echo -e "${YELLOW}  - 备份账号: gbox keepalive stop agent-at-gravtice-com-2025120115${NC}"
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
${GREEN}gbox keepalive - OAuth 登录态维持管理${NC}

${YELLOW}用法:${NC}
    gbox keepalive auto                      自动管理所有账号的 keepalive
    gbox keepalive status                    查看 keepalive 状态
    gbox keepalive stop <suffix>             停止指定账号的 keepalive
                                             示例: stop current 或 stop agent-at-gravtice-com-2025120115
    gbox keepalive stop-all                  停止所有 keepalive
    gbox keepalive logs <suffix>             查看 keepalive 日志
                                             示例: logs current 或 logs agent-at-gravtice-com-2025120115
    gbox keepalive help                      显示此帮助信息

${YELLOW}什么是 Keepalive?${NC}
    Keepalive 是自动化的 OAuth token 维持系统，通过后台容器定期执行
    'claude -p "who"' 来保持账号登录态不过期。

${YELLOW}核心特性:${NC}
    • 自动检测账号变化（登录/登出/切换）
    • 为每个账号启动独立的 keepalive 容器
    • 状态持久化，支持系统重启
    • 智能处理账号限制时间

${YELLOW}容器命名规则:${NC}
    gbox-keepalive-<email-suffix>

    示例:
    • gbox-keepalive-agent-at-gravtice-com
    • gbox-keepalive-team-at-gravtice-com

${YELLOW}示例:${NC}
    gbox keepalive auto                      # 自动管理（推荐）
    gbox keepalive status                    # 查看状态
    gbox keepalive stop agent-at-gravtice-com  # 停止特定账号
    gbox keepalive stop-all                  # 停止所有
    gbox keepalive logs agent-at-gravtice-com  # 查看日志

${YELLOW}自动触发时机:${NC}
    • gbox claude 执行前后
    • gbox oauth claude switch 执行后
    • 系统重启后首次执行 gbox 命令

${YELLOW}注意事项:${NC}
    • Keepalive 容器资源占用很低
    • Token 失效（403）时容器会自动退出
    • 账号 logout 时容器会自动停止
    • 可以手动停止不需要的 keepalive
EOF
            ;;
        *)
            echo -e "${RED}错误: 未知的子命令 '$subcommand'${NC}"
            echo ""
            echo -e "${YELLOW}可用子命令:${NC}"
            echo -e "  auto        自动管理所有账号"
            echo -e "  status      查看状态"
            echo -e "  stop        停止指定账号"
            echo -e "  stop-all    停止所有"
            echo -e "  logs        查看日志"
            echo -e "  help        显示帮助"
            echo ""
            echo -e "${YELLOW}使用 'gbox keepalive help' 查看详细说明${NC}"
            exit 1
            ;;
    esac
}
