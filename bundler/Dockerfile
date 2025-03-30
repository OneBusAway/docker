ARG OBA_VERSION=2.5.13-otsf

##############
# Go Builder #
##############

FROM golang:1.24.1-bookworm AS gobuilder

# Install gtfstidy - https://github.com/patrickbr/gtfstidy
WORKDIR /src
COPY ./set_goarch.sh .
RUN ./set_goarch.sh
RUN CGO_ENABLED=0 go install github.com/patrickbr/gtfstidy@latest

#########
# Maven #
#########

FROM tomcat:8.5.100-jdk11-temurin AS builder
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

FROM tomcat:8.5.100-jdk11-temurin
ARG OBA_VERSION
ENV OBA_VERSION=${OBA_VERSION}

RUN apt-get update && apt-get install -y unzip zip

# Start configuring OBA
WORKDIR /oba

RUN mkdir -p /oba/libs
COPY --from=gobuilder /go/bin/gtfstidy /usr/local/bin/gtfstidy
COPY --from=builder /oba/libs/onebusaway-transit-data-federation-builder-withAllDependencies.jar ./libs/
COPY ./build_bundle.sh .

CMD /oba/build_bundle.sh

# for debugging
# CMD ["tail", "-f", "/dev/null"]