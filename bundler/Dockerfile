ARG OBA_VERSION=2.7.1
# Pinned so image contents are reproducible and an upstream compromise of a
# moving target (@latest) can't silently land in a release. Bump deliberately.
ARG GTFSTIDY_VERSION=v0.0.0-20260823202512-95d4796d9e7c

##############
# Go Builder #
##############

FROM golang:1.26.8-bookworm AS gobuilder

ARG GTFSTIDY_VERSION

# Install gtfstidy - https://github.com/patrickbr/gtfstidy
WORKDIR /src
COPY ./set_goarch.sh .
RUN ./set_goarch.sh
RUN CGO_ENABLED=0 go install github.com/patrickbr/gtfstidy@${GTFSTIDY_VERSION}

#########
# Maven #
#########

FROM tomcat:9.0.122-jdk11-temurin-jammy AS builder
ARG OBA_VERSION
ENV OBA_VERSION=${OBA_VERSION}

RUN apt-get update && apt-get install -y maven

# Start configuring OBA
WORKDIR /oba
COPY ./pom.xml ./pom.xml
COPY ./settings.xml /root/.m2/settings.xml

RUN mkdir libs && \
    mvn org.apache.maven.plugins:maven-dependency-plugin:3.2.0:get \
    --batch-mode \
    -Dartifact=org.onebusaway:onebusaway-transit-data-federation-builder:${OBA_VERSION}:jar:withAllDependencies && \
    cp /root/.m2/repository/org/onebusaway/onebusaway-transit-data-federation-builder/${OBA_VERSION}/onebusaway-transit-data-federation-builder-${OBA_VERSION}-withAllDependencies.jar \
       ./libs/onebusaway-transit-data-federation-builder-withAllDependencies.jar

###########
# Bundler #
###########

# The bundler only needs a JVM, not a servlet container.
FROM eclipse-temurin:11.0.32_9-jre-jammy
ARG OBA_VERSION
ENV OBA_VERSION=${OBA_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends jq unzip wget zip \
    && rm -rf /var/lib/apt/lists/*

# Unprivileged user for the build; see entrypoint.sh.
ARG GID=1000
ARG UID=1000
ARG GROUP=oba_group
ARG USER=oba_user
RUN groupadd -g $GID $GROUP && \
    useradd -d /home/$USER -u $UID -m -s /bin/bash -g $GROUP $USER

# Start configuring OBA
WORKDIR /oba

RUN mkdir -p /oba/libs
COPY --from=gobuilder /go/bin/gtfstidy /usr/local/bin/gtfstidy
COPY --from=builder /oba/libs/onebusaway-transit-data-federation-builder-withAllDependencies.jar ./libs/
COPY ./build_bundle.sh .
COPY ./entrypoint.sh .

ENTRYPOINT ["/oba/entrypoint.sh"]
CMD ["/oba/build_bundle.sh"]

# for debugging
# CMD ["tail", "-f", "/dev/null"]