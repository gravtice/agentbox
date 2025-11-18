#!/bin/bash
# lib/oauth.sh - OAuth 账号管理模块
# 负责邮箱解析、账号查找、限制解析、账号切换与命令路由（依赖 lib/common.sh 提供的目录与配色常量）

# ============================================
# 邮箱解析
# ============================================
# 从 .claude.json 提取邮件地址并转换为文件名安全格式
function extract_email_safe() {
    local claude_json="$GBOX_CLAUDE_DIR/.claude.json"

    if [[ ! -f "$claude_json" ]]; then
        echo ""
        return 1
    fi

    # 尝试从 emailAddress 字段提取
    local email=$(jq -r '.oauthAccount.emailAddress // empty' "$claude_json" 2>/dev/null)

    if [[ -z "$email" ]]; then
        # 尝试其他可能的字段
        email=$(jq -r '.oauthAccount.Email // .Email // .email // .emailAddress // empty' "$claude_json" 2>/dev/null)
    fi

    if [[ -n "$email" ]]; then
        # 将邮件地址转换为文件名安全格式
        # 1. 转换为小写
        # 2. 将 @ 替换为 -at-
        # 3. 将 . 替换为 -
        # 4. 其他特殊字符也替换为 -
        local safe_email=$(echo "$email" | tr '[:upper:]' '[:lower:]' | sed 's/@/-at-/g' | sed 's/\./-/g' | sed 's/[^a-z0-9-]/-/g')
        echo "$safe_email"
        return 0
    fi

    echo ""
    return 1
}

# ============================================
# 账号查找与 Token 状态
# ============================================
# 查找可用的账号配置文件（V5 版本 - 使用 .claude-*.json）
# 参数: current_account (可选,当前账号,用于排除)
# 返回格式: 账号后缀 (如: user-at-example-com 或 user-at-example-com-2025110611)
# 优先级:
#   1. 无限制 + token 未过期 (最佳: 无限制且立即可用)
#   2. 限制已解除 + token 未过期 (次佳: 立即可用)
#   3. 无限制 + token 已过期 (需重新认证但无限制)
#   4. 限制已解除 + token 已过期 (需重新认证)
function find_available_account() {
    local current_account="${1:-}"
    local current_datetime=$(date +%Y%m%d%H)

    # 候选账号数组
    # 格式: "优先级:后缀:token状态"
    local candidates=()

    # 第一步: 收集无限制账号 (不带日期后缀)
    for file in "$GBOX_CLAUDE_DIR"/.claude-*.json; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file")
            # 检查是否不包含日期后缀 (格式: .claude-prefix.json)
            # 排除以10位数字结尾的文件名 (日期格式: YYYYMMDDHH)
            if [[ "$basename" =~ ^\.claude-[a-z0-9_-]+\.json$ ]] && [[ ! "$basename" =~ -[0-9]{10}\.json$ ]]; then
                # 提取 prefix: .claude-{prefix}.json -> {prefix}
                local prefix="${basename#.claude-}"
                prefix="${prefix%.json}"

                # 排除当前账号
                if [[ -n "$current_account" && "$prefix" == "$current_account" ]]; then
                    continue
                fi

                # 验证对应的 credentials 文件是否存在
                if [[ -f "$GBOX_CLAUDE_DIR/.credentials-$prefix.json" ]]; then
                    # 检查 token 是否过期
                    local token_status=$(check_token_expiry "$GBOX_CLAUDE_DIR/.credentials-$prefix.json")

                    if [[ "$token_status" =~ ^valid: ]]; then
                        # 优先级 1: 无限制 + token 未过期
                        candidates+=("1:$prefix:valid")
                    else
                        # 优先级 3: 无限制 + token 已过期
                        candidates+=("3:$prefix:expired")
                    fi
                fi
            fi
        fi
    done

    # 第二步: 收集限制已解除的账号 (日期后缀已过期)
    for file in "$GBOX_CLAUDE_DIR"/.claude-*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].json; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file")
            # 提取日期部分: .claude-prefix-2025110611.json -> 2025110611
            local date_part="${basename##*-}"
            date_part="${date_part%.json}"

            # 检查日期时间是否已过期或已到达
            # 使用 <= 而不是 <，因为到达限制时间点就可以使用了
            # 例如: 限制到2025110511(11点)，那么11点整就可以使用
            if [[ "$date_part" -le "$current_datetime" ]]; then
                # 提取完整的后缀: .claude-{prefix-YYYYMMDDHH}.json -> prefix-YYYYMMDDHH
                local suffix="${basename#.claude-}"
                suffix="${suffix%.json}"

                # 排除当前账号
                if [[ -n "$current_account" && "$suffix" == "$current_account" ]]; then
                    continue
                fi

                # 验证对应的 credentials 文件是否存在
                if [[ -f "$GBOX_CLAUDE_DIR/.credentials-$suffix.json" ]]; then
                    # 检查 token 是否过期
                    local token_status=$(check_token_expiry "$GBOX_CLAUDE_DIR/.credentials-$suffix.json")

                    if [[ "$token_status" =~ ^valid: ]]; then
                        # 优先级 2: 限制已解除 + token 未过期
                        candidates+=("2:$suffix:valid")
                    else
                        # 优先级 4: 限制已解除 + token 已过期
                        candidates+=("4:$suffix:expired")
                    fi
                fi
            fi
        fi
    done

    # 第三步: 如果有候选账号，按优先级排序并返回第一个
    if [[ ${#candidates[@]} -gt 0 ]]; then
        # 按优先级数字排序 (1 < 2 < 3 < 4)
        local sorted=($(printf '%s\n' "${candidates[@]}" | sort -t: -k1,1n))
        local best="${sorted[0]}"

        # 提取后缀部分
        local suffix=$(echo "$best" | cut -d: -f2)
        local token_state=$(echo "$best" | cut -d: -f3)

        # 输出诊断信息到 stderr (不影响函数返回值)
        local priority=$(echo "$best" | cut -d: -f1)
        case "$priority" in
            1) echo "  (优先级 1/4: 无限制账号, Token 有效)" >&2 ;;
            2) echo "  (优先级 2/4: 限制已解除, Token 有效)" >&2 ;;
            3) echo "  (优先级 3/4: 无限制账号, Token 已过期)" >&2 ;;
            4) echo "  (优先级 4/4: 限制已解除, Token 已过期)" >&2 ;;
        esac

        echo "$suffix"
        return 0
    fi

    # 没有找到可用账号
    return 1
}

# 检查 token 是否过期
# 参数: credentials.json 文件路径
# 返回: "valid:剩余小时" | "expired:过期小时" | "unknown" | "missing"
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
# 限制解析
# ============================================
# OAuth switch 子命令（新版 - 只切换 OAuth 字段）
# 解析限制字符串，提取时间并转换为 YYYYMMDDHH 格式
# 参数: limit_str - 限制字符串，例如 "Weekly limit reached ∙ resets Nov 9, 5pm"
# 返回: YYYYMMDDHH 格式的时间字符串，失败返回空
function parse_limit_str() {
    local limit_str="$1"

    # 提取月份、日期和时间
    # 支持格式: "resets Nov 9, 5pm" 或 "resets Nov 9, 5:00pm"
    if [[ "$limit_str" =~ resets[[:space:]]+([A-Za-z]+)[[:space:]]+([0-9]+),[[:space:]]+([0-9]+):?([0-9]+)?(am|pm) ]]; then
        local month_str="${BASH_REMATCH[1]}"
        local day="${BASH_REMATCH[2]}"
        local hour="${BASH_REMATCH[3]}"
        local minute="${BASH_REMATCH[4]}"
        local ampm="${BASH_REMATCH[5]}"

        # 转换月份名称为数字
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

        # 转换 12 小时制为 24 小时制
        if [[ "$ampm" == "pm" ]] && [[ "$hour" != "12" ]]; then
            hour=$((hour + 12))
        elif [[ "$ampm" == "am" ]] && [[ "$hour" == "12" ]]; then
            hour="00"
        fi

        # 补齐两位数
        day=$(printf "%02d" "$day")
        hour=$(printf "%02d" "$hour")

        # 确定年份（如果月份小于当前月份，则为下一年）
        local current_year=$(date +%Y)
        local current_month=$(date +%m)
        local year="$current_year"

        if [[ "$month" -lt "$current_month" ]]; then
            year=$((current_year + 1))
        fi

        # 返回 YYYYMMDDHH 格式
        echo "${year}${month}${day}${hour}"
        return 0
    fi

    return 1
}

# ============================================
# 账号切换
# ============================================
function oauth_switch() {
    local limit_param=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit)
                shift
                if [[ $# -eq 0 ]]; then
                    echo -e "${RED}错误: --limit 需要参数${NC}"
                    exit 1
                fi
                limit_param="$1"

                # 验证格式: 必须是10位数字 (YYYYMMDDHH)
                if [[ ! "$limit_param" =~ ^[0-9]{10}$ ]]; then
                    echo -e "${RED}错误: --limit 参数格式不正确${NC}"
                    echo -e "${YELLOW}期望格式: YYYYMMDDHH (10位数字)${NC}"
                    echo -e "${YELLOW}示例: 2025120111 (表示2025年12月01日11点)${NC}"
                    echo -e "${YELLOW}您输入的: $limit_param${NC}"
                    exit 1
                fi

                shift
                ;;
            --limit-str)
                shift
                if [[ $# -eq 0 ]]; then
                    echo -e "${RED}错误: --limit-str 需要参数${NC}"
                    exit 1
                fi
                local limit_str="$1"
                echo -e "${BLUE}解析限制字符串: $limit_str${NC}"

                limit_param=$(parse_limit_str "$limit_str")
                if [[ -z "$limit_param" ]]; then
                    echo -e "${RED}错误: 无法解析限制字符串${NC}"
                    echo -e "${YELLOW}期望格式: 'Weekly limit reached ∙ resets Nov 9, 5pm'${NC}"
                    echo -e "${YELLOW}您输入的: $limit_str${NC}"
                    exit 1
                fi

                echo -e "${GREEN}✓ 解析成功: $limit_param${NC}"
                shift
                ;;
            *)
                echo -e "${RED}错误: 未知参数 '$1'${NC}"
                echo -e "${YELLOW}用法: gbox oauth claude switch [--limit YYYYMMDDHH] [--limit-str STRING]${NC}"
                exit 1
                ;;
        esac
    done

    echo -e "${GREEN}OAuth 账号切换（智能保留配置）${NC}"
    echo ""

    # 检查当前配置文件是否存在
    local claude_json="$GBOX_CLAUDE_DIR/.claude.json"
    local credentials_json="$GBOX_CLAUDE_DIR/.credentials.json"

    if [[ ! -f "$claude_json" ]]; then
        echo -e "${YELLOW}警告: 当前没有 Claude 配置文件${NC}"
        echo -e "${YELLOW}将直接查找可用账号...${NC}"
        echo ""
        local backup_suffix=""
        local email_safe=""
    else
        # 提取当前账号的邮件地址(文件名安全格式)
        local email_safe=$(extract_email_safe)

        if [[ -z "$email_safe" ]]; then
            echo -e "${YELLOW}警告: 无法从配置文件提取 email${NC}"
            # 使用时间戳作为备份后缀
            email_safe="backup-$(date +%Y%m%d%H%M%S)"
        fi

        echo -e "${BLUE}当前账号: ${email_safe}${NC}"

        # 确定备份文件名
        local backup_suffix="$email_safe"
        if [[ -n "$limit_param" ]]; then
            # 提取日期部分 (YYYYMMDDHH)
            local date_part="${limit_param:0:10}"
            backup_suffix="${email_safe}-${date_part}"
            echo -e "${YELLOW}限制日期: ${date_part} (${limit_param})${NC}"
        fi

        echo -e "${BLUE}备份后缀: ${backup_suffix}${NC}"
        echo ""

        # V5: 备份完整配置（包含 oauthAccount）
        echo -e "${YELLOW}备份当前账号配置...${NC}"

        # 备份完整 .claude.json（包含 oauthAccount）
        local claude_backup="$GBOX_CLAUDE_DIR/.claude-${backup_suffix}.json"
        cp "$claude_json" "$claude_backup"
        echo -e "${GREEN}✓ 已备份配置: .claude-${backup_suffix}.json${NC}"

        # 备份 credentials.json（完整文件）
        if [[ -f "$credentials_json" ]]; then
            cp "$credentials_json" "$GBOX_CLAUDE_DIR/.credentials-${backup_suffix}.json"
            echo -e "${GREEN}✓ 已备份 Token: .credentials-${backup_suffix}.json${NC}"
        fi

        echo ""
    fi

    # 查找可用账号(排除当前账号)
    echo -e "${YELLOW}查找可用账号...${NC}"
    local available_account=$(find_available_account "$backup_suffix")

    if [[ -z "$available_account" ]]; then
        echo -e "${RED}错误: 没有找到可用的账号${NC}"
        echo ""
        echo -e "${YELLOW}可用账号规则:${NC}"
        echo -e "  1. 无限制账号: .claude-{email-safe}.json"
        echo -e "  2. 已过期限制: .claude-{email-safe}-{YYYYMMDDHH}.json (日期时间已过)"
        echo -e "  email-safe 示例: team-at-gravtice-com"
        echo ""
        echo -e "${BLUE}提示: 请检查 ${GBOX_CLAUDE_DIR} 目录${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ 找到可用账号: ${available_account}${NC}"
    echo ""

    # V5: 切换账号（只替换 oauthAccount 字段，保留其他配置）
    echo -e "${YELLOW}切换 OAuth 账号（保留其他配置）...${NC}"

    local claude_source="$GBOX_CLAUDE_DIR/.claude-${available_account}.json"
    local credentials_source="$GBOX_CLAUDE_DIR/.credentials-${available_account}.json"

    if [[ ! -f "$claude_source" ]]; then
        echo -e "${RED}错误: 配置备份文件不存在: $claude_source${NC}"
        exit 1
    fi

    # 恢复 credentials.json
    if [[ -f "$credentials_source" ]]; then
        cp "$credentials_source" "$credentials_json"
        echo -e "${GREEN}✓ 已更新 .credentials.json${NC}"
    else
        echo -e "${YELLOW}⚠ 警告: credentials 备份文件不存在，跳过${NC}"
    fi

    # 提取 .claude-{suffix}.json 中的 oauthAccount，替换 .claude.json 中的 oauthAccount
    jq --argfile oauth_data "$claude_source" \
       '.oauthAccount = $oauth_data.oauthAccount' \
       "$claude_json" > "$claude_json.tmp"
    mv "$claude_json.tmp" "$claude_json"
    echo -e "${GREEN}✓ 已更新 .claude.json 的 OAuth 字段（其他配置保留）${NC}"

    echo ""

    # 显示恢复后的 token 状态
    echo -e "${YELLOW}Token 状态:${NC}"
    local token_status=$(check_token_expiry "$credentials_json")

    case "$token_status" in
        valid:*)
            local hours="${token_status#valid:}"
            echo -e "${GREEN}✓ Token 有效 (剩余约 $hours 小时)${NC}"
            ;;
        expired:*)
            local hours="${token_status#expired:}"
            echo -e "${YELLOW}⚠ Token 已过期 (过期约 $hours 小时)${NC}"
            echo -e "${YELLOW}  下次使用时需要重新认证 Claude Code${NC}"
            ;;
        *)
            echo -e "${YELLOW}⚠ 无法确定 token 状态${NC}"
            ;;
    esac
    echo ""

    # 删除已使用的备份文件
    echo -e "${YELLOW}清理已使用的账号备份...${NC}"
    rm -f "$claude_source"
    echo -e "${GREEN}✓ 已删除: .claude-${available_account}.json${NC}"

    if [[ -f "$credentials_source" ]]; then
        rm -f "$credentials_source"
        echo -e "${GREEN}✓ 已删除: .credentials-${available_account}.json${NC}"
    fi
    echo ""

    echo -e "${GREEN}✓ OAuth 账号切换完成${NC}"
    echo ""
    echo -e "${BLUE}切换到账号: ${available_account}${NC}"
    echo -e "${GREEN}✓ 已保留: MCP 配置、UI 设置、历史记录等${NC}"
    echo -e "${YELLOW}提示: 新的 Claude Code 会话将使用此账号${NC}"
}

# ============================================
# 命令处理
# ============================================
# OAuth 命令处理（入口）
function handle_oauth_command() {
    local agent="${1:-help}"
    shift || true

    case "$agent" in
        claude)
            handle_oauth_claude_command "$@"
            ;;
        help|--help|-h)
            cat <<EOF
${GREEN}gbox oauth - OAuth 账号管理${NC}

${YELLOW}用法:${NC}
    gbox oauth <agent> <subcommand>    管理指定 agent 的 OAuth 账号
    gbox oauth help                     显示此帮助信息

${YELLOW}支持的 Agent:${NC}
    claude    Claude Code OAuth 管理

${YELLOW}示例:${NC}
    gbox oauth claude switch [--limit YYYYMMDDHH | --limit-str STRING]
                                                       切换 Claude 账号
    gbox oauth claude status                          查看 Claude 账号状态
    gbox oauth claude help                            显示 Claude OAuth 帮助

${YELLOW}详细说明:${NC}
    使用 ${GREEN}gbox oauth claude help${NC} 查看 Claude OAuth 管理的详细说明
EOF
            ;;
        *)
            echo -e "${RED}错误: 未知的 agent '$agent'${NC}"
            echo ""
            echo -e "${YELLOW}支持的 agent:${NC}"
            echo -e "  claude    Claude Code OAuth 管理"
            echo ""
            echo -e "${YELLOW}示例:${NC}"
            echo -e "  gbox oauth claude switch"
            echo -e "  gbox oauth claude status"
            exit 1
            ;;
    esac
}

# OAuth Claude 命令处理
function handle_oauth_claude_command() {
    local subcommand="${1:-help}"
    shift || true

    case "$subcommand" in
        switch)
            oauth_switch "$@"
            ;;
        status)
            # 检查当前账号的 token 状态
            local credentials_json="$GBOX_CLAUDE_DIR/.credentials.json"
            local claude_json="$GBOX_CLAUDE_DIR/.claude.json"

            echo -e "${GREEN}OAuth Token 状态检查${NC}"
            echo ""

            # 获取当前账号邮箱
            local email=$(jq -r '.oauthAccount.emailAddress // .oauthAccount.Email // .Email // .email // .emailAddress // empty' "$claude_json" 2>/dev/null)
            if [[ -n "$email" ]]; then
                echo -e "${BLUE}当前账号: ${email}${NC}"
            else
                echo -e "${YELLOW}⚠ 无法获取账号邮箱${NC}"
            fi

            # 检查 token 状态
            local token_status=$(check_token_expiry "$credentials_json")

            case "$token_status" in
                valid:*)
                    local hours="${token_status#valid:}"
                    local expires_at=$(jq -r '.claudeAiOauth.expiresAt' "$credentials_json" 2>/dev/null)
                    local expire_date=$(date -r $((expires_at / 1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "未知")
                    echo -e "${GREEN}✓ Token 有效${NC}"
                    echo -e "${BLUE}剩余时间: 约 $hours 小时${NC}"
                    echo -e "${BLUE}过期时间: $expire_date${NC}"
                    ;;
                expired:*)
                    local hours="${token_status#expired:}"
                    echo -e "${RED}✗ Token 已过期${NC}"
                    echo -e "${YELLOW}过期时间: 约 $hours 小时前${NC}"
                    echo -e "${YELLOW}建议: 运行 'claude' 命令重新认证${NC}"
                    ;;
                unknown)
                    echo -e "${YELLOW}⚠ 无法确定 token 状态${NC}"
                    echo -e "${YELLOW}可能原因: credentials.json 格式异常${NC}"
                    ;;
                missing)
                    echo -e "${RED}✗ credentials.json 文件不存在${NC}"
                    echo -e "${YELLOW}建议: 运行 'claude' 命令进行首次认证${NC}"
                    ;;
            esac
            echo ""

            # 显示备份账号信息
            local backup_count=$(ls -1 "$GBOX_CLAUDE_DIR"/.oauth-account-*.json 2>/dev/null | wc -l | tr -d ' ')
            if [[ $backup_count -gt 0 ]]; then
                echo -e "${BLUE}备份账号数量: $backup_count${NC}"
                echo -e "${YELLOW}使用 'ls -la ~/.gbox/claude/.oauth-account-*.json' 查看详情${NC}"
            else
                echo -e "${YELLOW}暂无备份账号${NC}"
            fi
            ;;
        help|--help|-h)
            cat <<EOF
${GREEN}gbox oauth claude - Claude OAuth 账号管理${NC}

${YELLOW}用法:${NC}
    gbox oauth claude switch [--limit YYYYMMDDHH | --limit-str STRING]
    gbox oauth claude status
    gbox oauth claude help

${YELLOW}说明:${NC}

    ${BLUE}账号切换 (switch) - 智能保留配置${NC}
    支持 Claude Code 的多账号管理，在账号达到使用限制时切换到其他可用账号。

    ${GREEN}✨ 新特性：只切换 OAuth 信息，保留其他配置${NC}
    - ✅ 保留 MCP 配置（所有容器共享）
    - ✅ 保留 UI 设置（主题、快捷键等）
    - ✅ 保留使用历史和统计
    - ✅ 只替换 OAuth 认证信息

    ${YELLOW}使用场景:${NC}
    1. 账号达到限制(指定时间): gbox oauth claude switch --limit 2025120111
       - 备份当前 OAuth 为 .oauth-account-{email-safe}-2025120111.json
       - 切换到无限制或限制已解除的账号
       - 保留所有其他配置（MCP、UI 等）
       - email-safe: 邮件地址的文件名安全格式(如 team-at-gravtice-com)

    2. 账号达到限制(自动解析): gbox oauth claude switch --limit-str "Weekly limit reached ∙ resets Nov 9, 5pm"
       - 自动从限制提示中提取时间并转换为 YYYYMMDDHH 格式
       - 其他行为同方式 1

    3. 主动切换账号: gbox oauth claude switch
       - 备份当前 OAuth 为 .oauth-account-{email-safe}.json
       - 切换到无限制或限制已解除的账号
       - 保留所有其他配置

    ${YELLOW}账号选择优先级:${NC}
    1. 优先使用无限制账号 (.oauth-account-{email-safe}.json)
    2. 其次使用限制已解除的账号 (.oauth-account-{email-safe}-YYYYMMDDHH.json)
    3. 同时优先选择 token 未过期的账号

    ${YELLOW}Token 管理:${NC}
    - 切换账号时会自动检查 token 是否过期
    - 如果 token 已过期，会提示重新认证
    - Token 过期是正常现象，OAuth token 需要定期刷新

    ${YELLOW}文件说明:${NC}
    - .oauth-account-*.json        OAuth 账号信息（仅 oauthAccount 字段）
    - .credentials-*.json          OAuth token（accessToken, refreshToken）
    - .claude.json.backup-*        完整配置备份（灾难恢复用）
    - .claude.json                 当前配置（包含 OAuth + MCP + UI 等）

    ${BLUE}Token 状态检查 (status)${NC}
    查看当前账号的 OAuth token 状态，包括:
    - 当前登录的账号邮箱
    - Token 有效期和剩余时间
    - 备份账号数量

${YELLOW}示例:${NC}

    # 检查当前 token 状态
    gbox oauth claude status

    # 账号达到限制,限制解除时间为 2025年12月01日11点
    gbox oauth claude switch --limit 2025120111
    # 生成备份: .oauth-account-team-at-gravtice-com-2025120111.json

    # 账号达到限制,使用限制字符串自动解析
    gbox oauth claude switch --limit-str "Weekly limit reached ∙ resets Nov 9, 5pm"
    # 自动解析为 2025110917，生成备份: .oauth-account-team-at-gravtice-com-2025110917.json

    # 主动切换账号(无限制)
    gbox oauth claude switch
    # 生成备份: .oauth-account-team-at-gravtice-com.json

    # 查看OAuth备份账号
    ls -la ~/.gbox/claude/.oauth-account-*.json

${YELLOW}配置文件位置:${NC}
    ${BLUE}${GBOX_CLAUDE_DIR}${NC}

    文件格式:
    - .claude.json                          当前使用的配置
    - .credentials.json                     当前使用的凭证
    - .claude.json-{email-safe}             无限制账号备份
    - .credentials.json-{email-safe}
    - .claude.json-{email-safe}-YYYYMMDDHH  有限制账号备份
    - .credentials.json-{email-safe}-YYYYMMDDHH

    {email-safe} 格式说明:
    - 原始: team@gravtice.com
    - 转换: team-at-gravtice-com (小写, @ -> -at-, . -> -, 其他特殊字符 -> -)
EOF
            ;;
        *)
            echo -e "${RED}错误: 未知的 oauth 子命令 '$subcommand'${NC}"
            echo ""
            echo -e "${YELLOW}用法: gbox oauth <subcommand> [options]${NC}"
            echo -e "${YELLOW}可用子命令: switch, help${NC}"
            exit 1
            ;;
    esac
}

