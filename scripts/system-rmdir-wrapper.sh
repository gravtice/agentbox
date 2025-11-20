#!/bin/bash
#
# System-level rmdir wrapper that enforces .git protection
# This script replaces /bin/rmdir to prevent bypassing protection
#

# Source the protection functions
source /usr/local/bin/git-protector.sh 2>/dev/null || true

# Call the protected rmdir function
rmdir "$@"
