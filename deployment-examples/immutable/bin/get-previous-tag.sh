#!/bin/bash
# get-previous-tag.sh

# Get the current tag (you would pass this as an argument when testing)
CURRENT_TAG=$1

if [ -z "$CURRENT_TAG" ]; then
  echo "Usage: $0 <current-tag>"
  exit 1
fi

# Get the previous tag (excluding the current one)
PREVIOUS_TAG=$(git tag --sort=-creatordate | grep -v "$CURRENT_TAG" | head -n 1)

if [ -z "$PREVIOUS_TAG" ]; then
  echo "No previous tag found"
  exit 1
fi

echo "$PREVIOUS_TAG"