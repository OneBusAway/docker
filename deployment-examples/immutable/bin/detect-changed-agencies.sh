#!/bin/bash
# detect-changed-agencies.sh

# Usage information
function usage {
  echo "Usage: $0 [--current-tag TAG] [--previous-tag TAG] [--json]" >&2
  echo "  --current-tag TAG   : Specify the current release tag (default: latest tag)" >&2
  echo "  --previous-tag TAG  : Specify the previous release tag (default: auto-detect)" >&2
  echo "  --json              : Output results as JSON array" >&2
  exit 1
}

# Parse command line arguments
JSON_OUTPUT=false
CURRENT_TAG=""
PREVIOUS_TAG=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --current-tag) CURRENT_TAG="$2"; shift ;;
    --previous-tag) PREVIOUS_TAG="$2"; shift ;;
    --json) JSON_OUTPUT=true ;;
    -h|--help) usage ;;
    *) echo "Unknown parameter: $1" >&2; usage ;;
  esac
  shift
done

# If no current tag specified, use the latest tag
if [ -z "$CURRENT_TAG" ]; then
  CURRENT_TAG=$(git tag --sort=-creatordate | head -n 1)
  if [ -z "$CURRENT_TAG" ]; then
    echo "No tags found in repository. Please specify --current-tag." >&2
    exit 1
  fi
  echo "Using latest tag: $CURRENT_TAG" >&2
fi

# If no previous tag specified, find the previous one
if [ -z "$PREVIOUS_TAG" ]; then
  PREVIOUS_TAG=$(git tag --sort=-creatordate | grep -v "$CURRENT_TAG" | head -n 1)
  if [ -z "$PREVIOUS_TAG" ]; then
    echo "No previous tag found. Please specify --previous-tag." >&2
    exit 1
  fi
  echo "Using previous tag: $PREVIOUS_TAG" >&2
fi

# Get changed Dockerfiles between the tags
CHANGED_FILES=$(git diff --name-only "$PREVIOUS_TAG" "$CURRENT_TAG" | grep "^Dockerfile\." || true)

# Extract agency names
AGENCIES=()
while read -r file; do
  if [[ "$file" == Dockerfile.* ]]; then
    AGENCY=$(echo "$file" | sed 's/Dockerfile\.//')
    AGENCIES+=("$AGENCY")
  fi
done <<< "$CHANGED_FILES"

# Output results
if [ "${#AGENCIES[@]}" -eq 0 ]; then
  echo "No Dockerfile changes detected between $PREVIOUS_TAG and $CURRENT_TAG" >&2
  if [ "$JSON_OUTPUT" = true ]; then
    echo "[]"
  fi
  exit 0
fi

if [ "$JSON_OUTPUT" = true ]; then
  # Output as JSON array (requires jq) - on a single line
  printf '%s\n' "${AGENCIES[@]}" | sort | uniq | jq -R . | jq -s -c .
else
  # Output as simple list
  echo "Changed agencies between $PREVIOUS_TAG and $CURRENT_TAG:" >&2
  printf '%s\n' "${AGENCIES[@]}" | sort | uniq
fi
