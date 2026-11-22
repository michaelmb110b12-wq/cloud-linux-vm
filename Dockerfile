# Apache Guacamole + guacd + PostgreSQL in one image.
# Hostless enforces a read-only root filesystem; runtime state stays in /tmp.
FROM abesnier/guacamole:1.6.0-pg17

COPY hostless/entrypoint.sh /usr/local/bin/hostless-entrypoint
RUN chmod 0755 /usr/local/bin/hostless-entrypoint

ENV GUACAMOLE_HOME=/tmp/guac-state/guacamole \
    PGDATA=/tmp/guac-state/postgres \
    PGHOST=/tmp/guac-state/run-postgresql \
    PGPORT=5432 \
    POSTGRES_USER=guacamole \
    POSTGRES_DB=guacamole_db \
    CATALINA_BASE=/tmp/guac-state/tomcat-base \
    CATALINA_TMPDIR=/tmp/guac-state/tomcat-temp \
    EXTENSIONS=auth-quickconnect

WORKDIR /
EXPOSE 8080

# Do not invoke the base image's /init (s6-overlay). Hostless mounts /var/run
# read-only, but s6 preinit must replace it with a symlink to /run.
ENTRYPOINT ["/usr/local/bin/hostless-entrypoint"]
