# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains Docker images for running OneBusAway Application Suite v2, a transit data platform. The system consists of three main components:

1. **Bundler Service**: Processes GTFS data and creates transit data bundles
2. **OBA App Service**: Runs the OneBusAway API and transit data federation webapps
3. **Database Service**: MySQL (default) or PostgreSQL for storing application data

## Common Commands

### Building and Running

```bash
# Build the app server
docker compose build oba_app

# Build a bundle with custom GTFS
GTFS_URL=https://example.com/gtfs.zip docker compose up oba_bundler

# Build with default test data (Unitrans)
docker compose up oba_bundler

# Run the OBA server
docker compose up oba_app

# Run validation tests
./bin/validate.sh

# Clean up
docker compose down -v
```

### Testing

```bash
# Run validation script to test API endpoints
./bin/validate.sh

# Build and test Docker images locally
docker compose build
docker compose up
```

## Architecture

### Directory Structure

- `/bundler/`: Docker setup for building transit data bundles from GTFS feeds
  - Uses Maven to fetch OneBusAway dependencies
  - Includes gtfstidy for cleaning/optimizing GTFS data
  - Outputs to `/bundle/` directory

- `/oba/`: Docker setup for the OneBusAway application server
  - Runs on Tomcat 8.5 with Java 11
  - Template-based configuration for database connections
  - Supports GTFS-RT feeds
  - Includes Prometheus JMX exporter for monitoring

- `/bundle/`: Shared volume containing processed transit data
  - Contains serialized Java objects (.obj files)
  - Lucene search indices
  - Processed GTFS data

### Key Technologies

- **Build System**: Maven-based Java project
- **OneBusAway Version**: v2.6.0 (configurable via OBA_VERSION)
- **Runtime**: Tomcat 8.5.100 with JDK 11
- **Databases**: MySQL 8.0 or PostgreSQL 16
- **GTFS Processing**: gtfstidy (Go-based optimizer)
- **Template Engine**: Custom Handlebars renderer (Go)

### Environment Variables

Database configuration:
- `JDBC_URL`, `JDBC_DRIVER`, `JDBC_USER`, `JDBC_PASSWORD`

GTFS configuration:
- `GTFS_URL`: URL to GTFS zip file
- `TZ`: Timezone for the transit agency

GTFS-RT configuration:
- `TRIP_UPDATES_URL`, `VEHICLE_POSITIONS_URL`, `ALERTS_URL`
- `REFRESH_INTERVAL`: Update frequency in seconds
- `AGENCY_ID`: Transit agency identifier
- `FEED_API_KEY`, `FEED_API_VALUE`: Authentication headers

### API Endpoints

When running locally:
- API webapp: http://localhost:8080/
- Example: http://localhost:8080/api/where/agencies-with-coverage.json?key=TEST
- Transit data federation: http://localhost:8080/onebusaway-transit-data-federation-webapp

### Docker Images

Published to Docker Hub:
- `opentransitsoftwarefoundation/onebusaway-bundle-builder`
- `opentransitsoftwarefoundation/onebusaway-api-webapp`

Multi-architecture support: x86_64, ARM64