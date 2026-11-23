# Apache Guacamole + guacd + PostgreSQL in one image.
# Hostless uses a read-only root filesystem; runtime data is placed in /tmp.
FROM abesnier/guacamole:1.6.0-pg17

COPY hostless/entrypoint.sh /usr/local/bin/hostless-entrypoint
RUN chmod 0755 /usr/local/bin/hostless-entrypoint

ENV GUACAMOLE_HOME=/tmp/guac-state/guacamole
ENV PGDATA=/tmp/guac-state/postgres
ENV PGHOST=/tmp/guac-state/run-postgresql
ENV PGPORT=5432
ENV POSTGRES_USER=guacamole
ENV POSTGRES_DB=guacamole_db
ENV CATALINA_BASE=/tmp/guac-state/tomcat-base
ENV CATALINA_TMPDIR=/tmp/guac-state/tomcat-temp
ENV EXTENSIONS=auth-quickconnect
ENV HOME=/tmp/guac-state/home
ENV TMPDIR=/tmp/guac-state/tmp

# Run as postgres so it creates its own PostgreSQL data directory.
# Hostless does not permit chown in the writable temporary filesystem.
USER postgres

WORKDIR /
EXPOSE 8080

# Bypass the base image's s6-overlay entrypoint. Hostless mounts /var/run
# read-only, which prevents s6 preinit from replacing it with a symlink.
ENTRYPOINT ["/usr/local/bin/hostless-entrypoint"]
