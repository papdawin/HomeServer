# Services

All managed service resources are split into Kustomize bundles and applied from the repository root:

```sh
kubectl apply -k services/
```

Bundles:

- `immich/` — Immich server, Valkey, NodePort, and ingress. The existing `pictures` PVC is intentionally external and retained.
- `powerdns/` — authoritative PowerDNS, Recursor, PowerDNS-Admin, Services, and Admin ingress. Credentials remain in existing Kubernetes Secrets.
- `traefik/` — rendered Traefik ServiceAccount, RBAC, Deployment, Service, and IngressClass.
- `homepage/` — Homepage dashboard with links and in-cluster site monitors for the managed web services.
- `metallb/` — the homelab IP pool, L2 advertisement, and pinned speaker override. The MetalLB controller/webhook vendor installation remains separately installed.

Endpoints:

- Traefik: `192.168.68.7`
- DNS Recursor: `192.168.68.8:53`
- Homepage: `https://homepage.home.papdavid.eu`
- Home Assistant: `https://homeassistant.home.papdavid.eu`
- Immich: `https://immich.home.papdavid.eu`
- PowerDNS-Admin: `https://dnsadmin.home.papdavid.eu`
- Prowlarr: `https://prowlarr.home.papdavid.eu`
- qBittorrent: `https://qbittorrent.home.papdavid.eu`
- Sonarr: `https://sonarr.home.papdavid.eu`
- Radarr: `https://radarr.home.papdavid.eu`
- Jellyfin: `https://jellyfin.home.papdavid.eu`

All web UIs use the `*.home.papdavid.eu` naming convention. PostgreSQL, NFS, PowerDNS API, and other internal services remain ClusterIP/internal-only.

Validate without changing the cluster:

```sh
for d in immich powerdns traefik metallb; do kubectl apply --dry-run=server -k "services/$d"; done
```
