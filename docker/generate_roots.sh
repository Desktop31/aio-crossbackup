#!/bin/sh
PATTERN_FILE="/etc/borgmatic.d/dynamic_roots.lst"
PREFIX="${SNAPSHOT_PREFIX:-storage-}"

# 1. Clean up stale bind mounts from the previous day's run
MOUNTS=$(grep " /stable_data/" /proc/mounts | cut -d' ' -f2 | sort -r)
if [ -n "$MOUNTS" ]; then
    for m in $MOUNTS; do
        umount "$m" 2>/dev/null
    done
fi

# 2. Clear the Borg pattern file
true > "$PATTERN_FILE"

# 3. Find parent directories dynamically mapped via Docker volumes
PARENTS=$(grep " /source_data/" /proc/mounts | cut -d' ' -f2)

# 4. Loop through each dataset
for parent in $PARENTS; do
  
  LATEST_PATH=""
  
  # Find the newest chronological snapshot
  for dir in "$parent/${PREFIX}"*; do
    if [ -d "$dir" ]; then
      LATEST_PATH="$dir"
    fi
  done
  
  if [ -n "$LATEST_PATH" ]; then
    # Generate a perfectly static path (e.g., /stable_data/main-storage/d31-private)
    STABLE_PATH=$(echo "$parent" | sed 's|^/source_data|/stable_data|')
    
    # Create the static directory inside the container
    mkdir -p "$STABLE_PATH"
    
    # Bind mount the dynamic snapshot to the static directory
    mount -o bind "$LATEST_PATH" "$STABLE_PATH"
    
    # Give Borgmatic the static path
    echo "R $STABLE_PATH" >> "$PATTERN_FILE"
  fi
  
done
