# HomeServer

This repository manages my full homelab media and automation stack on Proxmox using Terraform/Terragrunt for infrastructure and Nix flakes for in-container service configuration.

![Proxmox UI resources](https://github.com/papdawin/HomeServer/blob/main/pictures/proxmox.png?raw=true)

_Proxmox UI screencapture showing the resources and containers provisioned by Terraform/Terragrunt from this repository._

## Tech choices and why

| Technology | Why it is used here |
| --- | --- |
| Proxmox LXC | Lower overhead than full VMs, fast boot, simple isolation per service. |
| Terraform (`bpg/proxmox`) | Declarative container/storage provisioning with repeatable state. |
| Terragrunt | Shared config, dependency orchestration, and clean per-service stacks under `live/`. |
| NixOS flakes per service | Reproducible, pinned, versioned system config for each container. |
| SOPS-encrypted shared secrets | Secrets stay encrypted in Git while still being consumable during bootstrap. |
| Bootstrap scripts (API-driven) | Removes manual first-run UI setup for Jellyfin/Radarr/Sonarr/Prowlarr/Jellyseerr/qBittorrent. |
| Shared `/media` volume + `media` group | Consistent cross-container file ownership and predictable automation behavior. |

## Architecture

- `modules/lxc`: The "definitions" of my LXC containers, networking, mounts, which then applies the matching Nix flake over SSH.
- `modules/storage-directory`: Creates the Proxmox directory storage used by the media stack.
- `live/pve1/storage/media`: Defines shared HDD-backed storage.
- `live/pve1/storage/appdata`: Defines separate HDD-backed storage for app data volumes.
- `live/pve1/containers/*`: One stack per service, with explicit dependencies.
- `nix/<service>/flake.nix`: Service runtime config (ports, users, firewall, bootstrap services).
- `scripts/ensure-nixos-template.sh`: Auto-downloads NixOS LXC template if missing.

## Currently implemented services

| Stack | VMID | IP | Purpose |
| --- | ---: | --- | --- |
| `storage/media` | - | Proxmox storage | Shared directory storage (`rootdir`) for media volumes. |
| `storage/appdata` | - | Proxmox storage | Shared directory storage (`rootdir`) for app data volumes. |
| `storage-bootstrap` | 124 | 192.168.68.24 | Initializes `/media` layout, permissions, and helper appdata mounts. |
| `jellyfin` | 125 | 192.168.68.25 | Media streaming server. |
| `qbittorrent` | 126 | 192.168.68.26 | Download client for automation pipeline. |
| `hermes` | 127 | 192.168.68.27 | Hermes Agent gateway service with Honcho and Hermes WebUI. |
| `nomad` | 133 | 192.168.68.33 | Nomad travel/planning service container. |
| `immich` | 128 | 192.168.68.28 | Photo/video backup and gallery service. |
| `radarr` | 129 | 192.168.68.29 | Movie automation and library management. |
| `sonarr` | 130 | 192.168.68.30 | TV automation and library management. |
| `prowlarr` | 131 | 192.168.68.31 | Indexer management + sync to Radarr/Sonarr. |
| `jellyseerr` | 132 | 192.168.68.32 | User request portal integrated with Jellyfin and *arr apps. |
| `nextcloud` | 134 | 192.168.68.34 | Personal cloud/file sync service with full shared media mount access. |
| `bazarr` | 135 | 192.168.68.35 | Subtitle management integrated with Sonarr/Radarr. |
| `mealie` | 136 | 192.168.68.36 | Recipe and meal planning service. |
| `gotify` | 137 | 192.168.68.37 | Self-hosted notification service. |
| `traefik` | 138 | 192.168.68.38 | HTTPS reverse proxy for `*.home.papdavid.eu`. |
| `adguardhome` | 139 | 192.168.68.39 | Local DNS server with wildcard rewrite to Traefik. |
| `lidarr` | 140 | 192.168.68.40 | Music automation and library management. |
| `kima` | 141 | 192.168.68.41 | Self-hosted music streaming and discovery integrated with Lidarr. |

![Container diagram](https://github.com/papdawin/HomeServer/blob/main/pictures/container-diagram.png?raw=true)

_My currently existing containers visualized via excalidraw._


## Deploy

1. Load your environment file and export variables:

```bash
set -a
source .env
set +a
```

Provider auth options (from `.env`):
- API token auth: `PM_API_TOKEN_ID` + `PM_API_TOKEN_SECRET`
- Username/password auth: `PM_USERNAME` + `PM_PASSWORD` (takes precedence when both are set)

For secrets with shell characters (for example `$`), prefer single quotes in `.env` values so `source .env` loads them literally.

Also set `LXC_PASSWORD` and storage/SSH values as needed.
2. Apply shared storage:

```bash
terragrunt apply --working-dir live/pve1/storage/media
terragrunt apply --working-dir live/pve1/storage/appdata
```

3. Apply containers:

```bash
terragrunt run --all apply --queue-include-external --working-dir live/pve1/containers
```

For one service only:

```bash
terragrunt apply --working-dir live/pve1/containers/<service>
```

## Repository map

- `live/`: environment stacks (what is deployed)
- `modules/`: reusable Terraform modules (how resources are provisioned)
- `nix/`: service-level NixOS flakes (how services are configured)
- `scripts/`: deployment helpers
