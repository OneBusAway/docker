# Multiple GTFS-RT Feeds Example

This example runs a single OneBusAway server that serves **two transit agencies'
realtime data at once** — King County Metro and Pierce Transit — using the
`GTFS_RT_FEEDS` environment variable.

OneBusAway supports many `GtfsRealtimeSource` beans (one per realtime feed).
`GTFS_RT_FEEDS` exposes that: it takes a JSON array of feed
objects and renders one bean per feed. It supersedes the legacy single-feed
variables (`TRIP_UPDATES_URL`, `VEHICLE_POSITIONS_URL`, `ALERTS_URL`,
`AGENCY_ID`, …), which still work for a single feed when `GTFS_RT_FEEDS` is unset.

## What's configured

| Agency | `agency_id` | Static GTFS | Realtime |
|---|---|---|---|
| King County Metro | `1` | consolidated feed (below) | raw GTFS-RT protobufs from `kcm-alerts-realtime-prod` |
| Pierce Transit | `3` | consolidated feed (below) | relayed through the Puget Sound OneBusAway GTFS-RT endpoints |

**Static data** comes from the consolidated Puget Sound GTFS feed
(`https://gtfs.sound.obaweb.org/prod/gtfs_puget_sound_consolidated.zip`), which
already contains both agencies (and several others). Because it's a single zip,
the normal single-feed bundle builder handles it without any changes.

**Realtime data** is configured with two feeds in `GTFS_RT_FEEDS`. Each feed's
`agencyIds` tells OneBusAway which bundle agency the feed's entities belong to,
so the two protobuf streams line up with agencies `1` and `3` in the bundle:

```json
[
  {
    "tripUpdatesUrl": "https://s3.amazonaws.com/kcm-alerts-realtime-prod/tripupdates.pb",
    "vehiclePositionsUrl": "https://s3.amazonaws.com/kcm-alerts-realtime-prod/vehiclepositions.pb",
    "alertsUrl": "https://s3.amazonaws.com/kcm-alerts-realtime-prod/alerts.pb",
    "refreshInterval": "30",
    "agencyIds": ["1"]
  },
  {
    "tripUpdatesUrl": "https://api.pugetsound.onebusaway.org/api/gtfs_realtime/trip-updates-for-agency/3.pb?key=org.onebusaway.iphone",
    "vehiclePositionsUrl": "https://api.pugetsound.onebusaway.org/api/gtfs_realtime/vehicle-positions-for-agency/3.pb?key=org.onebusaway.iphone",
    "alertsUrl": "https://api.pugetsound.onebusaway.org/api/gtfs_realtime/alerts-for-agency/3.pb?key=org.onebusaway.iphone",
    "refreshInterval": "30",
    "agencyIds": ["3"]
  }
]
```

> **Note:** `oba_app` is built from this repository's `../../oba` directory, not
> the published `opentransitsoftwarefoundation/onebusaway-api-webapp:2.7.1-latest`
> image, because `GTFS_RT_FEEDS` support is not in a published release yet. Once a
> 2.7.1 image that understands `GTFS_RT_FEEDS` is published, an immutable
> deployment can bake these env vars into a `Dockerfile` that is `FROM` that
> image instead — see [`../immutable`](../immutable) for that pattern.

## Running it

From this directory:

```bash
docker compose up -d --build
```

This:

1. Runs `oba_bundler` once to build the consolidated bundle into a shared volume
   (this downloads ~38 MB of GTFS and takes a few minutes).
2. Starts PostgreSQL.
3. Starts `oba_app` after the bundle finishes, configured with both realtime feeds.

Watch the bundle build and app startup:

```bash
docker compose logs -f oba_bundler   # bundle build
docker compose logs -f oba_app       # config render + Tomcat startup
```

The API is available at <http://localhost:8080> once `oba_app` is up.

## Validating

Run the repository's validation script (from the repo root) against the running server:

```bash
./bin/validate.sh
```

Then confirm **realtime** is flowing for **both** agencies. The most direct
check is live vehicle positions — each count should be non-zero during service
hours, and it proves each feed's entities mapped onto the right bundle agency:

```bash
# King County Metro (agency 1) — live vehicles from its realtime feed
curl -s "http://localhost:8080/api/where/vehicles-for-agency/1.json?key=test" | jq '.data.list | length'

# Pierce Transit (agency 3) — live vehicles from its realtime feed
curl -s "http://localhost:8080/api/where/vehicles-for-agency/3.json?key=test" | jq '.data.list | length'
```

To see the realtime status of a specific trip, pull an active trip from a
vehicle and inspect its status — look for `"predicted": true`:

```bash
TRIP=$(curl -s "http://localhost:8080/api/where/vehicles-for-agency/1.json?key=test" | jq -r '.data.list[0].tripId')
curl -s "http://localhost:8080/api/where/trip-details/$TRIP.json?key=test" \
  | jq '.data.entry.status | {predicted, scheduleDeviation, vehicleId, lastUpdateTime}'
```

## Tearing down

```bash
docker compose down -v   # -v also removes the bundle and database volumes
```
