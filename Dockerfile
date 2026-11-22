# Self-contained Guacamole image: web client + guacd + PostgreSQL.
# Hostless should route traffic to container port 8080.
FROM abesnier/guacamole:1.6.0-pg17

# Add the QuickConnect bar to the Guacamole home page.
# Users can enter ad-hoc RDP/SSH/VNC URIs without saving connection profiles.
ENV EXTENSIONS=auth-quickconnect

EXPOSE 8080
