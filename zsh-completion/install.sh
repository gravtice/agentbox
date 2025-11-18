#!/bin/bash
# gbox Zsh 补全自动安装脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_FILE="$SCRIPT_DIR/gbox.plugin.zsh"
TARGET_DIR="$HOME/.oh-my-zsh/custom/plugins/gbox"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  gbox Zsh 补全自动安装                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# 检查 oh-my-zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    echo -e "${RED}✗ 错误: 未找到 oh-my-zsh${NC}"
    echo -e "${YELLOW}请先安装 oh-my-zsh: https://ohmyz.sh/${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} 检测到 oh-my-zsh"

# 检查插件文件
if [[ ! -f "$PLUGIN_FILE" ]]; then
    echo -e "${RED}✗ 错误: 插件文件不存在: $PLUGIN_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} 插件文件存在"

# 创建目标目录
echo ""
echo -e "${BLUE}[1/4]${NC} 安装插件文件..."
mkdir -p "$TARGET_DIR"
cp "$PLUGIN_FILE" "$TARGET_DIR/"
echo -e "${GREEN}✓${NC} 已复制到: $TARGET_DIR/gbox.plugin.zsh"

# 更新 .zshrc
echo ""
echo -e "${BLUE}[2/4]${NC} 更新 .zshrc 配置..."

if grep -q "^plugins=(.*gbox" "$HOME/.zshrc"; then
    echo -e "${YELLOW}→${NC} gbox 插件已在 .zshrc 中,跳过"
elif grep -q "^plugins=(" "$HOME/.zshrc"; then
    # 找到 plugins 行,并在其后添加 gbox
    # 使用 sed 在 plugins=( 后的第一个元素前添加 gbox
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' '/^plugins=($/a\
gbox
' "$HOME/.zshrc"
    else
        # Linux
        sed -i '/^plugins=($/a gbox' "$HOME/.zshrc"
    fi
    echo -e "${GREEN}✓${NC} 已添加 gbox 到 plugins 数组"
else
    echo -e "${RED}✗ 错误: 无法在 .zshrc 中找到 plugins 数组${NC}"
    echo -e "${YELLOW}请手动添加 'gbox' 到 .zshrc 的 plugins 数组${NC}"
    exit 1
fi

# 清理补全缓存
echo ""
echo -e "${BLUE}[3/4]${NC} 清理补全缓存..."
rm -f "$HOME/.zcompdump"*
echo -e "${GREEN}✓${NC} 缓存已清理"

# 验证安装
echo ""
echo -e "${BLUE}[4/4]${NC} 验证安装..."

# 在新的 zsh 进程中测试
if zsh -i -c 'type _gbox' &>/dev/null; then
    echo -e "${GREEN}✓${NC} _gbox 函数可以加载"
else
    echo -e "${YELLOW}⚠${NC} 函数加载测试失败 (这在某些环境下是正常的)"
fi

if zsh -i -c '[[ -n "${_comps[gbox]}" ]]' 2>/dev/null; then
    echo -e "${GREEN}✓${NC} gbox 补全已注册"
else
    echo -e "${YELLOW}⚠${NC} 补全注册测试失败 (这在某些环境下是正常的)"
fi

# 完成
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  安装完成!                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}下一步:${NC}"
echo ""
echo -e "  ${BLUE}1.${NC} 重新加载 shell (推荐):"
echo -e "     ${GREEN}exec zsh${NC}"
echo ""
echo -e "  ${BLUE}2.${NC} 或者 source 配置:"
echo -e "     ${GREEN}source ~/.zshrc${NC}"
echo ""
echo -e "  ${BLUE}3.${NC} 或者打开新的终端窗口"
echo ""
echo -e "${YELLOW}测试补全:${NC}"
echo -e "  ${GREEN}gbox [按 Tab 键]${NC}"
echo ""
echo -e "查看使用说明:"
echo -e "  ${GREEN}cat $SCRIPT_DIR/README.md${NC}"
echo ""
