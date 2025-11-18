#!/bin/bash
# lib/docker.sh - Docker 基础操作
# 这个模块负责 Docker 网络管理、容器状态检查和 worktree 目录管理

# ============================================
# Docker Exec 交互标志
# ============================================
# 在非 TTY 环境中使用 -t 会导致 "the input device is not a TTY" 报错。
# 统一在加载脚本时根据当前环境确定 docker exec 应使用的交互参数。
if [[ -t 0 && -t 1 ]]; then
    DOCKER_EXEC_TTY_ARGS=(-it)
else
    DOCKER_EXEC_TTY_ARGS=(-i)
fi

# ============================================
# Docker 网络管理
# ============================================

# 确保 Docker 网络存在
function ensure_network() {
    if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
        echo -e "${YELLOW}创建Docker网络: $NETWORK_NAME${NC}"
        docker network create "$NETWORK_NAME"
    fi
}

# ============================================
# 容器状态检查
# ============================================

# 检查容器是否正在运行
function is_container_running() {
    local container_name="$1"
    docker ps --format '{{.Names}}' | grep -q "^${container_name}$"
}

# 等待容器就绪
function wait_for_container_ready() {
    local container_name="$1"
    local attempts="${2:-${GBOX_READY_ATTEMPTS:-30}}"
    local delay="${3:-${GBOX_READY_DELAY:-0.2}}"

    for ((i = 0; i < attempts; i++)); do
        if docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null | grep -q "true"; then
            if docker exec "$container_name" bash -c "true" >/dev/null 2>&1; then
                return 0
            fi
        fi
        sleep "$delay"
    done

    return 1
}

# ============================================
# Worktree 目录管理
# ============================================

# 检测并获取主仓库目录
# 如果当前目录是 worktree，返回主仓库目录
# 如果当前目录是主仓库或普通目录，返回自身
# 目录规范：主目录 /path/to/project -> worktrees目录 /path/to/project-worktrees
function get_main_repo_dir() {
    local work_dir="$1"

    # 检查是否是 git worktree
    if [[ -f "$work_dir/.git" ]]; then
        # 如果 .git 是文件（而不是目录），可能是 worktree
        local git_content=$(cat "$work_dir/.git" 2>/dev/null)
        if [[ "$git_content" =~ ^gitdir:\ (.+)$ ]]; then
            # 这是一个 worktree，尝试通过 git 获取主仓库路径
            local main_worktree=$(cd "$work_dir" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
            if [[ -n "$main_worktree" ]]; then
                # git-common-dir 返回的是 .git/worktrees/<name> 或 .git
                # 需要提取主仓库根目录
                main_worktree="${main_worktree%/.git*}"
                if [[ -d "$main_worktree" ]]; then
                    echo "$main_worktree"
                    return 0
                fi
            fi
        fi
    fi

    # 如果不是 worktree，或者无法检测主仓库，检查是否在 worktrees 目录下
    # 通过目录命名规范推断：如果当前目录的父目录名以 -worktrees 结尾
    local parent_dir=$(dirname "$work_dir")
    local parent_name=$(basename "$parent_dir")

    if [[ "$parent_name" =~ ^(.+)-worktrees$ ]]; then
        # 父目录是 worktrees 目录，推断主目录
        local main_name="${BASH_REMATCH[1]}"
        local grandparent=$(dirname "$parent_dir")
        local main_dir="$grandparent/$main_name"

        if [[ -d "$main_dir" ]]; then
            echo "$main_dir"
            return 0
        fi
    fi

    # 默认返回工作目录本身（不是 worktree）
    echo "$work_dir"
}

# 根据工作目录生成对应的 worktrees 目录路径
# 自动检测主仓库目录，确保规范：主目录 /path/to/project -> worktrees目录 /path/to/project-worktrees
function get_worktree_dir() {
    local work_dir="$1"

    # 先获取主仓库目录
    local main_dir=$(get_main_repo_dir "$work_dir")

    # 返回主仓库对应的 worktrees 目录
    echo "${main_dir}-worktrees"
}

# 确保 worktrees 目录存在
# 如果目录不存在则创建，如果已存在则跳过
# 返回值：worktrees 目录路径
function ensure_worktree_dir() {
    local work_dir="$1"
    local quiet_mode="${2:-0}"
    local worktree_dir=$(get_worktree_dir "$work_dir")

    if [[ ! -d "$worktree_dir" ]]; then
        mkdir -p "$worktree_dir"
        if (( quiet_mode == 0 )); then
            echo -e "${GREEN}✓ 创建 worktrees 目录: $worktree_dir${NC}" >&2
        fi
    fi

    echo "$worktree_dir"
}
