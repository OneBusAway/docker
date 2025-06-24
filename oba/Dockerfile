ARG OBA_VERSION=2.6.0
ARG POSTGRESQL_CONNECTOR_VERSION=42.7.4
ARG MYSQL_CONNECTOR_VERSION=8.4.0

##############
# Go Builder #
##############

FROM golang:1.24.4-bookworm AS gobuilder

# Install gtfstidy - https://github.com/patrickbr/gtfstidy
WORKDIR /src
COPY ./set_goarch.sh .
RUN ./set_goarch.sh
RUN CGO_ENABLED=0 go install github.com/patrickbr/gtfstidy@latest

# Build the template renderer, which is called hbs_renderer
WORKDIR /oba/template_renderer
COPY ./config/template_renderer .
RUN CGO_ENABLED=0 go build -o hbs_renderer

################
# Java Builder #
################

FROM tomcat:8.5.100-jdk11-temurin AS builder

ARG OBA_VERSION
ENV OBA_VERSION=${OBA_VERSION}

ARG POSTGRESQL_CONNECTOR_VERSION
ENV POSTGRESQL_CONNECTOR_VERSION=${POSTGRESQL_CONNECTOR_VERSION}

ARG MYSQL_CONNECTOR_VERSION
ENV MYSQL_CONNECTOR_VERSION=${MYSQL_CONNECTOR_VERSION}

RUN apt-get update && apt-get install -y maven

# Start configuring OBA
WORKDIR /oba/libs
COPY ./config/pom.xml ./pom.xml
COPY ./config/settings.xml /root/.m2/settings.xml

# Download and install dependencies - this must be run here because
# secure args are not available in the next stage
RUN mvn -f pom.xml \
    install \
    --batch-mode \
    -DskipTests

COPY ./retrieve_maven_artifacts.sh .
RUN chmod +x ./retrieve_maven_artifacts.sh
RUN ./retrieve_maven_artifacts.sh

##########
# Server #
##########

FROM tomcat:8.5.100-jdk11-temurin AS server

ARG GTFS_TIDY_ARGS
ENV GTFS_TIDY_ARGS=${GTFS_TIDY_ARGS}
ARG OBA_VERSION=2.6.0

ARG POSTGRESQL_CONNECTOR_VERSION
ENV POSTGRESQL_CONNECTOR_VERSION=${POSTGRESQL_CONNECTOR_VERSION}

ARG MYSQL_CONNECTOR_VERSION
ENV MYSQL_CONNECTOR_VERSION=${MYSQL_CONNECTOR_VERSION}

ARG OBA_VERSION
ENV OBA_VERSION=${OBA_VERSION}

ENV CATALINA_HOME=/usr/local/tomcat
ENV TZ=America/New_York

ARG GID=1000
ARG UID=1000
ARG GROUP=oba_group
ARG USER=oba_user

RUN apt-get update && apt-get install -y \
    jq \
    python3-pip \
    supervisor \
    tzdata \
    unzip \
    wget \
    zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN pip install supervisord-dependent-startup
RUN apt remove -y python3-pip

COPY --from=gobuilder /oba/template_renderer/hbs_renderer /usr/local/bin/hbs_renderer
COPY --from=gobuilder /go/bin/gtfstidy /usr/local/bin/gtfstidy

# Set the configured time zone
RUN ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && dpkg-reconfigure -f noninteractive tzdata

# Create a non-root user and assign them ownership of tomcat
RUN groupadd -g $GID $GROUP && \
    useradd -d /home/$USER -u $UID -m -s /bin/bash -g $GROUP $USER && \
    chown -R $USER:$GROUP $CATALINA_HOME && \
    mkdir -p /var/log/tomcat8 && \
    chown -R $USER:$GROUP /var/log/tomcat8

##########
# Configure OBA Bundle Builder
##########

WORKDIR /oba/libs
COPY --from=builder \
    --chown=oba_user:oba_group \
    /oba/libs/onebusaway-transit-data-federation-builder-withAllDependencies.jar .

##########
# Copy over config files
##########

WORKDIR /oba/config

COPY ./config/context.xml.hbs .
COPY ./config/onebusaway-api-webapp-data-sources.xml.hbs .
COPY ./config/onebusaway-transit-data-federation-webapp-data-sources.xml.hbs .

##########
# Configure OBA Server
##########

WORKDIR $CATALINA_HOME/webapps

##########
# Configure onebusaway-api-webapp
##########

COPY --from=builder \
    --chown=oba_user:oba_group \
    /oba/libs/onebusaway-api-webapp.war .

RUN mkdir ROOT && \
    cd ROOT && \
    jar xvf ../onebusaway-api-webapp.war && \
    rm ../onebusaway-api-webapp.war

COPY --from=builder \
    --chown=oba_user:oba_group \
    /oba/libs/mysql-connector-j.jar \
    $CATALINA_HOME/webapps/ROOT/WEB-INF/lib/

COPY --from=builder \
    --chown=oba_user:oba_group \
    /oba/libs/postgresql.jar \
    $CATALINA_HOME/webapps/ROOT/WEB-INF/lib/

RUN mkdir -p /opt/oba/logs
RUN chown -R oba_user:oba_group /opt/oba/logs
RUN chmod 755 /opt/oba/logs

##########
# Configure onebusaway-transit-data-federation-webapp
##########

COPY --from=builder \
    --chown=oba_user:oba_group \
    /oba/libs/onebusaway-transit-data-federation-webapp.war .

RUN mkdir onebusaway-transit-data-federation-webapp && \
    cd onebusaway-transit-data-federation-webapp && \
    jar xvf ../onebusaway-transit-data-federation-webapp.war && \
    rm ../onebusaway-transit-data-federation-webapp.war

COPY --from=builder \
    --chown=oba_user:oba_group \
    /oba/libs/mysql-connector-j.jar \
    onebusaway-transit-data-federation-webapp/WEB-INF/lib/

COPY --from=builder \
    --chown=oba_user:oba_group \
    /oba/libs/postgresql.jar \
    onebusaway-transit-data-federation-webapp/WEB-INF/lib/

##########
# Clean up
##########

RUN apt-get autoremove -y && apt-get clean
RUN rm -rf /oba/webapps

# Jmx exporter

RUN mkdir -p /app && \
    wget -O /app/jmx_prometheus_javaagent.jar https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.19.0/jmx_prometheus_javaagent-0.19.0.jar
COPY ./jmx_exporter_config.yml /app/jmx_exporter_config.yml

# Set JVM options to include JMX exporter
ENV JAVA_OPTS="-javaagent:/app/jmx_prometheus_javaagent.jar=1234:/app/jmx_exporter_config.yml"

##########
# Bootstrapper and Supervisor
##########

COPY bootstrap.sh /oba/bootstrap.sh
COPY build_bundle.sh /oba/build_bundle.sh
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# CMD ["tail", "-f", "/dev/null"]
CMD ["supervisord", "-n"]
