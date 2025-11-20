#!/bin/bash
#
# Git Guardian - Monitors and protects .git directories
# This daemon runs in the background and:
# 1. Monitors .git directories for deletion attempts
# 2. Automatically creates backups when changes detected
# 3. Restores .git if deleted
#

BACKUP_DIR="/var/backups/git-guardian"
LOG_FILE="/var/log/git-guardian.log"
CHECK_INTERVAL=5  # seconds

# Initialize
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"
chmod 666 "$LOG_FILE"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

create_backup() {
    local git_dir="$1"
    local backup_name="$(echo "$git_dir" | tr '/' '_')_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"

    if [[ -d "$git_dir" ]]; then
        cp -a "$git_dir" "$backup_path" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_message "✓ Created backup: $backup_path"
            # Keep only last 3 backups for this directory
            ls -t "$BACKUP_DIR" | grep "^$(echo "$git_dir" | tr '/' '_')" | tail -n +4 | \
                xargs -I {} rm -rf "$BACKUP_DIR/{}" 2>/dev/null
            return 0
        fi
    fi
    return 1
}

restore_from_backup() {
    local git_dir="$1"
    local latest_backup=$(ls -t "$BACKUP_DIR" | grep "^$(echo "$git_dir" | tr '/' '_')" | head -1)

    if [[ -n "$latest_backup" ]]; then
        log_message "⚠️  Detected .git deletion: $git_dir"
        log_message "🔄 Restoring from backup: $latest_backup"

        cp -a "$BACKUP_DIR/$latest_backup" "$git_dir" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_message "✓ Successfully restored: $git_dir"
            return 0
        else
            log_message "❌ Failed to restore: $git_dir"
            return 1
        fi
    fi

    log_message "❌ No backup found for: $git_dir"
    return 1
}

monitor_directories() {
    # Track known .git directories
    declare -A known_git_dirs

    if [[ -n "$GBOX_WORK_DIR" ]] && [[ -d "$GBOX_WORK_DIR" ]]; then
        # Initial scan: find all existing .git directories
        while IFS= read -r -d '' git_dir; do
            known_git_dirs["$git_dir"]=1
            log_message "📍 Tracking: $git_dir"
        done < <(find "$GBOX_WORK_DIR" -maxdepth 3 -type d -name ".git" -print0 2>/dev/null)

        # Monitoring loop
        while true; do
            # Check all known .git directories
            for git_dir in "${!known_git_dirs[@]}"; do
                if [[ ! -d "$git_dir" ]]; then
                    # .git directory was deleted, try to restore
                    log_message "⚠️  Detected deletion: $git_dir"
                    restore_from_backup "$git_dir"
                    # If restore succeeded, keep tracking
                    if [[ -d "$git_dir" ]]; then
                        known_git_dirs["$git_dir"]=1
                    fi
                else
                    # .git exists, create periodic backup
                    create_backup "$git_dir"
                fi
            done

            # Also scan for new .git directories
            while IFS= read -r -d '' git_dir; do
                if [[ -z "${known_git_dirs[$git_dir]}" ]]; then
                    known_git_dirs["$git_dir"]=1
                    log_message "📍 New .git detected: $git_dir"
                    create_backup "$git_dir"
                fi
            done < <(find "$GBOX_WORK_DIR" -maxdepth 3 -type d -name ".git" -print0 2>/dev/null)

            sleep "$CHECK_INTERVAL"
        done
    else
        log_message "⚠️  GBOX_WORK_DIR not set or not found"
    fi
}

# Main
log_message "🛡️  Git Guardian started (PID: $$)"
log_message "   Monitoring: ${GBOX_WORK_DIR:-unknown}"
log_message "   Check interval: ${CHECK_INTERVAL}s"

# Create initial backups
if [[ -n "$GBOX_WORK_DIR" ]] && [[ -d "$GBOX_WORK_DIR" ]]; then
    while IFS= read -r -d '' git_dir; do
        create_backup "$git_dir"
    done < <(find "$GBOX_WORK_DIR" -maxdepth 3 -type d -name ".git" -print0 2>/dev/null)
fi

# Start monitoring
monitor_directories
