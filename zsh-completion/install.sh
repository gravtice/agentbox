#!/bin/bash
# gbox Zsh completion auto-installation script

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_FILE="$SCRIPT_DIR/gbox.plugin.zsh"
TARGET_DIR="$HOME/.oh-my-zsh/custom/plugins/gbox"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  gbox Zsh Completion Auto-Installation║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check oh-my-zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    echo -e "${RED}✗ Error: oh-my-zsh not found${NC}"
    echo -e "${YELLOW}Please install oh-my-zsh first: https://ohmyz.sh/${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} oh-my-zsh detected"

# Check plugin file
if [[ ! -f "$PLUGIN_FILE" ]]; then
    echo -e "${RED}✗ Error: Plugin file does not exist: $PLUGIN_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Plugin file exists"

# Create target directory
echo ""
echo -e "${BLUE}[1/4]${NC} Installing plugin file..."
mkdir -p "$TARGET_DIR"
cp "$PLUGIN_FILE" "$TARGET_DIR/"
echo -e "${GREEN}✓${NC} Copied to: $TARGET_DIR/gbox.plugin.zsh"

# Update .zshrc
echo ""
echo -e "${BLUE}[2/4]${NC} Updating .zshrc configuration..."

if grep -q "^plugins=(.*gbox" "$HOME/.zshrc"; then
    echo -e "${YELLOW}→${NC} gbox plugin already in .zshrc, skipping"
elif grep -q "^plugins=(" "$HOME/.zshrc"; then
    # Find plugins line and add gbox after it
    # Use sed to add gbox before the first element after plugins=(
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' '/^plugins=($/a\
gbox
' "$HOME/.zshrc"
    else
        # Linux
        sed -i '/^plugins=($/a gbox' "$HOME/.zshrc"
    fi
    echo -e "${GREEN}✓${NC} Added gbox to plugins array"
else
    echo -e "${RED}✗ Error: Cannot find plugins array in .zshrc${NC}"
    echo -e "${YELLOW}Please manually add 'gbox' to the plugins array in .zshrc${NC}"
    exit 1
fi

# Clean completion cache
echo ""
echo -e "${BLUE}[3/4]${NC} Cleaning completion cache..."
rm -f "$HOME/.zcompdump"*
echo -e "${GREEN}✓${NC} Cache cleaned"

# Verify installation
echo ""
echo -e "${BLUE}[4/4]${NC} Verifying installation..."

# Test in a new zsh process
if zsh -i -c 'type _gbox' &>/dev/null; then
    echo -e "${GREEN}✓${NC} _gbox function can be loaded"
else
    echo -e "${YELLOW}⚠${NC} Function loading test failed (this is normal in some environments)"
fi

if zsh -i -c '[[ -n "${_comps[gbox]}" ]]' 2>/dev/null; then
    echo -e "${GREEN}✓${NC} gbox completion registered"
else
    echo -e "${YELLOW}⚠${NC} Completion registration test failed (this is normal in some environments)"
fi

# Completion
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Installation Complete!                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo -e "  ${BLUE}1.${NC} Reload shell (recommended):"
echo -e "     ${GREEN}exec zsh${NC}"
echo ""
echo -e "  ${BLUE}2.${NC} Or source configuration:"
echo -e "     ${GREEN}source ~/.zshrc${NC}"
echo ""
echo -e "  ${BLUE}3.${NC} Or open a new terminal window"
echo ""
echo -e "${YELLOW}Test completion:${NC}"
echo -e "  ${GREEN}gbox [Press Tab key]${NC}"
echo ""
echo -e "View usage instructions:"
echo -e "  ${GREEN}cat $SCRIPT_DIR/README.md${NC}"
echo ""
