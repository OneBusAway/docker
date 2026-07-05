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

set -euo pipefail

# Normalize env so `set -u` can't trip on optional vars.
GTFS_URL=${GTFS_URL:-}
GTFS_ZIP_FILENAME=${GTFS_ZIP_FILENAME:-}
BUNDLE_INPUTS_URL=${BUNDLE_INPUTS_URL:-}
STOP_CONSOLIDATION_URL=${STOP_CONSOLIDATION_URL:-}
OBA_VERSION=${OBA_VERSION:-}
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

# Overridable for tests; production always uses /bundle.
BUNDLE_DIR=${BUNDLE_DIR:-/bundle}

validate_mode_env() {
    if [ -n "$BUNDLE_INPUTS_URL" ] && { [ -n "$GTFS_URL" ] || [ -n "$GTFS_ZIP_FILENAME" ]; }; then
        echo "Error: BUNDLE_INPUTS_URL cannot be combined with GTFS_URL or GTFS_ZIP_FILENAME. Please provide only one mode."
        exit 1
    fi

    if [ -n "$BUNDLE_INPUTS_URL" ] && [ -n "$STOP_CONSOLIDATION_URL" ]; then
        echo "Error: STOP_CONSOLIDATION_URL cannot be set in multi-input mode; the mapping comes from the manifest's stopConsolidationUrl."
        exit 1
    fi

    if [ -n "$BUNDLE_INPUTS_URL" ]; then
        return 0
    fi

    # Check that either GTFS_URL or GTFS_ZIP_FILENAME is set, but not both
    if [ -n "$GTFS_URL" ] && [ -n "$GTFS_ZIP_FILENAME" ]; then
        echo "Error: Both GTFS_URL and GTFS_ZIP_FILENAME are set. Please provide only one."
        exit 1
    fi

    if [ -z "$GTFS_URL" ] && [ -z "$GTFS_ZIP_FILENAME" ]; then
        echo "Error: Neither GTFS_URL nor GTFS_ZIP_FILENAME is set. Please provide one."
        exit 1
    fi
}

bundle_mode() {
    if [ -n "$BUNDLE_INPUTS_URL" ]; then
        echo "multi"
    else
        echo "single"
    fi
}

# fetch_url URL DEST LABEL — download with a one-line diagnostic on failure.
fetch_url() {
    local url="$1" dest="$2" label="$3"
    if ! wget -O "$dest" "$url"; then
        echo "ERROR: failed to download ${label} from ${url}" >&2
        exit 1
    fi
}

# Downloads manifest, feed zips, and optional mapping. Requires jq.
# Sets MAPPING_PATH to the downloaded mapping file path, or "" when absent.
MAPPING_PATH=""

download_bundle_inputs() {
    local inputs_dir="$BUNDLE_DIR/inputs"
    local manifest="$inputs_dir/bundle-inputs.json"
    mkdir -p "$inputs_dir"

    fetch_url "$BUNDLE_INPUTS_URL" "$manifest" "bundle-inputs manifest"

    local version
    version="$(jq -r '.version' "$manifest")"
    if [ "$version" != "1" ]; then
        echo "ERROR: unsupported bundle-inputs version: ${version}" >&2
        exit 1
    fi

    local feed_count
    feed_count="$(jq -r '.feeds | length' "$manifest")"
    if [ "$feed_count" -eq 0 ]; then
        echo "ERROR: bundle-inputs manifest lists no feeds" >&2
        exit 1
    fi

    local i id url sha dest
    i=0
    while [ "$i" -lt "$feed_count" ]; do
        id="$(jq -r ".feeds[$i].id" "$manifest")"
        url="$(jq -r ".feeds[$i].url" "$manifest")"
        sha="$(jq -r ".feeds[$i].sha256 // empty" "$manifest")"
        dest="$inputs_dir/${id}.zip"

        if ! wget -O "$dest" "$url"; then
            echo "ERROR: failed to download feed '${id}' from ${url}" >&2
            exit 1
        fi

        if [ -n "$sha" ]; then
            if ! echo "${sha}  ${dest}" | sha256sum -c - > /dev/null 2>&1; then
                echo "ERROR: sha256 mismatch for feed '${id}' (${dest})" >&2
                exit 1
            fi
        fi
        i=$((i + 1))
    done

    local mapping_url
    mapping_url="$(jq -r '.stopConsolidationUrl // empty' "$manifest")"
    if [ -n "$mapping_url" ]; then
        # StopConsolidation.txt is the hardcoded filename ConsolidatedStopsServiceImpl
        # reads from the bundle directory at runtime.
        MAPPING_PATH="$BUNDLE_DIR/StopConsolidation.txt"
        fetch_url "$mapping_url" "$MAPPING_PATH" "stop consolidation mapping"
    else
        MAPPING_PATH=""
    fi
}

# generate_bundle_context_xml MANIFEST_JSON INPUTS_DIR MAPPING_PATH OUT_XML
# Bean id "gtfs-bundles" and bean name "entityReplacementStrategy" are looked up
# by those exact names inside the federation builder — do not rename.
generate_bundle_context_xml() {
    local manifest="$1" inputs_dir="$2" mapping_path="$3" out_xml="$4"

    {
        cat <<'XMLHEAD'
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans-2.5.xsd">

    <bean id="gtfs-bundles" class="org.onebusaway.transit_data_federation.bundle.model.GtfsBundles">
        <property name="bundles">
            <list>
XMLHEAD

        local feed_count i id agency
        feed_count="$(jq -r '.feeds | length' "$manifest")"
        i=0
        while [ "$i" -lt "$feed_count" ]; do
            id="$(jq -r ".feeds[$i].id" "$manifest")"
            agency="$(jq -r ".feeds[$i].defaultAgencyId" "$manifest")"
            cat <<XMLFEED
                <bean class="org.onebusaway.transit_data_federation.bundle.model.GtfsBundle">
                    <property name="path" value="${inputs_dir}/${id}.zip" />
                    <property name="defaultAgencyId" value="${agency}" />
                </bean>
XMLFEED
            i=$((i + 1))
        done

        cat <<'XMLMID'
            </list>
        </property>
    </bean>
XMLMID

        if [ -n "$mapping_path" ]; then
            cat <<XMLMAP

    <bean id="entityReplacementStrategyFactory" class="org.onebusaway.transit_data_federation.bundle.tasks.EntityReplacementStrategyFactory">
        <property name="entityMappings">
            <map>
                <entry key="org.onebusaway.gtfs.model.Stop" value="${mapping_path}" />
            </map>
        </property>
    </bean>
    <bean id="entityReplacementStrategy" factory-bean="entityReplacementStrategyFactory" factory-method="create" />
XMLMAP
        fi

        cat <<'XMLTAIL'

</beans>
XMLTAIL
    } > "$out_xml"
}

run_single_mode() {
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

    cd "$BUNDLE_DIR"

    # Download GTFS file if URL is provided, otherwise use local file
    if [ -n "$GTFS_URL" ]; then
        fetch_url "$GTFS_URL" "$BUNDLE_DIR/$GTFS_ZIP_FILENAME" "GTFS feed"
    else
        # Check if the local file exists
        if [ ! -f "$GTFS_ZIP_FILENAME" ]; then
            echo "Error: GTFS file not found: $GTFS_ZIP_FILENAME"
            exit 1
        fi
    fi

    gtfstidy -"${GTFS_TIDY_ARGS}" "${GTFS_ZIP_FILENAME}"

    if [[ -d "gtfs-out" ]]; then
        cd gtfs-out
        zip ../gtfs_tidied.zip *
        cd ..
        GTFS_ZIP_FILENAME="gtfs_tidied.zip"
    fi

    # The JAR must be executed from within the same directory
    # as the bundle, or else some necessary files are not generated.
    java -Xss4m -Xmx3g -jar "$TDF_BUILDER_JAR" ./"${GTFS_ZIP_FILENAME}" .
}

run_multi_mode() {
    echo "OBA Bundle Builder Starting"
    echo "Multi-input mode: BUNDLE_INPUTS_URL: $BUNDLE_INPUTS_URL"
    echo "ERROR: multi-input mode not yet implemented" >&2
    exit 1
}

main() {
    validate_mode_env
    if [ "$(bundle_mode)" = "multi" ]; then
        run_multi_mode
    else
        run_single_mode
    fi
}

# Main guard: allow tests to `source` this file without executing.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
