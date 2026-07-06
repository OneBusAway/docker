#!/bin/bash
# Builds two 3-stop fixture GTFS zips (metro: agency 1, pierce: agency 3)
# into the directory given as $1. Stops M2/P2 sit at identical coordinates
# so consolidating "1_M2 3_P2" is geometrically sensible.
set -euo pipefail
OUT="${1:?usage: make_fixtures.sh OUT_DIR}"
mkdir -p "$OUT"

make_feed() {
    local dir="$1" agency_id="$2" agency_name="$3" prefix="$4"
    mkdir -p "$dir"
    cat > "$dir/agency.txt" <<EOF
agency_id,agency_name,agency_url,agency_timezone
${agency_id},${agency_name},https://example.org,America/Los_Angeles
EOF
    cat > "$dir/stops.txt" <<EOF
stop_id,stop_name,stop_lat,stop_lon
${prefix}1,First St,47.6000,-122.3300
${prefix}2,Shared Plaza,47.6100,-122.3350
${prefix}3,Third St,47.6200,-122.3400
EOF
    cat > "$dir/routes.txt" <<EOF
route_id,agency_id,route_short_name,route_long_name,route_type
${prefix}R1,${agency_id},${prefix}1,${agency_name} Line,3
EOF
    cat > "$dir/calendar.txt" <<EOF
service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date
${prefix}WEEK,1,1,1,1,1,0,0,20260101,20261231
EOF
    cat > "$dir/trips.txt" <<EOF
route_id,service_id,trip_id
${prefix}R1,${prefix}WEEK,${prefix}T1
EOF
    cat > "$dir/stop_times.txt" <<EOF
trip_id,arrival_time,departure_time,stop_id,stop_sequence
${prefix}T1,08:00:00,08:00:00,${prefix}1,1
${prefix}T1,08:05:00,08:05:00,${prefix}2,2
${prefix}T1,08:10:00,08:10:00,${prefix}3,3
EOF
    (cd "$dir" && zip -q "../$(basename "$dir").zip" ./*.txt)
    rm -r "$dir"
}

make_feed "$OUT/metro"  "1" "King County Metro" "M"
make_feed "$OUT/pierce" "3" "Pierce Transit"    "P"
