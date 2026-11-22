# Self-contained Guacamole image: web client + guacd + PostgreSQL.
# Hostless has a read-only root filesystem; use its temporary /tmp area instead
# of a paid persistent disk. Database and account changes reset on every restart.
FROM abesnier/guacamole:1.6.0-pg17

# Redirect all bundled image runtime state from /config to Hostless-writable /tmp.
RUN sed -i \
      -e 's#/config#/tmp/guac-state#g' \
      -e 's#/var/run/postgresql#/tmp/guac-state/run-postgresql#g' \
      /etc/cont-init.d/*.sh \
      /etc/services.d/guacamole/run \
      /etc/services.d/postgres/run \
    && sed -i '2i mkdir -p /tmp/guac-state' /etc/cont-init.d/30-defaults.sh

# Configure PostgreSQL to use a writable Unix socket directory under /tmp.
COPY hostless/45-postgres-socket.sh /etc/cont-init.d/45-postgres-socket.sh
RUN chmod +x /etc/cont-init.d/45-postgres-socket.sh

# QuickConnect lets an authenticated user enter an RDP URI without saving a profile.
ENV GUACAMOLE_HOME=/tmp/guac-state/guacamole \
    PGDATA=/tmp/guac-state/postgres \
    PGHOST=/tmp/guac-state/run-postgresql \
    EXTENSIONS=auth-quickconnect

WORKDIR /tmp/guac-state
EXPOSE 8080
