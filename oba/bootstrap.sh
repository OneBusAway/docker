#!/bin/bash

# Build bundle inside the container
if [ -n "$GTFS_URL" ]; then
    echo "GTFS_URL is set, building bundle from bootstrap.sh with build_bundle.sh"
    mkdir -p /bundle
    /oba/build_bundle.sh
fi

# For users who want to configure the data-sources.xml file and database themselves
if [ -n "$USER_CONFIGURED" ]; then
    echo "USER_CONFIGURED is set, you should create your own configuration file, Aborting..."
    exit 0
fi

#####
# onebusaway-api-webapp
#####

API_XML_SOURCE="/oba/config/onebusaway-api-webapp-data-sources.xml.hbs"
API_XML_DESTINATION="$CATALINA_HOME/webapps/ROOT/WEB-INF/classes/data-sources.xml"

hbs_renderer -input "$API_XML_SOURCE" \
             -json '{"TEST_API_KEY": "'$TEST_API_KEY'", "JDBC_DRIVER": "'$JDBC_DRIVER'"}' \
             -output "$API_XML_DESTINATION"

#####
# onebusaway-transit-data-federation-webapp
#####

FEDERATION_XML_SOURCE="/oba/config/onebusaway-transit-data-federation-webapp-data-sources.xml.hbs"
FEDERATION_XML_DESTINATION="$CATALINA_HOME/webapps/onebusaway-transit-data-federation-webapp/WEB-INF/classes/data-sources.xml"

if [ -z "$TRIP_UPDATES_URL" ] && [ -z "$VEHICLE_POSITIONS_URL" ]; then
    GTFS_RT_AVAILABLE=""
    echo "No GTFS-RT related environment variables are set. Removing element from data-sources.xml"
else
    GTFS_RT_AVAILABLE="1"
    echo "GTFS-RT related environment variables are set. Setting them in data-sources.xml"
fi

# Check if the GTFS_RT authentication header is set
if [ -n "$FEED_API_KEY" ] && [ -n "$FEED_API_VALUE" ]; then
    HAS_API_KEY="1"
else
    HAS_API_KEY=""
fi

# Handle AGENCY_ID_LIST properly - if it's a JSON array, use it directly, otherwise treat as empty
if [ -n "$AGENCY_ID_LIST" ]; then
    # Remove the outer quotes if they exist and use the array directly
    AGENCY_ID_LIST_JSON="$AGENCY_ID_LIST"
else
    AGENCY_ID_LIST_JSON="[]"
fi

# Build the JSON string with proper handling of AGENCY_ID_LIST
JSON_CONFIG=$(cat <<EOF
{
    "GTFS_RT_AVAILABLE": "$GTFS_RT_AVAILABLE",
    "TRIP_UPDATES_URL": "$TRIP_UPDATES_URL",
    "VEHICLE_POSITIONS_URL": "$VEHICLE_POSITIONS_URL",
    "ALERTS_URL": "$ALERTS_URL",
    "REFRESH_INTERVAL": "$REFRESH_INTERVAL",
    "AGENCY_ID": "$AGENCY_ID",
    "AGENCY_ID_LIST": $AGENCY_ID_LIST_JSON,
    "HAS_API_KEY": "$HAS_API_KEY",
    "FEED_API_KEY": "$FEED_API_KEY",
    "FEED_API_VALUE": "$FEED_API_VALUE"
}
EOF
)

hbs_renderer -input "$FEDERATION_XML_SOURCE" \
             -json "$JSON_CONFIG" \
             -output "$FEDERATION_XML_DESTINATION"

#####
# Tomcat context.xml
#####

CONTEXT_SOURCE="/oba/config/context.xml.hbs"
CONTEXT_DESTINATION="$CATALINA_HOME/conf/context.xml"

hbs_renderer -input "$CONTEXT_SOURCE" \
             -json '{"JDBC_URL": "'$JDBC_URL'", "JDBC_DRIVER": "'$JDBC_DRIVER'", "JDBC_USER": "'$JDBC_USER'", "JDBC_PASSWORD": "'$JDBC_PASSWORD'"}' \
             -output "$CONTEXT_DESTINATION"
