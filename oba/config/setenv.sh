# Sourced by catalina.sh after the deployment's own JAVA_OPTS/CATALINA_OPTS are
# read, so these flags are appended rather than replaced by an operator-supplied
# value (e.g. CATALINA_OPTS=-Xmx1g or JAVA_OPTS=-Xmx1g).
#
# GTFS-RT and alerts fetch timeouts (ms). OBA runs every GTFS-RT source on one
# shared single-thread scheduler and leaves URLConnection timeouts unset
# (infinite) unless these system properties exist, so one upstream socket that
# never answers freezes realtime for every agency on the server until Tomcat
# restarts. The read timeout bounds each socket read, not the whole download.
# Override with GTFS_CONNECT_TIMEOUT_MS / GTFS_READ_TIMEOUT_MS (positive
# integers up to 9 digits; anything else falls back to the default, since OBA would throw
# NumberFormatException on every fetch and catalina.sh evals CATALINA_OPTS).

_oba_ms() {
    case "$1" in
        # >9 digits could overflow Java's int and throw in Integer.parseInt.
        ''|*[!0-9]*|0*|??????????*) echo "$2" ;;
        *) echo "$1" ;;
    esac
}

CATALINA_OPTS="$CATALINA_OPTS -Dgtfs.connect_timeout=$(_oba_ms "$GTFS_CONNECT_TIMEOUT_MS" 10000) -Dgtfs.read_timeout=$(_oba_ms "$GTFS_READ_TIMEOUT_MS" 30000)"
unset -f _oba_ms
