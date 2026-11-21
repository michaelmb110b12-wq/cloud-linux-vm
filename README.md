# Apache Guacamole on Hostless + Windows GitHub Actions runner

This branch contains the Hostless Guacamole app and a separate GitHub Actions workflow that starts a temporary Windows runner and makes its RDP service reachable by Guacamole.

## Part 1: Deploy Guacamole on Hostless

1. Create a Hostless App connected to this repository and select the install-windows-vm branch.
2. Select the Docker build system.
3. Set the container port to 8080.
4. Attach persistent storage mounted at /config.
5. Keep the app at one replica.
6. Deploy and open the Hostless URL.

The Docker image includes the Guacamole web client, guacd, and PostgreSQL in one container.

## Part 2: Configure the Windows GitHub Actions runner

The workflow is .github/workflows/windows-guac.yml. It enables RDP on the temporary Windows runner, creates a dedicated non-administrator local account named guacuser, requires Network Level Authentication (NLA), and opens a free Pinggy TCP tunnel to 127.0.0.1:3389.

### Required GitHub Actions secret

In the GitHub repository, open Settings → Secrets and variables → Actions and create:

- WINDOWS_RDP_PASSWORD: a strong password of at least 24 characters for the temporary guacuser Windows account.

Do not put the password in the YAML file or commit it to Git. There is no ngrok account, ngrok token, credit card, Tailscale, or RustDesk required.

### Free tunnel limitations

This workflow uses Pinggy's free TCP tunnel. Pinggy documents free TCP tunnels without signup, but its free tunnels expire after about 60 minutes. The hostname and port are randomly allocated and change when the tunnel reconnects.

The workflow timeout is 90 minutes to allow time for optional app installation plus the tunnel. The tunnel itself lasts about 60 minutes. When it expires, the SSH step ends. Run the workflow again to get a new endpoint.

### Run the workflow

1. This workflow file is in the install-windows-vm branch. GitHub requires a workflow_dispatch workflow to exist on the default branch before it can be manually run. To run it, first copy or merge .github/workflows/windows-guac.yml into the repository's default branch; then select install-windows-vm in the branch selector when running it.
2. Open Actions → Windows Cloud PC (Guacamole).
3. Select Run workflow and optionally change the Chocolatey app list.
4. Wait for the step Verify Pinggy host key and open the free TCP tunnel. Its SSH output displays an address like tcp://hostname:port.
5. Keep the Actions job running while you use the Windows desktop.

**Public repository warning:** this repository is public, so workflow logs may be publicly visible. The temporary TCP endpoint is printed in the SSH step output so you can copy it. Anyone who sees the endpoint can attempt an RDP connection. NLA is required and the password is stored as a GitHub Actions secret, but a strong password is essential. Consider making the repository private before using remote desktop if you do not want the temporary endpoint exposed in public logs.

## Part 3: Add the Windows runner in Guacamole

In Guacamole, open Settings → Connections → New Connection and use:

| Guacamole field | Value |
|---|---|
| Name | Windows Cloud PC |
| Protocol | RDP |
| Hostname | Host from the Pinggy TCP address |
| Port | Port from the Pinggy TCP address |
| Username | guacuser |
| Password | Value stored in WINDOWS_RDP_PASSWORD |
| Domain | Leave blank |
| Security mode | NLA |
| Ignore server certificate | Enable only if certificate validation fails |

Save the connection and launch it.

## Security and lifetime notes

- The Windows runner is temporary. The workflow has a 90-minute job timeout, allowing for setup plus the approximately 60-minute free tunnel.
- Only RDP port 3389 is forwarded. The Windows firewall's Remote Desktop rules are restricted to loopback addresses; the runner does not intentionally accept direct external RDP connections.
- The Pinggy TCP endpoint is reachable by anyone who knows the temporary hostname and port. NLA and a strong password protect the Windows login, but the endpoint is not private network access.
- The free hostname and port change each run. Update the Guacamole connection after starting a new workflow.
- Guacamole does not create a permanent Windows VM. It provides browser-based access to the temporary Windows GitHub Actions runner.
- The Windows runner's default wallpaper is left unchanged; no custom branding or desktop note is applied.
