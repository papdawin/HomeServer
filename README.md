# HomeServer IaC (Terragrunt + Terraform + Proxmox LXC)

This repository manages Proxmox LXC workloads with Terragrunt.

Current baseline:
- `pve1` is active and has one Jellyfin service unit.
- Jellyfin is provisioned as a standard Terraform-managed LXC from an Ubuntu template image.

## Structure

- `root.hcl`: shared provider/version generation and common env-driven auth.
- `live/pve1/config/node.hcl`: node-level shared config for `pve1`.
- `live/pve1/terragrunt.hcl`: skipped parent config for shared node defaults.
- `live/pve1/containers/jellyfin/terragrunt.hcl`: Jellyfin service unit.
- `modules/proxmox-lxc-service`: service-level composition (template download and LXC module).
- `modules/lxc-container`: reusable low-level LXC resource module.

## Security and Operational Defaults

- API token auth only (no passwords in code).
- Unprivileged LXC by default.
- Firewall enabled on the container interface.

## Prerequisites

1. Terraform and Terragrunt installed.
2. Proxmox API token with permissions required for:
   - container lifecycle
   - template download

## Required Configuration Before First Apply

Update node placeholders in [`live/pve1/config/node.hcl`](/home/papdawin/Programming/HomeServer/live/pve1/config/node.hcl):

- `proxmox_node.api_url`

Update service-specific placeholders in [`live/pve1/containers/jellyfin/terragrunt.hcl`](/home/papdawin/Programming/HomeServer/live/pve1/containers/jellyfin/terragrunt.hcl):

- `containers.jellyfin.static_ipv4_cidr`

Populate [`.env`](/home/papdawin/Programming/HomeServer/.env):

```bash
PVE_API_TOKEN_ID="terraform@pve!provider"
PVE_API_TOKEN_SECRET="replace-with-token-secret"
```

Load `.env` into your current shell before Terragrunt commands:

```bash
set -a
source .env
set +a
```

## Usage

Format Terragrunt HCL:

```bash
terragrunt hcl format
```

Validate and plan the Jellyfin service unit:

```bash
set -a
source .env
set +a
cd live/pve1/containers/jellyfin
terragrunt init
terragrunt validate
terragrunt plan
```

Apply:

```bash
# if this is a new shell session, load .env first:
# set -a; source .env; set +a
terragrunt apply
```

Verify Jellyfin:

- URL: `http://<jellyfin-static-ip>:8096`

## SSH Access With SOPS

The Jellyfin service can inject root SSH public keys at container creation time. It reads them from [`live/pve1/containers/jellyfin/secrets.sops.yaml`](/home/papdawin/Programming/HomeServer/live/pve1/containers/jellyfin/secrets.sops.yaml) if that file exists.

1. Copy [`live/pve1/containers/jellyfin/secrets.sops.yaml.example`](/home/papdawin/Programming/HomeServer/live/pve1/containers/jellyfin/secrets.sops.yaml.example) to `live/pve1/containers/jellyfin/secrets.sops.yaml`.
2. Replace the example key with the contents of your local public key, for example `~/.ssh/id_ed25519.pub`.
3. Encrypt the file with `sops`. The repo-level [`.sops.yaml`](/home/papdawin/Programming/HomeServer/.sops.yaml) creation rule uses your local `~/.ssh/id_ed25519.pub` key:

```bash
sops --encrypt --in-place live/pve1/containers/jellyfin/secrets.sops.yaml
```

4. Apply Terragrunt for the service:

```bash
set -a
source .env
set +a
cd live/pve1/containers/jellyfin
terragrunt apply
```

5. SSH into the container after it is up:

```bash
ssh root@192.168.68.25
```

Notes:
- `sops` must be installed on the machine running Terragrunt because Terragrunt decrypts the file during evaluation.

## Adding More Containers on pve1

1. Create a new service directory under `live/pve1/containers/<service-name>/`.
2. Copy [`live/pve1/containers/jellyfin/terragrunt.hcl`](/home/papdawin/Programming/HomeServer/live/pve1/containers/jellyfin/terragrunt.hcl) and adjust the service values (`ct_id`, hostname, IP, tags, CPU, memory, disk, and optional SSH keys).
3. Run Terragrunt from that service directory only.

This keeps node-level settings centralized in [`live/pve1/config/node.hcl`](/home/papdawin/Programming/HomeServer/live/pve1/config/node.hcl) while each container is independently managed.

## Validation Checklist

- `terragrunt validate` succeeds in `live/pve1/containers/jellyfin`.
- No token secrets exist in repository files.
