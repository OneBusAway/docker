# Example Dockerfile for using local GTFS files with OneBusAway
# This builds on top of the main OBA Docker image

# First, build the base OBA image if not already built:
# docker build -t oba-base:latest -f ../oba/Dockerfile ../oba

FROM oba-base:latest

# Copy your local GTFS file into the container
# We copy to /tmp first because /bundle gets mounted over
COPY *.zip /tmp/

# Set the GTFS_ZIP_FILENAME environment variable
# This tells the build_bundle.sh script to use the local file instead of downloading
ENV GTFS_ZIP_FILENAME=gtfs.zip

# Copy the entrypoint script
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

# Optional: Override other environment variables if needed
# ENV TZ=America/Los_Angeles
ENV GTFS_TIDY_ARGS=OscRCSmeD

# The entrypoint and other configurations are inherited from the base image