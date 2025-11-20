#!/bin/bash
#
# System-level rm wrapper that enforces .git protection
# This script replaces /bin/rm to prevent bypassing protection
#

# Source the protection functions
source /usr/local/bin/git-protector.sh 2>/dev/null || true

# Call the protected rm function
rm "$@"
