#!/bin/bash
#
# System-level mv wrapper that enforces .git protection
# This script replaces /bin/mv to prevent bypassing protection
#

# Source the protection functions
source /usr/local/bin/git-protector.sh 2>/dev/null || true

# Call the protected mv function
mv "$@"
