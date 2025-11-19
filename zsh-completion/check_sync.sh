#!/bin/bash
# check_sync.sh - Check if Zsh completion plugin is synchronized with gbox

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    Zsh Completion Plugin Sync Checker${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Check if files exist
if [[ ! -f "$PROJECT_ROOT/gbox" ]]; then
    echo -e "${RED}Error: Cannot find gbox main script${NC}"
    exit 1
fi

if [[ ! -f "$PROJECT_ROOT/lib/common.sh" ]]; then
    echo -e "${RED}Error: Cannot find lib/common.sh${NC}"
    exit 1
fi

if [[ ! -f "$SCRIPT_DIR/gbox.plugin.zsh" ]]; then
    echo -e "${RED}Error: Cannot find gbox.plugin.zsh${NC}"
    exit 1
fi

# ========================================
# 1. Check AI Agents
# ========================================
echo -e "${BLUE}[1/4]${NC} Checking AI Agents list..."
echo ""

# Extract agents from lib/common.sh
AGENTS_FROM_COMMON=$(grep "SUPPORTED_AGENTS=" "$PROJECT_ROOT/lib/common.sh" | sed 's/SUPPORTED_AGENTS=(//' | sed 's/)//' | tr -d '"' | tr ' ' '\n' | sort)

# Extract agents from completion plugin
AGENTS_FROM_PLUGIN=$(grep -A 10 "# Define supported AI agents" "$SCRIPT_DIR/gbox.plugin.zsh" | grep "'" | awk -F: '{print $1}' | tr -d "'" | tr -d ' ' | sort)

echo -e "${YELLOW}Agents in lib/common.sh:${NC}"
echo "$AGENTS_FROM_COMMON"
echo ""

echo -e "${YELLOW}Agents in gbox.plugin.zsh:${NC}"
echo "$AGENTS_FROM_PLUGIN"
echo ""

if [[ "$AGENTS_FROM_COMMON" == "$AGENTS_FROM_PLUGIN" ]]; then
    echo -e "${GREEN}✓ AI Agents list synchronized${NC}"
else
    echo -e "${RED}✗ AI Agents list not synchronized!${NC}"
    echo -e "${YELLOW}Please update the agents array in gbox.plugin.zsh${NC}"
fi

echo ""

# ========================================
# 2. Check Main Commands
# ========================================
echo -e "${BLUE}[2/4]${NC} Checking main commands list..."
echo ""

# Extract main commands from gbox (case statements)
COMMANDS_FROM_GBOX=$(grep -E "^\s+(list|status|stop|stop-all|clean|oauth|keepalive|pull|push|logs|exec|shell|build|help)\)" "$PROJECT_ROOT/gbox" | sed 's/)//' | tr -d ' ' | sort)

# Extract commands from completion plugin
COMMANDS_FROM_PLUGIN=$(grep -A 20 "# Define main commands" "$SCRIPT_DIR/gbox.plugin.zsh" | grep "'" | awk -F: '{print $1}' | tr -d "'" | tr -d ' ' | grep -v "^$" | sort)

echo -e "${YELLOW}Commands in gbox:${NC}"
echo "$COMMANDS_FROM_GBOX"
echo ""

echo -e "${YELLOW}Commands in gbox.plugin.zsh:${NC}"
echo "$COMMANDS_FROM_PLUGIN"
echo ""

# Simple comparison (note: happy is a special case, present in plugin but matched by *) in gbox)
echo -e "${GREEN}ℹ Note: 'happy' is handled by the *) branch in gbox, this is normal${NC}"

echo ""

# ========================================
# 3. Check Parameter Options
# ========================================
echo -e "${BLUE}[3/4]${NC} Checking parameter options..."
echo ""

# Extract parameters from gbox
PARAMS_FROM_GBOX=$(grep -E "\-\-memory|\-\-cpu|\-\-ports|\-\-keep|\-\-name" "$PROJECT_ROOT/gbox" | grep -oE "\-\-[a-z-]+" | sort -u)

# Extract parameters from completion plugin
PARAMS_FROM_PLUGIN=$(grep -A 10 "gbox_opts=" "$SCRIPT_DIR/gbox.plugin.zsh" | grep "'" | awk -F: '{print $1}' | tr -d "'" | tr -d ' ' | grep "^--" | sort -u)

echo -e "${YELLOW}Parameters in gbox:${NC}"
echo "$PARAMS_FROM_GBOX"
echo ""

echo -e "${YELLOW}Parameters in gbox.plugin.zsh:${NC}"
echo "$PARAMS_FROM_PLUGIN"
echo ""

if [[ "$PARAMS_FROM_GBOX" == "$PARAMS_FROM_PLUGIN" ]]; then
    echo -e "${GREEN}✓ Parameter options synchronized${NC}"
else
    echo -e "${RED}✗ Parameter options may not be synchronized, please check manually${NC}"
fi

echo ""

# ========================================
# 4. Check Subcommands
# ========================================
echo -e "${BLUE}[4/4]${NC} Checking subcommands..."
echo ""

echo -e "${YELLOW}keepalive subcommands:${NC}"
echo "Defined in gbox:"
grep "handle_keepalive_command" -A 30 "$PROJECT_ROOT/lib/keepalive.sh" | grep -E "^\s+(list|stop|stop-all|restart|logs|auto|help)\)" | sed 's/)//' | tr -d ' '

echo ""
echo "Defined in plugin:"
grep -A 10 "keepalive_cmds=" "$SCRIPT_DIR/gbox.plugin.zsh" | grep "'" | awk -F: '{print $1}' | tr -d "'" | tr -d ' '

echo ""

# ========================================
# Summary
# ========================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    Check Complete${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Recommendations:${NC}"
echo "1. If not synchronized, please update zsh-completion/gbox.plugin.zsh"
echo "2. After update, run: ./zsh-completion/install.sh"
echo "3. Update CHANGELOG.md to record changes"
echo ""
echo -e "${YELLOW}Reference documentation:${NC}"
echo "  zsh-completion/MAINTENANCE.md"
echo ""
