# Homelab Kubernetes Platform

Terraform and Terragrunt manage the Kubernetes platform running on two Talos
VMs. Cilium is already installed and is intentionally outside this stack.

| Role | Name | Address | Capacity |
| --- | --- | --- | --- |
| Worker | `talos1` | `192.168.68.6` | 12 vCPU, about 6 GiB RAM |
| Control plane and worker | `talos2` | `192.168.68.7` | 12 vCPU, about 13 GiB RAM |
| TrueNAS SCALE 25.10.5 | `truenas` | `192.168.68.108` | Pool `HDD` |
| AdGuard Home | `adguard` | `192.168.68.8` | LAN DNS |

The initial applications are Authentik at `https://auth.home.papdavid.eu` and
Immich at `https://immich.home.papdavid.eu`.

## Repository layout

```text
modules/platform/          Cluster foundations and shared controllers
modules/identity/          Identity-service modules
modules/applications/      End-user application modules
modules/shared/            Reusable cross-service modules
live/homelab/platform/     Platform Terragrunt units
live/homelab/identity/     Authentik Terragrunt units
live/homelab/applications/ Application Terragrunt units
secrets/                   Values-only SOPS inputs by ownership boundary
docs/                      Architecture and operating procedures
root.hcl                   Shared providers and local-state placement
```

Terragrunt uses descriptive unit names and derives ordering from dependencies.
Local state is stored under the gitignored `.terragrunt-state` directory, never
inside `.terragrunt-cache`.

## Start here

1. Read [prerequisites](docs/prerequisites.md).
2. Prepare [Cloudflare and AdGuard](docs/cloudflare-and-adguard.md).
3. Prepare [TrueNAS](docs/truenas.md).
4. Review and rotate [SOPS secrets](secrets/README.md).
5. Follow the [deployment guide](docs/deployment.md).
6. Read the [risk review](docs/implementation-review.md) and
   [disaster-recovery guide](docs/disaster-recovery.md).

The approved architecture is recorded in the
[design specification](docs/superpowers/specs/2026-08-11-homelab-kubernetes-platform-design.md).

Nothing is committed or applied automatically. The normal workflow is
`terragrunt plan`, review, then `terragrunt apply` in the selected unit.
