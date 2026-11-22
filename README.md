# Apache Guacamole on Hostless (diskless mode)

This repository deploys Apache Guacamole as a browser-based remote desktop gateway. It does not host or create a Windows VM; connect it to a separate Windows VPS using that VPS's reachable IP address and RDP port.

## Hostless deployment — no paid disk required

1. Connect your Hostless App to this repository and select the main branch.
2. Use the Docker build system and the repository's Dockerfile.
3. Set the container port to 8080.
4. Leave the Start Command empty so the Dockerfile entrypoint runs.
5. Do not attach a disk. The Dockerfile redirects Guacamole/PostgreSQL state and the s6-overlay runtime directory to Hostless's writable temporary /tmp area.
6. Keep one replica.
7. Deploy or redeploy the app.

The image includes the Guacamole web client, guacd and PostgreSQL. It enables the QuickConnect extension so you can enter RDP details without saving a connection profile.

## Why the custom entrypoint is needed

Hostless makes the image filesystem read-only. The bundled s6-overlay normally cleans and creates runtime files under /run. This image redirects /run to /tmp/run before starting /init and enables S6_READ_ONLY_ROOT=1 so s6-overlay follows its read-only-root startup path.

The s6-overlay documentation requires /run to be writable in read-only-root mode. This setup relies on Hostless's writable /tmp mount being writable and executable. If Hostless mounts /tmp with noexec or does not allow the symlinked /run path, the runtime still cannot start; check the new runtime logs for the next specific error.

## Important: temporary data only

Hostless's /tmp area is writable but is cleared when the app process starts again. This diskless configuration is intended for temporary use and avoids creating a paid persistent disk.

That means:
- Guacamole's local PostgreSQL database is recreated after a restart or redeploy.
- The initial Guacamole login returns to the image/schema default (normally guacadmin / guacadmin) after a fresh database initialization.
- Any changed Guacamole password, saved connections, users, history and other local database records are lost on restart.
- QuickConnect itself does not save connection profiles, so you can type the Windows VPS details again after signing in.
- Hostless documents a 500 MiB limit for /tmp. Keep this as a small, temporary gateway; do not use it to store recordings or large files.

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
