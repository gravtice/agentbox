#!/bin/bash
# 更新 happy-cli submodule 并提交引用变更
# 用法: ./scripts/update-happy-cli.sh [commit_message]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUBMODULE_PATH="vendor/happy-cli"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# 检查是否在 AgentBox 根目录
cd "$PROJECT_ROOT"

# 检查并初始化 submodule
info "检查 submodule 状态..."
if [ ! -e "$SUBMODULE_PATH/.git" ] && [ ! -f "$SUBMODULE_PATH/.git" ]; then
    warning "Submodule $SUBMODULE_PATH 未初始化，正在初始化..."
    git submodule update --init --recursive
    if [ $? -ne 0 ]; then
        error "Submodule 初始化失败"
        exit 1
    fi
    success "Submodule 初始化成功"
fi

# 验证 submodule 目录存在
if [ ! -d "$SUBMODULE_PATH" ]; then
    error "Submodule 目录不存在: $SUBMODULE_PATH"
    exit 1
fi

info "检查 $SUBMODULE_PATH 状态..."

# 进入 submodule 目录
cd "$SUBMODULE_PATH"

# 检查 submodule 是否有未提交的更改
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    warning "检测到 $SUBMODULE_PATH 有未提交的更改"
    git status --short
    read -p "是否继续？这些更改不会被包含在更新中 (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "已取消"
        exit 1
    fi
fi

# 获取当前 commit
OLD_COMMIT=$(git rev-parse HEAD)
OLD_COMMIT_SHORT=$(git rev-parse --short HEAD)
OLD_COMMIT_MSG=$(git log -1 --pretty=format:"%s")

info "当前版本: $OLD_COMMIT_SHORT - $OLD_COMMIT_MSG"

# 更新到最新版本
info "拉取最新代码..."
git fetch origin
git pull origin "$(git rev-parse --abbrev-ref HEAD)"

# 获取新的 commit
NEW_COMMIT=$(git rev-parse HEAD)
NEW_COMMIT_SHORT=$(git rev-parse --short HEAD)
NEW_COMMIT_MSG=$(git log -1 --pretty=format:"%s")

# 检查是否有更新
if [ "$OLD_COMMIT" = "$NEW_COMMIT" ]; then
    success "已经是最新版本，无需更新"
    exit 0
fi

success "更新成功: $NEW_COMMIT_SHORT - $NEW_COMMIT_MSG"

# 回到项目根目录
cd "$PROJECT_ROOT"

# 检查 submodule 引用是否有变化
if git diff --quiet "$SUBMODULE_PATH"; then
    warning "Submodule 引用未变化（可能是 bug）"
    exit 0
fi

info "准备提交 submodule 引用更新..."

# 显示更新的 commit 范围
echo ""
info "更新内容:"
cd "$SUBMODULE_PATH"
git log --oneline --decorate --graph "$OLD_COMMIT..$NEW_COMMIT"
cd "$PROJECT_ROOT"
echo ""

# 准备提交信息
if [ -n "$1" ]; then
    COMMIT_MSG="$1"
else
    COMMIT_MSG="chore: 更新 happy-cli 到 $NEW_COMMIT_SHORT

从 $OLD_COMMIT_SHORT 更新到 $NEW_COMMIT_SHORT

更新内容:
$(cd "$SUBMODULE_PATH" && git log --pretty=format:"- %s" "$OLD_COMMIT..$NEW_COMMIT")
"
fi

# 提交
git add "$SUBMODULE_PATH"

# 显示即将提交的内容
info "即将提交:"
echo ""
git diff --cached "$SUBMODULE_PATH"
echo ""
echo "提交信息:"
echo "$COMMIT_MSG"
echo ""

read -p "确认提交? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    warning "已取消提交，但 submodule 已更新"
    info "你可以手动提交: git add $SUBMODULE_PATH && git commit"
    exit 1
fi

git commit -m "$COMMIT_MSG"

success "已提交 submodule 引用更新"
info "下一步: 推送到远程或同步到测试环境"
