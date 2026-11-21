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

The workflow is .github/workflows/windows-guac.yml. It enables RDP on the temporary Windows runner, creates a dedicated non-administrator local account named guacuser, requires Network Level Authentication (NLA), starts an ngrok TCP endpoint for port 3389, and keeps the runner alive until the job ends.

### Required GitHub Actions secrets

In the GitHub repository, open Settings → Secrets and variables → Actions and create:

- NGROK_AUTHTOKEN: your ngrok agent authtoken.
- WINDOWS_RDP_PASSWORD: a strong password of at least 20 characters for the temporary guacuser Windows account.

Do not put either value in the YAML file or commit them to Git.

### ngrok account requirement

Cloudflare Quick Tunnels do not provide the raw TCP endpoint needed for this RDP route, and publishing Cloudflare TCP applications requires a Cloudflare-managed domain. This workflow therefore uses ngrok TCP instead; it does not use Cloudflare, Tailscale, or RustDesk.

ngrok currently makes TCP endpoints available on its free plan only after a valid payment method is added to the account. The free plan has usage and connection limits. Its free TCP endpoint is randomly assigned, so the hostname and port can change on each workflow run.

### Run the workflow

1. Make sure this workflow file is present on the repository's default branch. GitHub requires a workflow_dispatch workflow to exist on the default branch before it can be manually run.
2. Open Actions → Windows Cloud PC (Guacamole).
3. Select Run workflow and optionally change the Chocolatey app list.
4. Wait for the step Start temporary ngrok TCP endpoint for RDP to complete.
5. Open your ngrok dashboard at https://dashboard.ngrok.com/endpoints. Find the active TCP endpoint and copy its hostname and port. The address is deliberately not written to this repository's workflow logs because this repository is public.
6. Keep the Actions job running while you use the Windows desktop.

## Part 3: Add the Windows runner in Guacamole

In Guacamole, open Settings → Connections → New Connection and use:

| Guacamole field | Value |
|---|---|
| Name | Windows Cloud PC |
| Protocol | RDP |
| Hostname | Host from the active ngrok TCP endpoint |
| Port | Port from the active ngrok TCP endpoint |
| Username | guacuser |
| Password | Value stored in WINDOWS_RDP_PASSWORD |
| Domain | Leave blank |
| Security mode | NLA |
| Ignore server certificate | Enable only if certificate validation fails |

Save the connection and launch it.

## Important lifetime and security notes

- The Windows runner is temporary. GitHub-hosted jobs have a six-hour maximum; this workflow stops at 350 minutes, before that hard limit.
- The ngrok TCP endpoint is public. RDP is configured to require NLA and a strong password. Do not share the endpoint or password.
- The workflow does not print the ngrok hostname or port in its logs because the repository is public. Retrieve the active endpoint from your own ngrok dashboard.
- The random free TCP address can change each run. Update the Guacamole connection's hostname and port after each new workflow run.
- A reserved, stable TCP address is a paid ngrok feature. No Cloudflare domain is required for this ngrok setup.
- Guacamole does not create the Windows VM. It provides browser-based access to the temporary Windows GitHub Actions runner.
- The Windows runner's default wallpaper is left unchanged; no custom branding or desktop note is applied.
