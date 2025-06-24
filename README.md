# OneBusAway Docker Images

<a href="https://hub.docker.com/u/opentransitsoftwarefoundation"><img alt="Official Docker images" src="https://img.shields.io/badge/Docker_Hub-images-green?logo=docker"></a> <img alt="GitHub Actions Workflow Status" src="https://img.shields.io/github/actions/workflow/status/onebusaway/onebusaway-docker/test.yaml?branch=main">

This repository contains scripts and configuration for building version 2 of the
[OneBusAway Application Suite](https://github.com/OneBusAway/onebusaway-application-modules)
for use with [Docker](https://www.docker.com/).

## Deploying to a cloud provider?

Check out our [onebusaway-deployment](https://github.com/oneBusAway/onebusaway-deployment) repository, which features OpenTofu (Terraform) IaC configuration for deploying OneBusAway to AWS, Azure, Google Cloud Platform, Render, Kubernetes, and other platforms.

### Deploy to Render

[Render](https://www.render.com) is an easy-to-use Platform-as-a-Service (PaaS) provider. You can host OneBusAway on Render by either manually configuring it or by clicking the button below.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/oneBusAway/onebusaway-docker/)

### Running in Kubernetes

[Learn more about running OBA in Kubernetes in the dedicated README](k8s-readme.md).

## Running locally

To build bundles and run the webapp server with your own GTFS feed, use the [Docker Compose](https://docs.docker.com/compose/) services in this repository.

### Building the app server

```bash
docker compose build oba_app
```

### Building bundles

To build a bundle, use the `oba_bundler` service:

```bash
GTFS_URL=https://www.soundtransit.org/GTFS-rail/40_gtfs.zip \
docker compose up oba_bundler
```

This process will create all necessary bundle files and metadata, and all will be accessible in your local repo's `./bundle` directory.

When the GTFS_URL is unspecified, `oba_bundler` will download and use the GTFS data for Davis, CA's Unitrans service. This can be used with the `bin/validate.sh` script to verify that the stack is working correctly.

```bash
docker compose up oba_bundler
```

### Running the OneBusAway server

Once you have built an OBA bundle inside `./bundle`, you can run the OBA server and make it accessible on your host machine with:

```bash
docker compose up oba_app
```

You will then have two web apps available:

* onebusaway-api-webapp, hosted at http://localhost:8080/
  * Example API call: http://localhost:8080/api/where/agencies-with-coverage.json?key=TEST
* onebusaway-transit-data-federation-webapp, which does the heavy lifting of exposing the transit data bundle to other services: http://localhost:8080/onebusaway-transit-data-federation-webapp

When done using this web server, you can use the shell-standard `^C` to exit out and turn it off. If issues persist across runs, you can try using `docker compose down -v` and then `docker compose up oba_app` to refresh the Docker containers and services.

### Using local GTFS files

If you have a local GTFS file instead of downloading from a URL, see the [`example-local-gtfs/`](example-local-gtfs/) directory for a complete example that demonstrates how to build bundles using local GTFS files.

### Inspecting the database

The Docker Compose database service should remain up after a call of `docker compose up oba_app`. Otherwise, you can always invoke it using `docker compose up oba_database`.

A database port is open to your host machine, so you can connect to it programmatically using `mysql`:

```bash
mysql -u oba_user -p -h localhost:3306
```

## Deployment

### Published Images

You can find the latest published Docker images on Docker Hub:

* [onebusaway-bundle-builder](https://hub.docker.com/r/opentransitsoftwarefoundation/onebusaway-bundle-builder) - This image is built from the `bundler` directory and contains the functionality needed to create a transit data bundle from a GTFS feed.
* [onebusaway-api-webapp](https://hub.docker.com/r/opentransitsoftwarefoundation/onebusaway-api-webapp) - This image is built from the `oba` directory and contains the functionality needed to run the OBA API webapp.

### Deployment Parameters

* Database
  * `JDBC_URL` - The JDBC connection URL for your MySQL or PostgreSQL database.
  * `JDBC_DRIVER` - The JDBC driver class name: `com.mysql.cj.jdbc.Driver` or `org.postgresql.Driver`
  * `JDBC_USER` - The username for your database.
  * `JDBC_PASSWORD` - The password for your database.
* GTFS (Optional, required only when using `oba_app` independently)
  * `GTFS_URL` - The URL to the GTFS feed you want to use.
* GTFS-RT Support (Optional)
  * `TZ` - The timezone for the server. Ensure that the server's timezone matches the timezone specified in your static GTFS `agency.txt` file. The timezone format is the IANA standard, and [a full list of timezones can be found on Wikipedia](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List).
  * `ALERTS_URL` - Service Alerts URL for GTFS-RT.
  * `TRIP_UPDATES_URL` - Trip Updates URL for GTFS-RT.
  * `VEHICLE_POSITIONS_URL` - Vehicle Positions URL for GTFS-RT.
  * `REFRESH_INTERVAL` - Refresh interval in seconds. Usually 10-30.
  * `AGENCY_ID` - Your GTFS-RT agency ID. Ostensibly the same as your GTFS agency ID.
  * Authentication (Optional)
    * Example: Specifying `FEED_API_KEY` = `X-API-KEY` and `FEED_API_VALUE` = `12345` will result in `X-API-KEY: 12345` being passed on every call to your GTFS-RT URLs.
    * `FEED_API_KEY` - If your GTFS-RT API requires you to pass an authentication header, you can represent the key portion of it by specifying this value.
    * `FEED_API_VALUE` - If your GTFS-RT API requires you to pass an authentication header, you can represent the value portion of it by specifying this value.



The `GTFS-RT` related variables will be handled by the `oba/bootstrap.sh` script, which will set the config files for the OBA API webapp. If you want to use your own config files, you could set `USER_CONFIGURED=1` in the `oba_app` service in `docker-compose.yml` to skip `bootstrap.sh` and write your config file in the container.
```yaml
  oba_app:
    container_name: oba_app
    depends_on:
      - oba_database
    build:
      context: ./oba
    environment:
      # database configs are read from environment variables
      - JDBC_URL=jdbc:mysql://oba_database:3306/oba_database
      - JDBC_USER=oba_user
      - JDBC_PASSWORD=oba_password
      # change this to your GTFS url
      - GTFS_URL=https://unitrans.ucdavis.edu/media/gtfs/Unitrans_GTFS.zip
      # skip bootstrap.sh and use user-configured config files
      - USER_CONFIGURED=1
```
