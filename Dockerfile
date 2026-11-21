# Self-contained Guacamole image: web client + guacd + PostgreSQL.
# Hostless should route traffic to container port 8080.
FROM abesnier/guacamole:1.6.0-pg17

EXPOSE 8080
