# Apache Guacamole on Hostless (diskless mode)

This repository deploys Apache Guacamole as a browser-based remote desktop gateway. It does not host or create the Windows VM; connect it to a separate Windows VPS using that VPS's reachable IP address and RDP port.

## Hostless deployment — no paid disk required

1. Connect your Hostless App to this repository and select the main branch.
2. Use the Docker build system and the repository's Dockerfile.
3. Set the container port to 8080.
4. Leave the Start Command empty so the Dockerfile entrypoint runs.
5. Do not attach a disk. The custom entrypoint stores temporary Guacamole and PostgreSQL state under Hostless's writable /tmp directory.
6. Keep one replica.
7. Deploy or redeploy the app.

The image includes the Guacamole web client, guacd and PostgreSQL. It enables the QuickConnect extension so you can enter RDP details without saving a connection profile.

## Runtime model for Hostless

Hostless mounts the root filesystem read-only and mounts /var/run as a read-only directory. The base image's s6-overlay preinit tries to replace /var/run with a symlink to /run. That fails on Hostless.

The custom Dockerfile entrypoint bypasses /init and starts PostgreSQL, guacd and Tomcat directly. The Dockerfile sets the container user to the unprivileged postgres account. This is important: Hostless does not allow chown operations on its temporary filesystem, so the process creates PostgreSQL's data directory as the postgres user from the beginning.

If runtime logs show /package/admin/s6-overlay/libexec/preinit, verify that Hostless deployed the newest commit, uses the Docker build system and has an empty Start Command. Hostless's Docker Start Command replaces CMD, while the image's ENTRYPOINT is defined in the Dockerfile.

## Automatic InstaBox desktop tunnel

The app image includes the InstaBox CLI and OpenSSH client. When the Guacamole app starts, its entrypoint launches a background supervisor that:

- Checks the state of the `linux-guaq` machine.
- Starts it if stopped, or resumes it if paused.
- Waits for it to report Running.
- Opens and continuously retries the VNC tunnel from `127.0.0.1:15901` to port `5901` on the InstaBox machine.

Keep the existing Hostless app environment variable `INSTABOX_API_KEY` configured. The supervisor does not print the key. Optional settings are `INSTABOX_MACHINE` (default `linux-guaq`), `INSTABOX_LOCAL_PORT` (default `15901`), and `INSTABOX_REMOTE_PORT` (default `5901`).

The tunnel runs inside the Guacamole app process environment, not an embedded Hostless worker. This is intentional: Guacamole connects to `127.0.0.1:15901`, and a separate worker has a different localhost. The supervisor restarts the tunnel if it exits.

## Important: temporary data only

Hostless's /tmp area is writable but is cleared when the app process starts again. This diskless configuration avoids creating a paid persistent disk, but all Guacamole database state is temporary.

- The PostgreSQL database is recreated after a restart or redeploy.
- The initial Guacamole login returns to the image/schema default (normally guacadmin / guacadmin) after fresh initialization.
- Changed Guacamole passwords, saved connections, users, history and other local database records are lost on restart.
- QuickConnect itself does not save connection profiles, so you can enter the Windows VPS details again after signing in.
- Hostless documents a 500 MiB limit for /tmp. Do not use it to store recordings or large files.

Change the initial Guacamole password after each fresh start. Do not expose the public Guacamole URL without protecting access to it.

## Connect to a Windows VPS by entering its details

1. Sign in to your Hostless Guacamole URL.
2. On the Guacamole home page, find the QuickConnect field.
3. Enter an RDP URI using the Windows VPS's reachable public IP or DNS name and RDP port:

   `rdp://WINDOWS_USERNAME@PUBLIC_IP:3389/?security=nla`

4. Replace WINDOWS_USERNAME and PUBLIC_IP with the values from your Windows VPS provider.
5. Press Enter or click the connect icon.
6. Enter the Windows password when Guacamole prompts you. Do not put the password in the URI.

Example using documentation-only placeholder values:

`rdp://Administrator@203.0.113.10:3389/?security=nla`

The IP above is reserved for examples and will not connect to a real VPS.

## Runtime settings

- Build system: Docker
- Dockerfile: ./Dockerfile
- Working directory: /
- Start command: empty
- Container port: 8080
- Runtime: 0.5 vCPU and 1024 MiB RAM, if available
- Replicas: 1
- Persistent disk: none
- Health check: HTTP /

## Network and security requirements

The Windows VPS address must be reachable from the Hostless Guacamole container, not merely from your own computer. The VPS must have Remote Desktop enabled and its provider firewall must permit inbound RDP from the Guacamole server. Restrict the source to Hostless's outbound IP if Hostless provides a stable one; avoid exposing RDP/3389 to the entire internet.

If the VPS provider only allows RDP from a private network, or Hostless cannot reach the VPS IP/port, QuickConnect cannot bypass that restriction; a private network or tunnel would be needed.

## QuickConnect security note

QuickConnect lets authenticated Guacamole users initiate ad-hoc connections and specify connection parameters. Only give Guacamole accounts to people you trust. Do not paste passwords into QuickConnect URIs, screenshots or chat messages.
