#!/bin/bash
# lib/state.sh - 状态管理
# 这个模块负责配置目录初始化、状态文件管理、容器映射关系

# ============================================
# Git 配置初始化
# ============================================

# 初始化 Git 配置文件
function init_gitconfig() {
    local gitconfig_file="$GBOX_CONFIG_DIR/.gitconfig"

    # 如果文件已存在，不覆盖
    if [[ -f "$gitconfig_file" ]]; then
        return 0
    fi

    # 尝试从宿主机复制用户信息
    local git_name=""
    local git_email=""

    if [[ -f "$HOME/.gitconfig" ]]; then
        git_name=$(git config --file "$HOME/.gitconfig" --get user.name 2>/dev/null || echo "")
        git_email=$(git config --file "$HOME/.gitconfig" --get user.email 2>/dev/null || echo "")
    fi

    # 创建默认配置文件
    cat > "$gitconfig_file" <<EOF
# gbox 共享 Git 配置
# 此文件会被挂载到所有 gbox 容器中作为全局配置
# 位置: $gitconfig_file

[core]
	autocrlf = input
	eol = lf
	safecrlf = warn

[user]
	# 请根据需要修改以下信息
	name = ${git_name:-Your Name}
	email = ${git_email:-your.email@example.com}

[pull]
	rebase = false

# 可以在此添加更多配置，例如：
# [alias]
#     st = status
#     co = checkout
#     br = branch
#     ci = commit
EOF

    # 如果成功从宿主机复制了信息，提示用户
    if [[ -n "$git_name" && -n "$git_email" ]]; then
        echo -e "${GREEN}✓ 已创建 Git 配置文件并从宿主机复制用户信息${NC}"
        echo -e "${BLUE}  配置文件: $gitconfig_file${NC}"
    else
        echo -e "${YELLOW}⚠ 已创建 Git 配置文件，但未找到宿主机用户信息${NC}"
        echo -e "${YELLOW}  请编辑配置文件: $gitconfig_file${NC}"
    fi
}

# ============================================
# 状态目录初始化
# ============================================

# 初始化状态目录和配置文件
function init_state() {
    mkdir -p "$GBOX_CONFIG_DIR"
    mkdir -p "$GBOX_CLAUDE_DIR"
    mkdir -p "$GBOX_CODEX_DIR"
    mkdir -p "$GBOX_HAPPY_DIR"
    mkdir -p "$LOGS_DIR"
    mkdir -p "$CACHE_DIR/pip"
    mkdir -p "$CACHE_DIR/npm"
    mkdir -p "$CACHE_DIR/uv"

    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{}' > "$STATE_FILE"
    fi

    # 初始化共享的 .gitconfig
    init_gitconfig
}

# ============================================
# 状态文件安全更新
# ============================================

# 安全地更新状态文件（跨平台兼容）
# 参数: jq_filter jq_args...
function safe_jq_update() {
    local jq_expr="$1"
    shift
    local jq_args=("$@")

    if (( HAS_FLOCK == 1 )); then
        # Linux: 使用 flock 保证并发安全
        (
            flock -x 200
            jq "${jq_args[@]}" "$jq_expr" "$STATE_FILE" > "$STATE_FILE.tmp"
            mv "$STATE_FILE.tmp" "$STATE_FILE"
        ) 200>"$STATE_FILE.lock"
    else
        # macOS/其他: 直接执行（mv 操作本身是原子的）
        jq "${jq_args[@]}" "$jq_expr" "$STATE_FILE" > "$STATE_FILE.tmp"
        mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
}

# ============================================
# 状态键生成
# ============================================

# 生成状态文件键：{mainDir}:{run_mode}:{agent}
# 注意：使用主仓库目录而不是工作目录，确保主仓库和 worktree 共享同一个状态键
# 这与容器名生成逻辑保持一致（容器名也是基于主仓库目录）
# 对于 only-local: {mainDir}:only-local:{agent}
# 对于 local-remote: {mainDir}:local-remote:{agent}
function generate_state_key() {
    local work_dir="$1"
    local run_mode="$2"
    local agent="$3"

    # 获取主仓库目录（如果是 worktree，会返回主仓库目录）
    # 确保主仓库和 worktree 共享同一个状态键
    local main_dir=$(get_main_repo_dir "$work_dir")

    echo "${main_dir}:${run_mode}:${agent}"
}

# ============================================
# 容器映射查询
# ============================================

# 根据工作目录、运行模式和 agent 获取容器名
function get_container_by_workdir_mode_agent() {
    local work_dir="$1"
    local run_mode="$2"
    local agent="$3"
    local key=$(generate_state_key "$work_dir" "$run_mode" "$agent")
    jq -r --arg key "$key" '.[$key] // empty' "$STATE_FILE"
}

# 根据容器名获取状态键
function get_state_key_by_container() {
    local container_name="$1"
    jq -r --arg name "$container_name" 'to_entries[] | select(.value == $name) | .key' "$STATE_FILE"
}

# 从容器名获取主仓库目录（提取键中的 mainDir 部分）
# 注意：返回的是主仓库目录，不是实际工作目录（worktree 场景）
function get_workdir_by_container() {
    local container_name="$1"
    local state_key=$(get_state_key_by_container "$container_name")
    if [[ -n "$state_key" ]]; then
        # 从 "{mainDir}:{run_mode}:{agent}" 中提取 mainDir
        echo "${state_key%%:*}"
    fi
}

# ============================================
# 容器映射保存和删除
# ============================================

# 保存容器映射关系
function save_container_mapping() {
    local work_dir="$1"
    local run_mode="$2"
    local agent="$3"
    local container_name="$4"
    local key=$(generate_state_key "$work_dir" "$run_mode" "$agent")

    # 使用安全更新函数（跨平台兼容）
    safe_jq_update '. + {($key): $name}' --arg key "$key" --arg name "$container_name"
}

# 删除容器映射关系（根据键）
function remove_container_mapping() {
    local work_dir="$1"
    local run_mode="$2"
    local agent="$3"
    local key=$(generate_state_key "$work_dir" "$run_mode" "$agent")

    # 使用安全更新函数（跨平台兼容）
    safe_jq_update 'del(.[$key])' --arg key "$key"
}

# 通过容器名删除映射
function remove_container_mapping_by_container() {
    local container_name="$1"

    # 使用安全更新函数（跨平台兼容）
    safe_jq_update 'to_entries | map(select(.value != $name)) | from_entries' --arg name "$container_name"
}
