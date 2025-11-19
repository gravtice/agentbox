#!/bin/bash
# Update happy-cli submodule and commit reference changes
# Usage: ./scripts/update-happy-cli.sh [commit_message]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUBMODULE_PATH="vendor/happy-cli"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored messages
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

# Check if in AgentBox root directory
cd "$PROJECT_ROOT"

# Check and initialize submodule
info "Checking submodule status..."
if [ ! -e "$SUBMODULE_PATH/.git" ] && [ ! -f "$SUBMODULE_PATH/.git" ]; then
    warning "Submodule $SUBMODULE_PATH not initialized, initializing..."
    git submodule update --init --recursive
    if [ $? -ne 0 ]; then
        error "Submodule initialization failed"
        exit 1
    fi
    success "Submodule initialized successfully"
fi

# Verify submodule directory exists
if [ ! -d "$SUBMODULE_PATH" ]; then
    error "Submodule directory does not exist: $SUBMODULE_PATH"
    exit 1
fi

info "Checking $SUBMODULE_PATH status..."

# Enter submodule directory
cd "$SUBMODULE_PATH"

# Check if submodule has uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    warning "Detected uncommitted changes in $SUBMODULE_PATH"
    git status --short
    read -p "Continue? These changes will not be included in the update (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "Cancelled"
        exit 1
    fi
fi

# Get current commit
OLD_COMMIT=$(git rev-parse HEAD)
OLD_COMMIT_SHORT=$(git rev-parse --short HEAD)
OLD_COMMIT_MSG=$(git log -1 --pretty=format:"%s")

info "Current version: $OLD_COMMIT_SHORT - $OLD_COMMIT_MSG"

# Update to latest version
info "Pulling latest code..."
git fetch origin
git pull origin "$(git rev-parse --abbrev-ref HEAD)"

# Get new commit
NEW_COMMIT=$(git rev-parse HEAD)
NEW_COMMIT_SHORT=$(git rev-parse --short HEAD)
NEW_COMMIT_MSG=$(git log -1 --pretty=format:"%s")

# Check if there are updates
if [ "$OLD_COMMIT" = "$NEW_COMMIT" ]; then
    success "Already at latest version, no update needed"
    exit 0
fi

success "Update successful: $NEW_COMMIT_SHORT - $NEW_COMMIT_MSG"

# Return to project root directory
cd "$PROJECT_ROOT"

# Check if submodule reference has changed
if git diff --quiet "$SUBMODULE_PATH"; then
    warning "Submodule reference unchanged (possible bug)"
    exit 0
fi

info "Preparing to commit submodule reference update..."

# Display updated commit range
echo ""
info "Update content:"
cd "$SUBMODULE_PATH"
git log --oneline --decorate --graph "$OLD_COMMIT..$NEW_COMMIT"
cd "$PROJECT_ROOT"
echo ""

# Prepare commit message
if [ -n "$1" ]; then
    COMMIT_MSG="$1"
else
    COMMIT_MSG="chore: update happy-cli to $NEW_COMMIT_SHORT

Update from $OLD_COMMIT_SHORT to $NEW_COMMIT_SHORT

Update content:
$(cd "$SUBMODULE_PATH" && git log --pretty=format:"- %s" "$OLD_COMMIT..$NEW_COMMIT")
"
fi

# Commit
git add "$SUBMODULE_PATH"

# Display content to be committed
info "About to commit:"
echo ""
git diff --cached "$SUBMODULE_PATH"
echo ""
echo "Commit message:"
echo "$COMMIT_MSG"
echo ""

read -p "Confirm commit? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    warning "Commit cancelled, but submodule has been updated"
    info "You can manually commit: git add $SUBMODULE_PATH && git commit"
    exit 1
fi

git commit -m "$COMMIT_MSG"

success "Submodule reference update committed"
info "Next step: Push to remote or sync to test environment"
