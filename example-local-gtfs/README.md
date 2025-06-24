# Example: Using Local GTFS Files with OneBusAway Docker

This example demonstrates how to build OneBusAway bundles using local GTFS files instead of downloading them from a URL.

## Prerequisites

1. A local GTFS zip file
2. Docker and Docker Compose installed on your system

## Usage

### Option 1: Using Docker Compose (Recommended)

#### Step 1: Copy your GTFS file

Copy your GTFS zip file to this directory:

```bash
cp /path/to/your/gtfs.zip ./sta-gtfs-may-2025.zip
```

Or update the Dockerfile and docker-compose.yml to use your filename.

#### Step 2: Run the full stack

```bash
# build the bundle
docker compose up oba_bundler

# Then start the app
docker compose up oba_app
```

This will:
1. Build a bundle from your local GTFS file
2. Start the database (PostgreSQL or MySQL)
3. Start the OneBusAway API server

Access the API at: http://localhost:8080/onebusaway-api-webapp/api/where/agencies-with-coverage.json?key=test

### Option 2: Manual Docker Build

#### Step 1: Build the base OBA image

First, build the base OneBusAway image from the parent directory:

```bash
cd ..
docker build -t oba-base:latest -f oba/Dockerfile .
```

#### Step 2: Copy your GTFS file

Copy your GTFS zip file to this directory and rename it, or update the Dockerfile to use your filename:

```bash
cp /path/to/your/gtfs.zip ./your-gtfs-file.zip
```

#### Step 3: Update the Dockerfile

Edit the Dockerfile to use your GTFS filename:
- Change `your-gtfs-file.zip` to match your actual filename in both the COPY and ENV lines

#### Step 4: Build the image with your local GTFS

```bash
docker build -t oba-local-gtfs:latest .
```

#### Step 5: Run the bundle builder

```bash
docker run --rm -v $(pwd)/../bundle:/bundle oba-local-gtfs:latest
```

This will:
- Use your local GTFS file (no download required)
- Run gtfstidy to optimize the GTFS data
- Build the OneBusAway bundle
- Output the bundle to the shared volume

## Environment Variables

You can override these environment variables in the Dockerfile or docker-compose.yml:

- `GTFS_ZIP_FILENAME`: The name of your GTFS file (required when not using GTFS_URL)
- `TZ`: Timezone for the transit agency (default: America/New_York)
- `GTFS_TIDY_ARGS`: Arguments for gtfstidy optimization (default: OscRCSmeD)
- `OBA_VERSION`: OneBusAway version (inherited from base image)

## Docker Compose Services

- `oba_database`: MySQL database (optional)
- `oba_database_pg`: PostgreSQL database (default)
- `oba_bundler`: Builds transit data bundle from local GTFS
- `oba_app`: OneBusAway API server

## How it Works

1. **Build Time**: Your GTFS zip file is copied into the Docker image at `/tmp/`
2. **Runtime**: The `docker-entrypoint.sh` script:
   - Finds your GTFS file in `/tmp/`
   - Copies it to `/bundle/gtfs.zip` (after the volume is mounted)
   - Executes the main command (build_bundle.sh or supervisord)

This approach is needed because Docker volume mounts happen after the image is built but before commands run. By copying to `/tmp/` first, we ensure the file isn't hidden by the volume mount.

## Notes

- Place any GTFS zip file in this directory - it will be automatically detected
- Make sure not to set GTFS_URL when using GTFS_ZIP_FILENAME
- The bundle output will be in the ../bundle directory
- The docker-compose file uses PostgreSQL by default; comment it out and uncomment MySQL if preferred
- You can override the GTFS filename by setting `GTFS_ZIP_FILENAME` in docker-compose.yml