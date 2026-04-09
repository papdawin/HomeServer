# HomeServer Container Deployment

This repository manages Proxmox LXC containers with Terragrunt/Terraform and NixOS flakes.

## Apply All Containers (Master Command)

Run all container stacks sequentially (init + apply):

```bash
./scripts/containers-master.sh apply-all
```

Optional:

```bash
./scripts/containers-master.sh init-all
```

Notes:
- Default execution is one-by-one (`TG_PARALLELISM=1`).
- You can override parallelism if needed, for example: `TG_PARALLELISM=2 ./scripts/containers-master.sh apply-all`.

## Apply Individual Containers

Run a single container stack directly:

```bash
terragrunt apply --working-dir live/pve1/containers/<name>
```

Examples:

```bash
terragrunt apply --working-dir live/pve1/storage/media
terragrunt apply --working-dir live/pve1/containers/storage-bootstrap
terragrunt apply --working-dir live/pve1/containers/immich
terragrunt apply --working-dir live/pve1/containers/jellyfin
terragrunt apply --working-dir live/pve1/containers/qbittorrent
terragrunt apply --working-dir live/pve1/containers/radarr
terragrunt apply --working-dir live/pve1/containers/sonarr
terragrunt apply --working-dir live/pve1/containers/prowlarr
terragrunt apply --working-dir live/pve1/containers/jellyseerr
terragrunt apply --working-dir live/pve1/containers/openclaw
```

## Required Environment Variables

At minimum, set:
- `PM_API_URL`
- `PM_API_TOKEN_ID`
- `PM_API_TOKEN_SECRET`

Optional/common:
- `PM_TLS_INSECURE` (default `true`)
- `LXC_PASSWORD`
- `BOOTSTRAP_PUBLIC_KEY`
- `BOOTSTRAP_USE_SSH_AGENT` (default `true`)
- `BOOTSTRAP_PRIVATE_KEY_FILE` (default `~/.ssh/id_ed25519`; also used for in-container SOPS decryption)
- `LXC_TEMPLATE`
- `NIXOS_LXC_TEMPLATE_URL`
- `MEDIA_STORAGE_ID` (default `media`)
- `MEDIA_STORAGE_PATH` (default `/mnt/pve/HDD/media`)
- `MEDIA_VOLUME_SIZE` (default `2T`)
- `STORAGE_BOOTSTRAP_START` (default `true`; set `false` after bootstrap to keep helper stopped)

Shared container secrets:
- `live/pve1/containers/common.sops.yaml` holds encrypted values used by container flakes (including `services.jellyfin.password`, `services.qbittorrent.password`, and `services.mediaautomation.*` integration credentials).

## Shared Media HDD (Media Stack)

This setup uses a Proxmox **volume mount** (not host-path bind mount):

- Terraform creates a Proxmox directory storage on your HDD (`live/pve1/storage/media`)
- `storage-bootstrap` creates `/media` as a volume on that storage and is the single place that bootstraps the shared directory layout
- qBittorrent, Jellyfin, Radarr, Sonarr, Prowlarr, and Jellyseerr all mount that same existing helper-created volume at `/media`
- Services enforce a shared `media` group (GID `2000`) and setgid directory permissions
- Expected directories inside the mount: `/media/movies`, `/media/shows`, `/media/other`, `/media/music`, `/media/downloads/radarr`, `/media/downloads/sonarr`, `/media/downloads/other`, `/media/downloads/incomplete`, `/media/appdata/qbittorrent`, `/media/appdata/radarr`, `/media/appdata/sonarr`, `/media/appdata/prowlarr`, `/media/appdata/jellyseerr`

Set storage values, then apply in dependency order:

```bash
export MEDIA_STORAGE_ID=<your-hdd-storage-id>
export MEDIA_STORAGE_PATH=<path-mounted-from-hdd-on-proxmox-node>
export MEDIA_VOLUME_SIZE=2T

terragrunt apply --working-dir live/pve1/storage/media
terragrunt apply --working-dir live/pve1/containers/storage-bootstrap
terragrunt apply --working-dir live/pve1/containers/qbittorrent
terragrunt apply --working-dir live/pve1/containers/jellyfin
terragrunt apply --working-dir live/pve1/containers/radarr
terragrunt apply --working-dir live/pve1/containers/sonarr
terragrunt apply --working-dir live/pve1/containers/prowlarr
terragrunt apply --working-dir live/pve1/containers/jellyseerr
```

Re-apply is idempotent:
- Storage will not be recreated if unchanged.
- Storage resource has `prevent_destroy` to avoid accidental deletion.
- Helper bootstrap is idempotent.

Note on deleting the helper:
- The shared media volume is owned by the helper container VMID.
- Deleting the helper may remove the attached volume unless you first migrate/detach ownership manually.

## Proxmox API Token Permissions

If applies fail with permission errors, broaden permissions on the API token used by:
- `PM_API_TOKEN_ID`
- `PM_API_TOKEN_SECRET`

Recommended role mapping for this repo:
- `/` (propagate): `PVEAuditor`
- `/nodes/server` (propagate): `PVEVMAdmin`
- `/storage/local` (propagate): `PVEAuditor` (read template storage)
- `/storage/local-lvm` (propagate): `PVEStorageAdmin` (container rootfs allocation)
- `/storage/media` (propagate): `PVEStorageAdmin` (shared media storage + mount usage)

Important:
- API tokens cannot create LXC bind mounts (host-path mounts like `/mnt/...`) on current Proxmox releases.
- If you need bind mounts, authenticate as `root@pam` (username/password or ticket auth), not token auth.

Fastest broad option (less secure, easiest while bootstrapping):
- assign `Administrator` on `/` (propagate) to the token's backing user.

After changing ACLs/tokens, export env vars again and re-run `terragrunt apply`.
