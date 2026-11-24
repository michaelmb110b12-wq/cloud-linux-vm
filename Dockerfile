# Apache Guacamole + guacd + PostgreSQL in one image.
# Hostless uses a read-only root filesystem; runtime data is placed in /tmp.
FROM abesnier/guacamole:1.6.0-pg17

# The InstaBox tunnel needs curl for CLI installation and OpenSSH for VNC forwarding.
USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl openssh-client \
    && rm -rf /var/lib/apt/lists/*
ENV INSTABOX_INSTALL_HOME=/opt/instabox-install
RUN mkdir -p "$INSTABOX_INSTALL_HOME" \
    && HOME="$INSTABOX_INSTALL_HOME" sh -c 'curl -fsSL https://api.instabox.sh/install.sh | sh' \
    && test -x "$INSTABOX_INSTALL_HOME/.local/bin/instabox" \
    && chmod 0755 "$INSTABOX_INSTALL_HOME/.local/bin/instabox" \
    && chmod 0755 "$INSTABOX_INSTALL_HOME" "$INSTABOX_INSTALL_HOME/.local" "$INSTABOX_INSTALL_HOME/.local/bin"

COPY hostless/entrypoint.sh /usr/local/bin/hostless-entrypoint
COPY hostless/instabox-tunnel-supervisor.sh /usr/local/bin/instabox-tunnel-supervisor
RUN chmod 0755 /usr/local/bin/hostless-entrypoint /usr/local/bin/instabox-tunnel-supervisor

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
