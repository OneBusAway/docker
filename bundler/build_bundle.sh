#!/bin/bash

#
# Copyright (C) 2024 Open Transit Software Foundation <info@onebusaway.org>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Check that either GTFS_URL or GTFS_ZIP_FILENAME is set, but not both
if [ -n "$GTFS_URL" ] && [ -n "$GTFS_ZIP_FILENAME" ]; then
    echo "Error: Both GTFS_URL and GTFS_ZIP_FILENAME are set. Please provide only one."
    exit 1
fi

if [ -z "$GTFS_URL" ] && [ -z "$GTFS_ZIP_FILENAME" ]; then
    echo "Error: Neither GTFS_URL nor GTFS_ZIP_FILENAME is set. Please provide one."
    exit 1
fi

TDF_BUILDER_JAR=${TDF_BUILDER_JAR:-/oba/libs/onebusaway-transit-data-federation-builder-withAllDependencies.jar}

# Run gtfstidy (https://github.com/patrickbr/gtfstidy) with the following options enabled by default:
# -O: remove entities that are not referenced anywhere
# -s: minimize shapes (using Douglas-Peucker)
# -c: minimize services by searching for the optimal exception/range coverage
# -R: remove route duplicates
# -C: remove duplicate services in calendar.txt and calendar_dates.txt
# -S: remove shape duplicates
# -m: remeasure shapes (filling measurement-holes)
# -e: if non-required fields have errors, fall back to the default values
# -D: drop erroneous entries from feed
GTFS_TIDY_ARGS=${GTFS_TIDY_ARGS:-OscRCSmeD}

# Set default filename if using GTFS_URL
if [ -n "$GTFS_URL" ]; then
    GTFS_ZIP_FILENAME="gtfs_pristine.zip"
fi

echo "OBA Bundle Builder Starting"
if [ -n "$GTFS_URL" ]; then
    echo "GTFS_URL: $GTFS_URL"
else
    echo "GTFS_ZIP_FILENAME: $GTFS_ZIP_FILENAME"
fi
echo "OBA Version: $OBA_VERSION"
echo "GTFS Tidy Args: $GTFS_TIDY_ARGS"
echo "TDF_BUILDER_JAR: $TDF_BUILDER_JAR"

cd /bundle

# Download GTFS file if URL is provided, otherwise use local file
if [ -n "$GTFS_URL" ]; then
    wget -O ${GTFS_ZIP_FILENAME} ${GTFS_URL}
else
    # Check if the local file exists
    if [ ! -f "$GTFS_ZIP_FILENAME" ]; then
        echo "Error: GTFS file not found: $GTFS_ZIP_FILENAME"
        exit 1
    fi
fi

gtfstidy -${GTFS_TIDY_ARGS} ${GTFS_ZIP_FILENAME}

if [[ -d "gtfs-out" ]]; then
    cd gtfs-out
    zip ../gtfs_tidied.zip *
    cd ..
    GTFS_ZIP_FILENAME="gtfs_tidied.zip"
fi

# The JAR must be executed from within the same directory
# as the bundle, or else some necessary files are not generated.
java -Xss4m -Xmx3g -jar $TDF_BUILDER_JAR ./${GTFS_ZIP_FILENAME} .
