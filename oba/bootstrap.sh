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

# Build the FEEDS array for the transit-data-federation data-sources.xml.
# Prefer the multi-feed GTFS_RT_FEEDS env var; fall back to the legacy
# single-feed vars so already-deployed Dockerfiles keep working.
# Strip whitespace for the guard only, so a blank/whitespace GTFS_RT_FEEDS
# falls through to the legacy/no-feeds path instead of producing invalid JSON.
GTFS_RT_FEEDS_TRIMMED="$(printf '%s' "$GTFS_RT_FEEDS" | tr -d '[:space:]')"
if [ -n "$GTFS_RT_FEEDS_TRIMMED" ] && [ "$GTFS_RT_FEEDS_TRIMMED" != "[]" ]; then
    echo "GTFS_RT_FEEDS is set. Rendering multiple GTFS-RT feeds."
    FEEDS_JSON="$GTFS_RT_FEEDS"
elif [ -n "$TRIP_UPDATES_URL" ] || [ -n "$VEHICLE_POSITIONS_URL" ]; then
    echo "Legacy single-feed GTFS-RT env vars are set. Normalizing into one feed."
    if [ -n "$AGENCY_ID_LIST" ]; then
        AGENCY_IDS_JSON="$AGENCY_ID_LIST"
    elif [ -n "$AGENCY_ID" ]; then
        AGENCY_IDS_JSON="[\"$AGENCY_ID\"]"
    else
        AGENCY_IDS_JSON="[]"
    fi
    FEEDS_JSON=$(cat <<EOF
[{
  "tripUpdatesUrl": "$TRIP_UPDATES_URL",
  "vehiclePositionsUrl": "$VEHICLE_POSITIONS_URL",
  "alertsUrl": "$ALERTS_URL",
  "refreshInterval": "$REFRESH_INTERVAL",
  "agencyIds": $AGENCY_IDS_JSON,
  "feedApiKey": "$FEED_API_KEY",
  "feedApiValue": "$FEED_API_VALUE"
}]
EOF
)
else
    FEEDS_JSON="[]"
    echo "No GTFS-RT environment variables are set. No realtime feeds will be configured."
fi

JSON_CONFIG="{ \"FEEDS\": $FEEDS_JSON }"

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
