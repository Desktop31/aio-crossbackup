#!/bin/sh
PATTERN_FILE="/etc/borgmatic.d/dynamic_roots.lst"

# 1. Grab the variable from Docker, or use a safe default if missing
PREFIX="${SNAPSHOT_PREFIX:-auto-}"

# 2. Clear the file from the previous run
true > "$PATTERN_FILE"

# 3. Find parent directories using the dynamic prefix
PARENTS=$(find /source_data -type d -name "${PREFIX}*" | sed 's|/[^/]*$||' | sort -u)

# 4. Loop through each dataset
for parent in $PARENTS; do
  
  LATEST_PATH=""
  
  # 5. Use a glob to find snapshots. The shell expands these alphabetically.
  for dir in "$parent/${PREFIX}"*; do
    # Ensure the directory actually exists (handles cases where the glob finds nothing)
    if [ -d "$dir" ]; then
      # Overwrite the variable. The loop naturally ends on the newest (last) snapshot.
      LATEST_PATH="$dir"
    fi
  done
  
  # 6. If we found a valid snapshot, append it to the Borgmatic list
  if [ -n "$LATEST_PATH" ]; then
    echo "R $LATEST_PATH" >> "$PATTERN_FILE"
  fi
  
done
