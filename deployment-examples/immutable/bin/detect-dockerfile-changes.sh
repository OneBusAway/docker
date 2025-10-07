#!/bin/bash
# detect-dockerfile-changes.sh

# Get the previous and current tags (passed as arguments)
PREVIOUS_TAG=$1
CURRENT_TAG=$2

if [ -z "$PREVIOUS_TAG" ] || [ -z "$CURRENT_TAG" ]; then
  echo "Usage: $0 <previous-tag> <current-tag>"
  exit 1
fi

# Check if both tags exist
if ! git rev-parse --verify "$PREVIOUS_TAG" > /dev/null 2>&1; then
  echo "Tag $PREVIOUS_TAG does not exist"
  exit 1
fi

if ! git rev-parse --verify "$CURRENT_TAG" > /dev/null 2>&1; then
  echo "Tag $CURRENT_TAG does not exist"
  exit 1
fi

# Get changed Dockerfiles between the two tags
CHANGED_FILES=$(git diff --name-only "$PREVIOUS_TAG" "$CURRENT_TAG" | grep "^Dockerfile\.")

# Output the list of files
if [ -z "$CHANGED_FILES" ]; then
  echo "No Dockerfile changes detected"
  exit 0
fi

echo "$CHANGED_FILES"