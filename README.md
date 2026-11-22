# Apache Guacamole on Hostless

This repository deploys Apache Guacamole as a browser-based remote desktop gateway. It does not host or create the Windows VM; connect it to a separate Windows VPS using that VPS's reachable IP address and RDP port.

## Hostless deployment

1. Connect your Hostless App to this repository and select the `main` branch.
2. Use the Docker build system and the repository's `Dockerfile`.
3. Set the container port to `8080`.
4. Attach persistent storage mounted at `/config`.
5. Keep the app at one replica.
6. Deploy or redeploy the app after changes to the Dockerfile.

The image includes the Guacamole web client, `guacd`, and PostgreSQL. The Dockerfile enables Guacamole's official QuickConnect extension.

## Connect to a Windows VPS by entering its details

1. Sign in to your Hostless Guacamole URL.
2. On the Guacamole home page, find the **QuickConnect** field.
3. Enter an RDP URI using the Windows VPS's public IP or DNS name and RDP port:

   `rdp://WINDOWS_USERNAME@PUBLIC_IP:3389/?security=nla`

4. Replace `WINDOWS_USERNAME` and `PUBLIC_IP` with the values from your Windows VPS provider.
5. Press Enter or click the connect icon.
6. Enter the Windows password when Guacamole prompts you. Do not put the password in the URI.

Example using documentation-only placeholder values:

`rdp://Administrator@203.0.113.10:3389/?security=nla`

The IP address above is reserved for examples and will not connect to a real VPS.

## RDP connection details

| Item | What to enter |
|---|---|
| Protocol | RDP |
| Host | Public IPv4 address or DNS name of the Windows VPS |
| Port | Usually `3389`, unless the provider specifies another port |
| Username | Windows account username |
| Password | Enter when prompted; do not put it in the URI |
| Security | NLA if the Windows VPS requires Network Level Authentication |

Guacamole's QuickConnect field creates an ad-hoc connection that exists only for the current Guacamole session; it does not save the connection profile.

## Network and security requirements

- The address must be reachable **from the Hostless Guacamole container**, not merely from your own computer.
- The VPS must have Remote Desktop enabled and be listening on the specified TCP port.
- The VPS provider's firewall/security group must permit inbound RDP from the Guacamole server. Prefer restricting the source to Hostless's outbound IP address if Hostless provides a stable one.
- Do not expose RDP/3389 to the entire internet when you can restrict the source. Use a strong Windows password and keep NLA enabled.
- If the VPS provider only allows RDP from a private network, or Hostless cannot reach the VPS IP/port, direct QuickConnect cannot bypass that restriction; a private network or tunnel would be needed.

## Storage and scaling

- Keep the persistent volume mounted at `/config`; this stores the image's PostgreSQL data and Guacamole configuration.
- Keep one replica when using the single embedded PostgreSQL instance.

## QuickConnect security note

QuickConnect lets authenticated Guacamole users initiate ad-hoc connections and specify connection parameters. Only give Guacamole accounts to people you trust. Do not paste passwords into QuickConnect URIs, screenshots, or chat messages.
