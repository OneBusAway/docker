#!/bin/bash
# Builds services-gtfs.zip: a small, self-contained GTFS feed used by the
# "Services with Bundler" CI job so that job is deterministic and does NOT
# depend on the live Unitrans feed (which drifts and, as of mid-2026, leaves
# ~40% of its stops out of OBA's geospatial index, making bin/validate.sh's
# stops-for-location check fail at random).
#
# Design notes for validate.sh compatibility:
#   * one agency, one route, one trip, seven well-separated stops (~1 km apart)
#     so every stop lands in OBA's geospatial STRtree (stops-for-location).
#   * calendar spans a wide date range so agencies-with-coverage is populated.
#
# Regenerate with:  bash bin/testdata/services/make_services_fixture.sh
set -euo pipefail
OUT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/agency.txt" <<'EOF'
agency_id,agency_name,agency_url,agency_timezone
oba-test,OBA Test Transit,https://example.org,America/Los_Angeles
EOF

# Seven stops strung ~1 km apart along a NE line near Davis, CA. Wide spacing
# keeps each stop distinct in the geospatial index.
cat > "$WORK/stops.txt" <<'EOF'
stop_id,stop_name,stop_lat,stop_lon
S1,First & Main,38.540000,-121.740000
S2,Second & Oak,38.548000,-121.730000
S3,Third & Elm,38.556000,-121.720000
S4,Fourth & Pine,38.564000,-121.710000
S5,Fifth & Cedar,38.572000,-121.700000
S6,Sixth & Birch,38.580000,-121.690000
S7,Seventh & Ash,38.588000,-121.680000
EOF

cat > "$WORK/routes.txt" <<'EOF'
route_id,agency_id,route_short_name,route_long_name,route_type
R1,oba-test,1,Test Line,3
EOF

cat > "$WORK/calendar.txt" <<'EOF'
service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date
WEEK,1,1,1,1,1,1,1,20200101,20401231
EOF

cat > "$WORK/trips.txt" <<'EOF'
route_id,service_id,trip_id
R1,WEEK,T1
EOF

cat > "$WORK/stop_times.txt" <<'EOF'
trip_id,arrival_time,departure_time,stop_id,stop_sequence
T1,08:00:00,08:00:00,S1,1
T1,08:05:00,08:05:00,S2,2
T1,08:10:00,08:10:00,S3,3
T1,08:15:00,08:15:00,S4,4
T1,08:20:00,08:20:00,S5,5
T1,08:25:00,08:25:00,S6,6
T1,08:30:00,08:30:00,S7,7
EOF

(cd "$WORK" && zip -q "$OUT_DIR/services-gtfs.zip" ./*.txt)
echo "wrote $OUT_DIR/services-gtfs.zip"
