#!/bin/bash
# extract-agencies.sh

# Read the list of changed Dockerfiles (either from stdin or a file)
if [ -n "$1" ]; then
  CHANGED_FILES=$(cat "$1")
else
  CHANGED_FILES=$(cat)
fi

# Extract agency names from Dockerfile changes
AGENCIES=()
while read -r file; do
  if [[ "$file" == Dockerfile.* ]]; then
    AGENCY=$(echo "$file" | sed 's/Dockerfile\.//')
    AGENCIES+=("$AGENCY")
  fi
done <<< "$CHANGED_FILES"

# Output as a simple list by default
if [ "${#AGENCIES[@]}" -eq 0 ]; then
  echo "No agencies extracted"
  exit 0
fi

# Format output
if [ "$2" = "--json" ]; then
  # Output as JSON array (requires jq)
  printf '%s\n' "${AGENCIES[@]}" | jq -R . | jq -s .
else
  # Output as simple list
  printf '%s\n' "${AGENCIES[@]}" | sort | uniq
fi