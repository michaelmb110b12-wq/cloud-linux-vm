#!/usr/bin/with-contenv sh
set -eu

PG_CONF="${PGDATA}/postgresql.conf"
if [ ! -f "$PG_CONF" ]; then
  echo "PostgreSQL configuration not found at $PG_CONF" >&2
  exit 1
fi

# Hostless only guarantees writable temporary paths. Keep the local PostgreSQL
# Unix socket in /tmp as well, rather than the image's default /var/run path.
echo "unix_socket_directories = '/tmp/guac-state/run-postgresql'" >> "$PG_CONF"
