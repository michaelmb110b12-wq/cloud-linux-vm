#!/bin/bash
set -Eeuo pipefail

log() {
  printf '[hostless-guac] %s\n' "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

export PATH="/command:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

: "${PG_MAJOR:=17}"
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
: "${GUAC_VER:=1.6.0}"

PG_BIN="/usr/lib/postgresql/${PG_MAJOR}/bin"
SETUIDGID="$(command -v s6-setuidgid || true)"

[ -x "$PG_BIN/initdb" ] || fail "PostgreSQL initdb not found at $PG_BIN/initdb"
[ -x "$PG_BIN/postgres" ] || fail "PostgreSQL server binary not found"
[ -x "$PG_BIN/pg_isready" ] || fail "pg_isready not found"
[ -x "$CATALINA_HOME/bin/catalina.sh" ] || fail "Tomcat catalina.sh not found"
[ -x /usr/local/sbin/guacd ] || fail "guacd not found"
[ -n "$SETUIDGID" ] || fail "s6-setuidgid helper is missing from the image"

# Every mutable path is under Hostless's documented writable /tmp directory.
mkdir -p "$PGDATA" "$PGHOST" "$GUACAMOLE_HOME" "$CATALINA_TMPDIR" \
  "$CATALINA_BASE/logs" "$CATALINA_BASE/temp" "$CATALINA_BASE/work" \
  /tmp/guac-state/tomcat-work /root/.config/freerdp/known_hosts

# Prepare a separate Tomcat runtime base under /tmp. Its webapps directory is
# read-only, so WARs must be deployed directly without unpacking.
if [ ! -d "$CATALINA_BASE/conf" ]; then
  mkdir -p "$CATALINA_BASE"
  cp -a "$CATALINA_HOME/conf" "$CATALINA_BASE/conf"
fi
if [ ! -e "$CATALINA_BASE/webapps" ]; then
  ln -s "$CATALINA_HOME/webapps" "$CATALINA_BASE/webapps"
fi
if grep -q 'unpackWARs="true"' "$CATALINA_BASE/conf/server.xml"; then
  sed -i 's/unpackWARs="true"/unpackWARs="false"/g' "$CATALINA_BASE/conf/server.xml"
fi
if grep -q 'autoDeploy="true"' "$CATALINA_BASE/conf/server.xml"; then
  sed -i 's/autoDeploy="true"/autoDeploy="false"/g' "$CATALINA_BASE/conf/server.xml"
fi

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

# PostgreSQL must run as its own unprivileged service user.
chown -R postgres:postgres "$PGDATA" "$PGHOST"
chmod 0700 "$PGDATA"
chmod 0755 "$PGHOST"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  log "Initializing temporary PostgreSQL data directory"
  "$SETUIDGID" postgres "$PG_BIN/initdb" -D "$PGDATA" --auth-local=trust --auth-host=trust
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
chown postgres:postgres "$PGDATA/pg_hba.conf" "$PGDATA/postgresql.conf"

PG_PID=""
GUACD_PID=""
TOMCAT_PID=""

shutdown() {
  log "Stopping Guacamole services"
  set +e
  [ -n "$TOMCAT_PID" ] && kill -TERM "$TOMCAT_PID" 2>/dev/null
  [ -n "$GUACD_PID" ] && kill -TERM "$GUACD_PID" 2>/dev/null
  [ -n "$PG_PID" ] && kill -TERM "$PG_PID" 2>/dev/null
  [ -n "$TOMCAT_PID" ] && wait "$TOMCAT_PID" 2>/dev/null
  [ -n "$GUACD_PID" ] && wait "$GUACD_PID" 2>/dev/null
  [ -n "$PG_PID" ] && wait "$PG_PID" 2>/dev/null
}
trap shutdown EXIT INT TERM

log "Starting PostgreSQL on loopback"
"$SETUIDGID" postgres "$PG_BIN/postgres" -D "$PGDATA" \
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
