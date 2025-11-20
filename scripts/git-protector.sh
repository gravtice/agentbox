#!/bin/bash
#
# Git Directory Protector
# Wraps dangerous commands (rm, mv, rmdir) to prevent accidental deletion of .git directories
#
# Usage: Source this file in .bashrc
#   source /usr/local/bin/git-protector.sh
#

# Log file for protection events
PROTECTOR_LOG="/var/log/gbox-git-protector.log"

# Check if a path is or contains a .git directory
is_git_path() {
    local path="$1"

    # Remove trailing slashes
    path="${path%/}"

    # Check if path itself is .git
    if [[ "$(basename "$path")" == ".git" ]]; then
        return 0
    fi

    # Check if path contains .git component
    if [[ "$path" =~ (^|/)\.git(/|$) ]]; then
        return 0
    fi

    # Try to resolve and check real path
    if [[ -e "$path" ]]; then
        local real_path
        real_path=$(realpath "$path" 2>/dev/null)
        if [[ -n "$real_path" ]] && [[ "$real_path" =~ (^|/)\.git(/|$) ]]; then
            return 0
        fi
    fi

    return 1
}

# Log protection event
log_protection() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] BLOCKED: $*" >> "$PROTECTOR_LOG" 2>/dev/null
}

# Wrapper for rm command
rm() {
    local has_force=0
    local protected_paths=()

    # Check all arguments for .git paths
    for arg in "$@"; do
        # Skip flags
        if [[ "$arg" == -* ]]; then
            [[ "$arg" =~ f ]] && has_force=1
            continue
        fi

        # Check if this path should be protected
        if is_git_path "$arg"; then
            protected_paths+=("$arg")
        fi
    done

    # If protected paths found, block the operation
    if [[ ${#protected_paths[@]} -gt 0 ]]; then
        echo "❌ ERROR: Attempting to remove .git directory is BLOCKED" >&2
        echo "" >&2
        echo "Protected paths detected:" >&2
        for path in "${protected_paths[@]}"; do
            echo "  - $path" >&2
        done
        echo "" >&2
        echo "⚠️  This protection prevents accidental deletion of git repositories." >&2
        echo "⚠️  This operation cannot be bypassed for safety reasons." >&2
        echo "" >&2
        echo "If you need to manage .git directories, exit the container and" >&2
        echo "perform the operation on the host system." >&2

        log_protection "rm $*"
        return 1
    fi

    # Safe to execute - use original command
    if [[ -x /usr/local/lib/original/rm ]]; then
        /usr/local/lib/original/rm "$@"
    else
        command rm "$@"
    fi
}

# Wrapper for mv command
mv() {
    local has_force=0
    local protected_paths=()

    # Check all arguments except the last one (destination)
    local args=("$@")
    local num_args=${#args[@]}

    for ((i=0; i<num_args-1; i++)); do
        local arg="${args[$i]}"

        # Skip flags
        if [[ "$arg" == -* ]]; then
            [[ "$arg" =~ f ]] && has_force=1
            continue
        fi

        # Check if this path should be protected
        if is_git_path "$arg"; then
            protected_paths+=("$arg")
        fi
    done

    # If protected paths found, block the operation
    if [[ ${#protected_paths[@]} -gt 0 ]]; then
        echo "❌ ERROR: Attempting to move .git directory is BLOCKED" >&2
        echo "" >&2
        echo "Protected paths detected:" >&2
        for path in "${protected_paths[@]}"; do
            echo "  - $path" >&2
        done
        echo "" >&2
        echo "⚠️  This protection prevents accidental corruption of git repositories." >&2
        echo "⚠️  This operation cannot be bypassed for safety reasons." >&2
        echo "" >&2
        echo "If you need to manage .git directories, exit the container and" >&2
        echo "perform the operation on the host system." >&2

        log_protection "mv $*"
        return 1
    fi

    # Safe to execute - use original command
    if [[ -x /usr/local/lib/original/mv ]]; then
        /usr/local/lib/original/mv "$@"
    else
        command mv "$@"
    fi
}

# Wrapper for rmdir command
rmdir() {
    local protected_paths=()

    # Check all arguments
    for arg in "$@"; do
        # Skip flags
        [[ "$arg" == -* ]] && continue

        # Check if this path should be protected
        if is_git_path "$arg"; then
            protected_paths+=("$arg")
        fi
    done

    # If protected paths found, block the operation
    if [[ ${#protected_paths[@]} -gt 0 ]]; then
        echo "❌ ERROR: Attempting to remove .git directory is BLOCKED" >&2
        echo "" >&2
        echo "Protected paths detected:" >&2
        for path in "${protected_paths[@]}"; do
            echo "  - $path" >&2
        done
        echo "" >&2
        echo "⚠️  This protection prevents accidental deletion of git repositories." >&2
        echo "⚠️  This operation cannot be bypassed for safety reasons." >&2
        echo "" >&2
        echo "If you need to manage .git directories, exit the container and" >&2
        echo "perform the operation on the host system." >&2

        log_protection "rmdir $*"
        return 1
    fi

    # Safe to execute - use original command
    if [[ -x /usr/local/lib/original/rmdir ]]; then
        /usr/local/lib/original/rmdir "$@"
    else
        command rmdir "$@"
    fi
}

# Export functions for subshells
export -f rm mv rmdir is_git_path log_protection

# Log initialization
if [[ ! -f "$PROTECTOR_LOG" ]]; then
    touch "$PROTECTOR_LOG" 2>/dev/null
    chmod 666 "$PROTECTOR_LOG" 2>/dev/null
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Git Protector initialized" >> "$PROTECTOR_LOG" 2>/dev/null
