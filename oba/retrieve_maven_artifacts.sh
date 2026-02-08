#!/usr/bin/env bash

copy_and_rename_artifact() {
    local input_artifact=$1
    local output_filename=$2

    # Split the input_artifact into its components
    IFS=':' read -r group_id artifact_id version packaging classifiers <<< "$input_artifact"

    # Construct the expected filename
    local expected_filename="${artifact_id}-${version}"

    # Add classifiers to the expected filename if present
    if [ -n "$classifiers" ]; then
        expected_filename="${expected_filename}-${classifiers}"
    fi

    expected_filename="${expected_filename}.${packaging}"

    mvn -f pom.xml \
        dependency:copy \
        --batch-mode \
        -DoutputDirectory=/oba/libs/ \
        -Dartifact=${input_artifact}

    # Rename the file
    mv "/oba/libs/${expected_filename}" "/oba/libs/${output_filename}.${packaging}"
}

copy_and_rename_artifact \
    "org.onebusaway:onebusaway-api-webapp:${OBA_VERSION}:war" \
    "onebusaway-api-webapp"

copy_and_rename_artifact \
    "org.onebusaway:onebusaway-transit-data-federation-webapp:${OBA_VERSION}:war" \
    "onebusaway-transit-data-federation-webapp"

copy_and_rename_artifact \
    "org.onebusaway:onebusaway-transit-data-federation-builder:${OBA_VERSION}:jar:withAllDependencies" \
    "onebusaway-transit-data-federation-builder-withAllDependencies"

copy_and_rename_artifact \
    "org.onebusaway:onebusaway-api-key-cli:${OBA_VERSION}:jar:withAllDependencies" \
    "onebusaway-api-key-cli-withAllDependencies"

copy_and_rename_artifact \
    "com.mysql:mysql-connector-j:${MYSQL_CONNECTOR_VERSION}:jar" \
    "mysql-connector-j"

copy_and_rename_artifact \
    "org.postgresql:postgresql:${POSTGRESQL_CONNECTOR_VERSION}:jar" \
    "postgresql"