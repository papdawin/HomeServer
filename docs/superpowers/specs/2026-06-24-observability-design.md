# Observability Container Design

## Goal

Add a persistent `observability` Proxmox LXC container to this repository that runs a first-stage observability stack using Grafana, Prometheus, Loki, and Promtail.

This first rollout must:

- follow the existing Terragrunt + Nix per-container pattern used by the repo
- persist state on appdata-backed storage
- expose only Grafana through Traefik at `observability.home.papdavid.eu`
- keep Prometheus, Loki, and Promtail internal to the container
- include a healthcheck command for the stack
- avoid wiring other service containers into metrics or log collection yet

## Scope

Included in this change:

- new Terragrunt stack at `live/pve1/containers/observability`
- new Nix flake at `nix/observability/flake.nix`
- persistent appdata mount for observability state
- Grafana, Prometheus, Loki, and Promtail system services
- Grafana provisioning for Prometheus and Loki data sources
- Traefik route for Grafana only
- container-local healthcheck command and service defaults for self-healing
- README updates to document the new stack

Explicitly excluded from this first change:

- scraping or log shipping from other service containers
- dashboards beyond basic Grafana bootstrap
- alerting, notification routing, or Alertmanager
- external monitoring of the healthcheck from Proxmox or another system

## Architecture

The stack will be deployed as a single new `observability` LXC container, matching the repository's current one-service-per-container pattern. The Terragrunt definition will live under `live/pve1/containers/observability/terragrunt.hcl` and will reuse the shared LXC inputs from `live/pve1/containers/common.hcl`.

The container will mount an appdata-backed persistent directory. That mount will hold Grafana state, Prometheus TSDB data, Loki storage, Promtail positions, and generated or provisioned config where needed. This keeps stack state durable across reprovisioning and aligned with the storage approach already used for other services.

Inside the container, NixOS will manage all observability components as native systemd services:

- Grafana for the UI and datasource access
- Prometheus for metrics storage and querying
- Loki for log storage and querying
- Promtail for local log shipping into Loki

Grafana will bind on the container network and be proxied through Traefik. Prometheus, Loki, and Promtail will remain private to the container and will not be routed through Traefik.

## Networking and Exposure

The new container will get a fixed LAN IP in the existing `192.168.68.0/24` subnet and a new VMID. Its firewall rules will allow:

- SSH for administration
- Grafana on the local network and from Traefik
- internal access among observability components on localhost

Traefik will receive one new proxied service entry:

- host: `observability`
- URL target: Grafana's HTTP listener inside the observability container

No public or reverse-proxied routes will be added for Prometheus, Loki, or Promtail.

## Service Design

### Grafana

Grafana is the only user-facing entrypoint for this phase. It will:

- start automatically on boot
- store its database and state on the persistent appdata mount
- be provisioned with Prometheus and Loki datasources using localhost URLs
- listen on the container network interface so Traefik can proxy it

This makes the stack usable immediately after deployment without manual datasource setup.

### Prometheus

Prometheus will start with a minimal configuration:

- self-scrape only, or an equivalently minimal bootstrap config
- persistent TSDB storage on the appdata mount
- no external targets yet

This keeps the initial rollout intentionally narrow while ensuring Prometheus is fully operational and ready for later expansion.

### Loki

Loki will:

- persist its storage on the appdata mount
- expose only its internal HTTP API inside the container
- accept writes from the local Promtail instance

It will not yet ingest logs from other service containers.

### Promtail

Promtail will be included so the logging pipeline is complete from day one. In this first phase it will ship only local logs available inside the observability container, such as selected system logs or service logs supported by the NixOS service layout.

Promtail position tracking will be stored persistently on the appdata mount.

## Health Model

Health is defined at two layers.

### Process resilience

Each core service will use systemd restart-on-failure behavior so transient failures are retried automatically without manual intervention.

### Stack healthcheck

A container-local healthcheck command will be installed, for example `observability-healthcheck`. It will verify readiness of the core stack by checking HTTP readiness endpoints for:

- Grafana
- Prometheus
- Loki

The command will return a non-zero exit code if any required service is unavailable. This gives a single, deterministic operational check that can be run over SSH or reused by future monitoring.

This healthcheck is intentionally local to the container in phase one. It does not yet integrate with Proxmox health reporting or an external watchdog.

## Operational Flow

Deployment will follow the same process as the existing containers:

1. create or update the observability LXC through Terragrunt and the shared LXC module
2. copy the Nix flake into the container
3. run `nixos-rebuild switch`
4. start Grafana, Prometheus, Loki, and Promtail as systemd services
5. access Grafana through `https://observability.home.papdavid.eu`
6. validate the stack with the local healthcheck command

Because only Grafana is externally exposed, all deeper operations remain container-local unless later changes expand the surface area.

## Testing and Validation

The implementation should be validated with:

- `terragrunt hclfmt` for the new Terragrunt stack
- a targeted `terragrunt plan` for `live/pve1/containers/observability`
- successful `nixos-rebuild` during apply
- `systemctl` checks for Grafana, Prometheus, Loki, and Promtail
- successful healthcheck command execution in the container
- successful Grafana access through Traefik
- confirmation that Prometheus and Loki are reachable from Grafana as provisioned datasources

## Risks and Constraints

- All observability components share one container, so a container-level failure affects the whole stack.
- The initial rollout provides infrastructure but not fleet-wide visibility yet, because other services are intentionally not connected.
- NixOS module behavior for Loki, Promtail, or Grafana provisioning may require small configuration adjustments during implementation depending on the exact option surface in the pinned `nixos-25.11` channel.

These are acceptable trade-offs for the first phase because the main objective is a persistent, reachable, repo-native observability foundation.
