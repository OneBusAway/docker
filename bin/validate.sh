#!/bin/bash

output=$(curl -s "http://localhost:8080/api/where/current-time.json?key=test" | jq '.data.entry.time')

if [[ ! -z "$output" && "$output" =~ ^[0-9]+$ ]]; then
    echo "current-time.json endpoint works."
else
    echo "Error: current-time.json endpoint is not working."
    exit 1
fi

# Get the first agency from agencies-with-coverage
agency_response=$(curl -s "http://localhost:8080/api/where/agencies-with-coverage.json?key=test")
agency_count=$(echo "$agency_response" | jq '.data.list | length')

if [[ "$agency_count" -gt 0 ]]; then
    echo "agencies-with-coverage.json endpoint works (found $agency_count agencies)."
    AGENCY_ID=$(echo "$agency_response" | jq -r '.data.list[0].agencyId')
    echo "Using agency: $AGENCY_ID"
else
    echo "Error: agencies-with-coverage.json endpoint is not working or no agencies found: $agency_count"
    exit 1
fi

# Get routes for the agency
routes_response=$(curl -s "http://localhost:8080/api/where/routes-for-agency/${AGENCY_ID}.json?key=test")
route_count=$(echo "$routes_response" | jq '.data.list | length')
if [[ "$route_count" -gt 0 ]]; then
    echo "routes-for-agency/${AGENCY_ID}.json endpoint works (found $route_count routes)."
    ROUTE_ID=$(echo "$routes_response" | jq -r '.data.list[0].id')
    echo "Using route: $ROUTE_ID"
else
    echo "Error: routes-for-agency/${AGENCY_ID}.json is not working or no routes found: $route_count"
    exit 1
fi

# Get stops for the route
stops_response=$(curl -s "http://localhost:8080/api/where/stops-for-route/${ROUTE_ID}.json?key=test")
route_id_check=$(echo "$stops_response" | jq -r '.data.entry.routeId')
if [[ ! -z "$route_id_check" && "$route_id_check" == "$ROUTE_ID" ]]; then
    echo "stops-for-route/${ROUTE_ID}.json endpoint works."
    STOP_ID=$(echo "$stops_response" | jq -r '.data.entry.stopIds[0]')
    echo "Using stop: $STOP_ID"
else
    echo "Error: stops-for-route/${ROUTE_ID}.json endpoint is not working: $route_id_check"
    exit 1
fi

# Get stop details
stop_response=$(curl -s "http://localhost:8080/api/where/stop/${STOP_ID}.json?key=test")
stop_id_check=$(echo "$stop_response" | jq -r '.data.entry.id')
if [[ ! -z "$stop_id_check" && "$stop_id_check" == "$STOP_ID" ]]; then
    echo "stop/${STOP_ID}.json endpoint works."
    # Extract coordinates for stops-for-location test
    STOP_LAT=$(echo "$stop_response" | jq -r '.data.entry.lat')
    STOP_LON=$(echo "$stop_response" | jq -r '.data.entry.lon')
    echo "Using coordinates: $STOP_LAT, $STOP_LON"
else
    echo "Error: stop/${STOP_ID}.json endpoint is not working: $stop_id_check"
    exit 1
fi

# Test stops-for-location using coordinates from the stop
LOCATION_URL="http://localhost:8080/api/where/stops-for-location.json?lat=${STOP_LAT}&lon=${STOP_LON}&key=test"
location_response=$(curl -s "$LOCATION_URL")
out_of_range=$(echo "$location_response" | jq '.data.outOfRange')
stops_found=$(echo "$location_response" | jq '.data.list | length')
if [[ ! -z "$out_of_range" && "$out_of_range" == "false" && "$stops_found" -gt 0 ]]; then
    echo "stops-for-location.json endpoint works (found $stops_found stops)."
else
    echo "Error: stops-for-location.json endpoint is not working: outOfRange=$out_of_range, stops=$stops_found"
    echo "URL: $LOCATION_URL"
    echo "Response: $location_response"
    exit 1
fi

# Test arrivals-and-departures-for-stop endpoint
arrivals_response=$(curl -s "http://localhost:8080/api/where/arrivals-and-departures-for-stop/${STOP_ID}.json?key=test")
arrivals_stop_id=$(echo "$arrivals_response" | jq -r '.data.entry.stopId')
arrivals_count=$(echo "$arrivals_response" | jq '.data.entry.arrivalsAndDepartures | length // 0')

if [[ "$arrivals_stop_id" == "$STOP_ID" ]]; then
    if [[ "$arrivals_count" -gt 0 ]]; then
        echo "arrivals-and-departures-for-stop/${STOP_ID}.json endpoint works (found $arrivals_count arrivals/departures)."
    else
        echo "arrivals-and-departures-for-stop/${STOP_ID}.json endpoint works but no arrivals/departures at this time."
    fi
else
    echo "Warning: arrivals-and-departures-for-stop/${STOP_ID}.json endpoint may not be working correctly."
fi