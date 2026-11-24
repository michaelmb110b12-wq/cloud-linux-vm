#!/bin/bash
set -Eeuo pipefail

log() {
  printf '[hostless-guac] %s\n' "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

export PATH="/opt/instabox-install/.local/bin:/command:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export INSTABOX_API_URL="${INSTABOX_API_URL:-https://api.instabox.sh}"

: "${PG_MAJOR:=17}"
: "${PORT:=8080}"
: "${PGDATA:=/tmp/guac-state/postgres}"
: "${PGHOST:=/tmp/guac-state/run-postgresql}"
: "${PGPORT:=5432}"
: "${POSTGRES_USER:=guacamole}"
: "${POSTGRES_DB:=guacamole_db}"
: "${GUACAMOLE_HOME:=/tmp/guac-state/guacamole}"
: "${CATALINA_HOME:=/usr/local/tomcat}"
: "${CATALINA_BASE:=/tmp/guac-state/tomcat-base}"
: "${CATALINA_TMPDIR:=/tmp/guac-state/tomcat-temp}"
: "${GUACD_LOG_LEVEL:=info}"
: "${HOME:=/tmp/guac-state/home}"
: "${TMPDIR:=/tmp/guac-state/tmp}"
: "${GUAC_VER:=1.6.0}"

PG_BIN="/usr/lib/postgresql/${PG_MAJOR}/bin"

[ -x "$PG_BIN/initdb" ] || fail "PostgreSQL initdb not found at $PG_BIN/initdb"
[ -x "$PG_BIN/postgres" ] || fail "PostgreSQL server binary not found"
[ -x "$PG_BIN/pg_isready" ] || fail "pg_isready not found"
[ -x "$CATALINA_HOME/bin/catalina.sh" ] || fail "Tomcat catalina.sh not found"
[ -x /usr/local/sbin/guacd ] || fail "guacd not found"

# Every mutable path is under Hostless's documented writable /tmp directory.
mkdir -p "$PGDATA" "$PGHOST" "$GUACAMOLE_HOME" "$CATALINA_TMPDIR" \
  "$CATALINA_BASE/logs" "$CATALINA_BASE/temp" "$CATALINA_BASE/work" \
  /tmp/guac-state/tomcat-work "$HOME/.config/freerdp/known_hosts" "$TMPDIR"

# Prepare a separate Tomcat runtime base under /tmp. Its webapps directory is
# read-only, so WARs must be deployed directly without unpacking.
if [ ! -d "$CATALINA_BASE/conf" ]; then
  mkdir -p "$CATALINA_BASE"
  cp -a "$CATALINA_HOME/conf" "$CATALINA_BASE/conf"
fi
# Tomcat's webapp appBase must be writable so Guacamole can be unpacked
# outside the read-only image. Jersey's package scanner cannot scan the
# nested war: URI produced when unpackWARs=false.
if [ -L "$CATALINA_BASE/webapps" ]; then
  rm "$CATALINA_BASE/webapps"
fi
mkdir -p "$CATALINA_BASE/webapps"
[ -f "$CATALINA_HOME/webapps/ROOT.war" ] || fail "Guacamole ROOT.war not found"
rm -rf "$CATALINA_BASE/webapps/ROOT"
cp -f "$CATALINA_HOME/webapps/ROOT.war" "$CATALINA_BASE/webapps/ROOT.war"
if grep -q 'unpackWARs="false"' "$CATALINA_BASE/conf/server.xml"; then
  sed -i 's/unpackWARs="false"/unpackWARs="true"/g' "$CATALINA_BASE/conf/server.xml"
fi
if grep -q 'autoDeploy="true"' "$CATALINA_BASE/conf/server.xml"; then
  sed -i 's/autoDeploy="true"/autoDeploy="false"/g' "$CATALINA_BASE/conf/server.xml"
fi

# Hostless supplies PORT at runtime. Tomcat must listen on that exact port.
[[ "$PORT" =~ ^[0-9]+$ ]] || fail "Hostless PORT must be a numeric TCP port; got: $PORT"
if ! grep -q '<Connector port="' "$CATALINA_BASE/conf/server.xml"; then
  fail "Could not find the HTTP Connector in Tomcat server.xml"
fi
# Bind the public HTTP listener on every interface, not just loopback.
# Hostless's router and TCP readiness probe connect from outside the container.
sed -i "0,/<Connector port=\"[0-9][0-9]*\"/s//<Connector address=\"0.0.0.0\" port=\"$PORT\"/" "$CATALINA_BASE/conf/server.xml"
log "Configured Tomcat HTTP Connector for Hostless PORT=$PORT on 0.0.0.0"
PORT_HEX="$(printf '%04X' "$PORT")"
log "TCP listener entries for port $PORT (hex $PORT_HEX):"
awk -v suffix=":$PORT_HEX" 'NR == 1 { next } toupper($2) ~ (suffix "$") { print }' /proc/net/tcp /proc/net/tcp6 || true

# Hostless exposes container stdout/stderr, not files under the ephemeral
# CATALINA_BASE. Forward Tomcat's localhost webapp errors there so startup
# failures (including filter exceptions) include their real stack traces.
cat >> "$CATALINA_BASE/conf/logging.properties" <<'LOGGING'
java.util.logging.ConsoleHandler.level = ALL
java.util.logging.ConsoleHandler.formatter = org.apache.juli.OneLineFormatter
org.apache.catalina.core.ContainerBase.[Catalina].[localhost].level = INFO
org.apache.catalina.core.ContainerBase.[Catalina].[localhost].handlers = java.util.logging.ConsoleHandler
org.apache.catalina.core.ContainerBase.[Catalina].[localhost].useParentHandlers = false
LOGGING

# Stage Guacamole's supplied configuration and JDBC/QuickConnect extensions.
cp -a /app/guacamole/. "$GUACAMOLE_HOME"/
mkdir -p "$GUACAMOLE_HOME/extensions" "$GUACAMOLE_HOME/extensions-available"
QUICKCONNECT_JAR="$GUACAMOLE_HOME/extensions-available/guacamole-auth-quickconnect-${GUAC_VER}.jar"
[ -f "$QUICKCONNECT_JAR" ] || fail "QuickConnect extension not found: $QUICKCONNECT_JAR"
cp -f "$QUICKCONNECT_JAR" "$GUACAMOLE_HOME/extensions/"

# Point Guacamole at the local PostgreSQL instance and local guacd process.
GUAC_PROPERTIES="$GUACAMOLE_HOME/guacamole.properties"
[ -f "$GUAC_PROPERTIES" ] || fail "guacamole.properties was not copied"
sed -i \
  -e 's/^postgresql-hostname:.*/postgresql-hostname: 127.0.0.1/' \
  -e 's/^postgresql-port:.*/postgresql-port: 5432/' \
  -e 's/^postgresql-username:.*/postgresql-username: guacamole/' \
  -e 's/^postgresql-database:.*/postgresql-database: guacamole_db/' \
  -e 's/^postgresql-password:.*/postgresql-password: /' \
  "$GUAC_PROPERTIES"
if ! grep -q '^guacd-hostname:' "$GUAC_PROPERTIES"; then
  printf '\nguacd-hostname: 127.0.0.1\nguacd-port: 4822\n' >> "$GUAC_PROPERTIES"
else
  sed -i 's/^guacd-hostname:.*/guacd-hostname: 127.0.0.1/' "$GUAC_PROPERTIES"
fi

# The container itself runs as the unprivileged postgres user; no chown is needed.
chmod 0700 "$PGDATA"
chmod 0755 "$PGHOST"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  log "Initializing temporary PostgreSQL data directory"
  "$PG_BIN/initdb" -D "$PGDATA" --auth-local=trust --auth-host=trust
fi

# PostgreSQL is reachable only over loopback; trust authentication is confined
# to this single container and no database port is exposed by Hostless.
cat > "$PGDATA/pg_hba.conf" <<'PGHBA'
local all all trust
host all all 127.0.0.1/32 trust
host all all ::1/128 trust
PGHBA

cat >> "$PGDATA/postgresql.conf" <<PGCONF

listen_addresses = '127.0.0.1'
port = ${PGPORT}
unix_socket_directories = '${PGHOST}'
logging_collector = off
PGCONF

PG_PID=""
GUACD_PID=""
TOMCAT_PID=""
INSTABOX_PID=""

shutdown() {
  log "Stopping Guacamole services"
  set +e
  [ -n "$INSTABOX_PID" ] && kill -TERM "$INSTABOX_PID" 2>/dev/null
  [ -n "$INSTABOX_PID" ] && wait "$INSTABOX_PID" 2>/dev/null
  [ -n "$TOMCAT_LOG_PID" ] && kill -TERM "$TOMCAT_LOG_PID" 2>/dev/null
  [ -n "$TOMCAT_PID" ] && kill -TERM "$TOMCAT_PID" 2>/dev/null
  [ -n "$GUACD_PID" ] && kill -TERM "$GUACD_PID" 2>/dev/null
  [ -n "$PG_PID" ] && kill -TERM "$PG_PID" 2>/dev/null
  [ -n "$TOMCAT_PID" ] && wait "$TOMCAT_PID" 2>/dev/null
  [ -n "$GUACD_PID" ] && wait "$GUACD_PID" 2>/dev/null
  [ -n "$PG_PID" ] && wait "$PG_PID" 2>/dev/null
}
trap shutdown EXIT INT TERM

export HOME TMPDIR
log "Starting PostgreSQL as the unprivileged container user on loopback"
"$PG_BIN/postgres" -D "$PGDATA" \
  -c "listen_addresses=127.0.0.1" \
  -c "unix_socket_directories=$PGHOST" \
  -c "port=$PGPORT" &
PG_PID=$!

PG_READY=0
for attempt in $(seq 1 60); do
  if "$PG_BIN/pg_isready" -h "$PGHOST" -p "$PGPORT" -U postgres >/dev/null 2>&1; then
    PG_READY=1
    break
  fi
  if ! kill -0 "$PG_PID" 2>/dev/null; then
    fail "PostgreSQL exited before becoming ready"
  fi
  sleep 1
done
[ "$PG_READY" -eq 1 ] || fail "PostgreSQL did not become ready within 60 seconds"

log "Creating Guacamole database and schema if needed"
if ! "$PG_BIN/psql" -h "$PGHOST" -p "$PGPORT" -U postgres -d postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'" | grep -q '^1$'; then
  "$PG_BIN/createuser" -h "$PGHOST" -p "$PGPORT" -U postgres "$POSTGRES_USER"
  "$PG_BIN/createdb" -h "$PGHOST" -p "$PGPORT" -U postgres -O "$POSTGRES_USER" "$POSTGRES_DB"
  cat "$GUACAMOLE_HOME"/schema/*.sql | \
    "$PG_BIN/psql" -h "$PGHOST" -p "$PGPORT" -U "$POSTGRES_USER" \
      -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -f -
fi

log "Starting guacd"
 /usr/local/sbin/guacd -b 127.0.0.1 -L "$GUACD_LOG_LEVEL" -f &
GUACD_PID=$!

# Keep the InstaBox VM and its VNC tunnel available on this same app's
# localhost so the saved Guacamole connection can continue using 127.0.0.1:15901.
if [ -n "${INSTABOX_API_KEY:-}" ]; then
  log "Starting InstaBox VM/tunnel supervisor in the background"
  /usr/local/bin/instabox-tunnel-supervisor &
  INSTABOX_PID=$!
else
  log "INSTABOX_API_KEY is not configured; skipping automatic InstaBox tunnel"
fi

# Tomcat writes the detailed filter/listener startup exception to
# localhost.YYYY-MM-DD.log under CATALINA_BASE/logs. Hostless only displays
# container stdout/stderr, so forward that file to stdout for diagnosis.
TOMCAT_LOG_PID=""
(
  set +e
  while true; do
    shopt -s nullglob
    log_files=("$CATALINA_BASE"/logs/localhost*.log)
    if [ "${#log_files[@]}" -gt 0 ]; then
      exec tail -n +1 -F "${log_files[@]}"
    fi
    sleep 1
  done
) &
TOMCAT_LOG_PID=$!

log "Starting Tomcat / Guacamole on port 8080"
export CATALINA_HOME CATALINA_BASE CATALINA_TMPDIR GUACAMOLE_HOME
"$CATALINA_HOME/bin/catalina.sh" run &
TOMCAT_PID=$!

log "Guacamole services started; waiting for a service to exit"
set +e
wait -n "$PG_PID" "$GUACD_PID" "$TOMCAT_PID"
STATUS=$?
set -e
log "A Guacamole service exited (status $STATUS); stopping the container"
exit 1
