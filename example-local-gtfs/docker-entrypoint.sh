#!/bin/bash

# This entrypoint script handles copying the local GTFS file from the build-time
# location (/tmp) to the runtime location (/bundle) after volumes are mounted.
#
# Why this is needed:
# - At build time, we copy the GTFS zip file to /tmp
# - At runtime, Docker mounts the host's bundle directory to /bundle
# - This mount would hide any files we copied to /bundle during build
# - So we copy the file after the volume is mounted

# Find the GTFS zip file that was copied during build
GTFS_FILE=$(find /tmp -name "*.zip" -type f | head -1)

if [ -z "$GTFS_FILE" ]; then
    echo "Error: No GTFS zip file found in /tmp"
    echo "Make sure your GTFS zip file is in the build context"
    exit 1
fi

# Copy the file to the bundle directory with the expected name
echo "Found GTFS file: $GTFS_FILE"
echo "Copying to: /bundle/${GTFS_ZIP_FILENAME}"
cp "$GTFS_FILE" "/bundle/${GTFS_ZIP_FILENAME}"

if [ $? -ne 0 ]; then
    echo "Error: Failed to copy GTFS file to /bundle"
    exit 1
fi

echo "GTFS file copied successfully"

# Execute the original command (supervisord or build_bundle.sh)
# "$@" expands to all arguments passed to this script
exec "$@"