# Apache Guacamole on Hostless

This branch deploys the self-contained `abesnier/guacamole` image. It includes the Guacamole web client, `guacd`, and PostgreSQL in one container.

## Hostless configuration

1. Create a Hostless **App** connected to this repository.
2. Select the `install-windows-vm` branch.
3. Select the **Docker** build system. The repository's `hostless.yaml` selects `./Dockerfile` and configures a single replica.
4. Set the app's **container port** to `8080`. The image's Tomcat server listens on port 8080.
5. Attach a persistent volume mounted at **`/config`**. This is required: the image stores its PostgreSQL database and Guacamole configuration there. Hostless's root filesystem is not persistent.
6. Deploy the app and open its Hostless URL.

Keep the app at one replica while using the single `/config` volume. Do not scale it horizontally.

## First login and security

The image's initial login is `guacadmin` / `guacadmin`. Sign in and change that password immediately before sharing or exposing the URL. Do not commit VM usernames, passwords, or other secrets to this repository.

## Connecting to a Windows machine

Guacamole is a remote-desktop gateway; it does **not** create or boot a Windows virtual machine.

To connect a Windows VM, first run that VM on a separate host that supports virtualization and RDP. Enable Remote Desktop on Windows and make sure the Hostless app can reach the VM over the network. In Guacamole, create a new **RDP** connection and enter the Windows machine's reachable hostname/IP, RDP port (normally `3389`), and credentials.

A normal Hostless app container is not itself a Windows VM host. Do not assume nested virtualization or `/dev/kvm` access is available unless Hostless explicitly confirms it.

## Runtime notes

- The app listens on container port `8080`; configure Hostless's container port to match.
- The persistent volume must be mounted at `/config`, not at an arbitrary directory.
- The included health check probes `/` over HTTP.
- The default resource profile is one replica, 0.5 vCPU maximum, and 1 GiB memory maximum. Hostless resource allowances are shared across your project, so lower other workloads or adjust the allocation if the project has already used that allowance.
- Optional environment variable: set `TZ` in Hostless to your preferred IANA time zone.

## Why there is no docker-compose.yml

Hostless builds this app from a Dockerfile. The selected image already runs the three Guacamole components together, so a Compose deployment is unnecessary.
