#!/bin/bash

# The bundle build downloads and parses third-party GTFS data, so it should not
# run as root. When the container starts as root (the default), hand /bundle to
# the unprivileged user and drop privileges before running the command. When the
# container was started with an explicit --user, just run the command.

set -euo pipefail

OBA_USER="${OBA_USER:-oba_user}"
OBA_GROUP="${OBA_GROUP:-oba_group}"

if [ "$(id -u)" = "0" ]; then
    mkdir -p /bundle
    chown -R "$OBA_USER:$OBA_GROUP" /bundle
    exec setpriv --reuid="$OBA_USER" --regid="$OBA_GROUP" --init-groups \
        env HOME="/home/$OBA_USER" "$@"
fi

exec "$@"
