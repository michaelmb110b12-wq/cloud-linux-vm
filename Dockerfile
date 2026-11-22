# Self-contained Guacamole image: web client + guacd + PostgreSQL.
# Hostless uses a read-only root filesystem and provides writable temporary /tmp.
# Keep both s6-overlay runtime files and Guacamole/PostgreSQL state under /tmp.
FROM abesnier/guacamole:1.6.0-pg17

# Redirect bundled Guacamole/PostgreSQL state away from the read-only /config path.
RUN sed -i \
      -e 's#/config#/tmp/guac-state#g' \
      -e 's#/var/run/postgresql#/tmp/guac-state/run-postgresql#g' \
      /etc/cont-init.d/*.sh \
      /etc/services.d/guacamole/run \
      /etc/services.d/postgres/run \
    && sed -i '2i mkdir -p /tmp/guac-state' /etc/cont-init.d/30-defaults.sh

# s6-overlay read-only-root mode still needs writable /run.
# Hostless only guarantees writable /tmp, so make /run resolve there.
RUN rm -rf /run /var/run \
    && ln -s /tmp/run /run \
    && ln -s /run /var/run

COPY hostless/45-postgres-socket.sh /etc/cont-init.d/45-postgres-socket.sh
COPY hostless/entrypoint.sh /usr/local/bin/hostless-entrypoint
RUN chmod +x /etc/cont-init.d/45-postgres-socket.sh /usr/local/bin/hostless-entrypoint

# QuickConnect allows ad-hoc RDP URIs on the Guacamole home page.
ENV GUACAMOLE_HOME=/tmp/guac-state/guacamole \
    PGDATA=/tmp/guac-state/postgres \
    PGHOST=/tmp/guac-state/run-postgresql \
    EXTENSIONS=auth-quickconnect \
    S6_READ_ONLY_ROOT=1

WORKDIR /tmp/guac-state
EXPOSE 8080

# Create writable /run before handing control to the s6 init system.
ENTRYPOINT ["/usr/local/bin/hostless-entrypoint"]
