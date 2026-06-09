#!/bin/sh
TIME_STAMP=$(date "+%Y-%m-%d %H:%M:%S")
DATE_STAMP=$(date +%Y-%m-%d)
LOG_FILE="/etc/borgmatic.d/mount_logs/mounts-${DATE_STAMP}.log"

echo "[$TIME_STAMP] --- Cleaning up snapshot mounts ---" >> "$LOG_FILE"

# Find all active stable_data bind mounts and unmount them
MOUNTS=$(grep " /stable_data/" /proc/mounts | cut -d' ' -f2 | sort -r)
if [ -n "$MOUNTS" ]; then
    for m in $MOUNTS; do
        umount "$m" 2>/dev/null
        
        LOG_MSG="UNMAPPED: $m"
        echo "[$TIME_STAMP] $LOG_MSG" >> "$LOG_FILE"
        logger -t "borg-zfs-hook" "$LOG_MSG"
    done
fi
