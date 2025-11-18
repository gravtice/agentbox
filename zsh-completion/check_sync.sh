#!/bin/bash
# check_sync.sh - 检查 Zsh 补全插件是否与 gbox 同步

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    Zsh 补全插件同步检查工具${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# 检查文件是否存在
if [[ ! -f "$PROJECT_ROOT/gbox" ]]; then
    echo -e "${RED}错误: 找不到 gbox 主脚本${NC}"
    exit 1
fi

if [[ ! -f "$PROJECT_ROOT/lib/common.sh" ]]; then
    echo -e "${RED}错误: 找不到 lib/common.sh${NC}"
    exit 1
fi

if [[ ! -f "$SCRIPT_DIR/gbox.plugin.zsh" ]]; then
    echo -e "${RED}错误: 找不到 gbox.plugin.zsh${NC}"
    exit 1
fi

# ========================================
# 1. 检查 AI Agents
# ========================================
echo -e "${BLUE}[1/4]${NC} 检查 AI Agents 列表..."
echo ""

# 从 lib/common.sh 提取 agents
AGENTS_FROM_COMMON=$(grep "SUPPORTED_AGENTS=" "$PROJECT_ROOT/lib/common.sh" | sed 's/SUPPORTED_AGENTS=(//' | sed 's/)//' | tr -d '"' | tr ' ' '\n' | sort)

# 从补全插件提取 agents
AGENTS_FROM_PLUGIN=$(grep -A 10 "# 定义支持的 AI agents" "$SCRIPT_DIR/gbox.plugin.zsh" | grep "'" | awk -F: '{print $1}' | tr -d "'" | tr -d ' ' | sort)

echo -e "${YELLOW}lib/common.sh 中的 agents:${NC}"
echo "$AGENTS_FROM_COMMON"
echo ""

echo -e "${YELLOW}gbox.plugin.zsh 中的 agents:${NC}"
echo "$AGENTS_FROM_PLUGIN"
echo ""

if [[ "$AGENTS_FROM_COMMON" == "$AGENTS_FROM_PLUGIN" ]]; then
    echo -e "${GREEN}✓ AI Agents 列表同步${NC}"
else
    echo -e "${RED}✗ AI Agents 列表不同步!${NC}"
    echo -e "${YELLOW}请更新 gbox.plugin.zsh 的 agents 数组${NC}"
fi

echo ""

# ========================================
# 2. 检查主命令
# ========================================
echo -e "${BLUE}[2/4]${NC} 检查主命令列表..."
echo ""

# 从 gbox 提取主命令 (case 语句)
COMMANDS_FROM_GBOX=$(grep -E "^\s+(list|status|stop|stop-all|clean|oauth|keepalive|pull|push|logs|exec|shell|build|help)\)" "$PROJECT_ROOT/gbox" | sed 's/)//' | tr -d ' ' | sort)

# 从补全插件提取命令
COMMANDS_FROM_PLUGIN=$(grep -A 20 "# 定义主命令" "$SCRIPT_DIR/gbox.plugin.zsh" | grep "'" | awk -F: '{print $1}' | tr -d "'" | tr -d ' ' | grep -v "^$" | sort)

echo -e "${YELLOW}gbox 中的命令:${NC}"
echo "$COMMANDS_FROM_GBOX"
echo ""

echo -e "${YELLOW}gbox.plugin.zsh 中的命令:${NC}"
echo "$COMMANDS_FROM_PLUGIN"
echo ""

# 简单对比 (注意: happy 是特殊情况,在插件中有但 gbox 中通过 *) 匹配)
echo -e "${GREEN}ℹ 注意: 'happy' 在 gbox 中通过 *) 分支处理,这是正常的${NC}"

echo ""

# ========================================
# 3. 检查参数选项
# ========================================
echo -e "${BLUE}[3/4]${NC} 检查参数选项..."
echo ""

# 从 gbox 提取参数
PARAMS_FROM_GBOX=$(grep -E "\-\-memory|\-\-cpu|\-\-ports|\-\-keep|\-\-name" "$PROJECT_ROOT/gbox" | grep -oE "\-\-[a-z-]+" | sort -u)

# 从补全插件提取参数
PARAMS_FROM_PLUGIN=$(grep -A 10 "gbox_opts=" "$SCRIPT_DIR/gbox.plugin.zsh" | grep "'" | awk -F: '{print $1}' | tr -d "'" | tr -d ' ' | grep "^--" | sort -u)

echo -e "${YELLOW}gbox 中的参数:${NC}"
echo "$PARAMS_FROM_GBOX"
echo ""

echo -e "${YELLOW}gbox.plugin.zsh 中的参数:${NC}"
echo "$PARAMS_FROM_PLUGIN"
echo ""

if [[ "$PARAMS_FROM_GBOX" == "$PARAMS_FROM_PLUGIN" ]]; then
    echo -e "${GREEN}✓ 参数选项同步${NC}"
else
    echo -e "${RED}✗ 参数选项可能不同步,请手动检查${NC}"
fi

echo ""

# ========================================
# 4. 检查子命令
# ========================================
echo -e "${BLUE}[4/4]${NC} 检查子命令..."
echo ""

echo -e "${YELLOW}keepalive 子命令:${NC}"
echo "gbox 中定义:"
grep "handle_keepalive_command" -A 30 "$PROJECT_ROOT/lib/keepalive.sh" | grep -E "^\s+(list|stop|stop-all|restart|logs|auto|help)\)" | sed 's/)//' | tr -d ' '

echo ""
echo "插件中定义:"
grep -A 10 "keepalive_cmds=" "$SCRIPT_DIR/gbox.plugin.zsh" | grep "'" | awk -F: '{print $1}' | tr -d "'" | tr -d ' '

echo ""

# ========================================
# 总结
# ========================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    检查完成${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}建议:${NC}"
echo "1. 如有不同步,请更新 zsh-completion/gbox.plugin.zsh"
echo "2. 更新后运行: ./zsh-completion/install.sh"
echo "3. 更新 CHANGELOG.md 记录变更"
echo ""
echo -e "${YELLOW}参考文档:${NC}"
echo "  zsh-completion/MAINTENANCE.md"
echo ""
