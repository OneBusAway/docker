#!/bin/bash

OBA_USER="${OBA_USER:-oba_user}"
OBA_GROUP="${OBA_GROUP:-oba_group}"

# abort MESSAGE — fail closed on a configuration error.
# Exiting non-zero is not enough: supervisord starts Tomcat as soon as this
# script reaches EXITED, whatever its status (dependent_startup_wait_for=
# start:exited), so Tomcat would come up on the stale or default config. Stop
# supervisord (PID 1) so the container exits and the error is visible.
abort() {
    echo "ERROR: $*" >&2
    supervisorctl shutdown >/dev/null 2>&1 || kill -TERM 1
    exit 1
}

# Build bundle inside the container
if [ -n "$GTFS_URL" ]; then
    echo "GTFS_URL is set, building bundle from bootstrap.sh with build_bundle.sh"
    mkdir -p /bundle
    # The build downloads and parses third-party GTFS data, so it runs as the
    # unprivileged user rather than root.
    chown -R "$OBA_USER:$OBA_GROUP" /bundle \
        || abort "could not prepare /bundle for the bundle build"
    setpriv --reuid="$OBA_USER" --regid="$OBA_GROUP" --init-groups \
        env HOME="/home/$OBA_USER" /oba/build_bundle.sh \
        || abort "bundle build failed; not starting Tomcat on a missing or partial bundle"
fi

# Whoever built the bundle (this script or the separate bundler image), the
# running webapp only needs to read it. Hand it to root, group-readable by the
# Tomcat group, so a compromised webapp cannot tamper with the transit data it
# serves but can still read a bundle that was built with a restrictive umask.
# Group and other write bits are cleared too: the group is Tomcat's, so a
# group-writable entry (e.g. from a bind mount) would stay writable to it.
# Only files that aren't already root's are touched: chown on an image-baked
# bundle would copy every file into the container's writable layer.
# chmod is limited to regular files and directories (find does not follow
# symlinks) and chown uses -h, so a symlink planted by the unprivileged build
# can't redirect either one at a file outside /bundle.
if [ -d /bundle ]; then
    { find /bundle ! -user root \( -type f -o -type d \) -exec chmod g+rX,go-w {} + \
        && find /bundle ! -user root -exec chown -h "root:$OBA_GROUP" {} + ; } 2>/dev/null \
        || echo "WARNING: could not change ownership of /bundle (read-only mount?); continuing."
fi

API_XML_SOURCE="/oba/config/onebusaway-api-webapp-data-sources.xml.hbs"
API_XML_DESTINATION="$CATALINA_HOME/webapps/ROOT/WEB-INF/classes/data-sources.xml"

# For users who want to configure the data-sources.xml file and database themselves
if [ -n "$USER_CONFIGURED" ]; then
    echo "USER_CONFIGURED is set; skipping data-sources.xml rendering. Supply your own configuration files."
    # The federation webapp moved off the public port (see conf/server.xml). A
    # user-supplied config written for older images still points at :8080 and
    # would fail every API request with connection errors, so refuse to start.
    if grep -qE '(localhost|127\.0\.0\.1):8080/onebusaway-transit-data-federation-webapp' "$API_XML_DESTINATION" 2>/dev/null; then
        abort "$API_XML_DESTINATION points the transitDataService at port 8080, but the federation webapp is now only served on the loopback-only internal connector. Change the serviceUrl to http://127.0.0.1:8081/onebusaway-transit-data-federation-webapp/remoting/transit-data-service"
    fi
    exit 0
fi

#####
# onebusaway-api-webapp
#####

# render SOURCE DESTINATION JSON
# Rendered files contain credentials (database password, feed API keys):
# readable by root and the Tomcat group only. A failed render stops the
# container rather than letting Tomcat start on a stale or default config.
render() {
    local source="$1" destination="$2" json="$3"
    if ! hbs_renderer -input "$source" -json "$json" -output "$destination"; then
        abort "failed to render $destination"
    fi
    chown "root:$OBA_GROUP" "$destination"
    chmod 640 "$destination"
}

# JSON is built with jq so values containing quotes, spaces, or backslashes are
# encoded correctly instead of corrupting (or injecting into) the document.
API_JSON="$(jq -n --arg TEST_API_KEY "$TEST_API_KEY" --arg JDBC_DRIVER "$JDBC_DRIVER" '$ARGS.named')"
render "$API_XML_SOURCE" "$API_XML_DESTINATION" "$API_JSON"

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
# Any explicit (non-whitespace) value — including "[]" — takes precedence over
# the legacy vars, so operators can disable realtime feeds with GTFS_RT_FEEDS='[]'
# even when the legacy single-feed vars are still set.
GTFS_RT_FEEDS_TRIMMED="$(printf '%s' "$GTFS_RT_FEEDS" | tr -d '[:space:]')"
if [ -n "$GTFS_RT_FEEDS_TRIMMED" ]; then
    echo "GTFS_RT_FEEDS is set; using it to configure GTFS-RT feeds."
    FEEDS_JSON="$GTFS_RT_FEEDS"
elif [ -n "$TRIP_UPDATES_URL" ] || [ -n "$VEHICLE_POSITIONS_URL" ]; then
    echo "Legacy single-feed GTFS-RT env vars are set. Normalizing into one feed."
    if [ -n "$AGENCY_ID_LIST" ]; then
        AGENCY_IDS_JSON="$AGENCY_ID_LIST"
    elif [ -n "$AGENCY_ID" ]; then
        AGENCY_IDS_JSON="$(jq -n --arg id "$AGENCY_ID" '[$id]')"
    else
        AGENCY_IDS_JSON="[]"
    fi
    if ! FEEDS_JSON="$(jq -n \
            --arg tripUpdatesUrl "$TRIP_UPDATES_URL" \
            --arg vehiclePositionsUrl "$VEHICLE_POSITIONS_URL" \
            --arg alertsUrl "$ALERTS_URL" \
            --arg refreshInterval "$REFRESH_INTERVAL" \
            --argjson agencyIds "$AGENCY_IDS_JSON" \
            --arg feedApiKey "$FEED_API_KEY" \
            --arg feedApiValue "$FEED_API_VALUE" \
            '[$ARGS.named]')"; then
        abort "could not build the GTFS-RT feed config; AGENCY_ID_LIST must be valid JSON (got: $AGENCY_ID_LIST)"
    fi
else
    FEEDS_JSON="[]"
    echo "No GTFS-RT environment variables are set. No realtime feeds will be configured."
fi

JSON_CONFIG="{ \"FEEDS\": $FEEDS_JSON }"

render "$FEDERATION_XML_SOURCE" "$FEDERATION_XML_DESTINATION" "$JSON_CONFIG"

#####
# Tomcat context.xml
#####

CONTEXT_SOURCE="/oba/config/context.xml.hbs"
CONTEXT_DESTINATION="$CATALINA_HOME/conf/context.xml"

CONTEXT_JSON="$(jq -n \
    --arg JDBC_URL "$JDBC_URL" \
    --arg JDBC_DRIVER "$JDBC_DRIVER" \
    --arg JDBC_USER "$JDBC_USER" \
    --arg JDBC_PASSWORD "$JDBC_PASSWORD" \
    '$ARGS.named')"
render "$CONTEXT_SOURCE" "$CONTEXT_DESTINATION" "$CONTEXT_JSON"
