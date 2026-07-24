# AGENTS.md

## Project

Single-node K3s homelab managed with Helmfile. Runs on host `10.250.163.241` (node: `khadas`).

## Quick reference

| App | Namespace | Chart | Version | Access |
|---|---|---|---|---|
| CNPG | cnpg-system | cnpg/cloudnative-pg | — | operator |
| Jellyfin | jellyfin | jellyfin/jellyfin | 3.2.0 | `:30619` |
| Immich | immich | immich/immich | 0.12.0 | `:31547` |
| Homepage | homepage | m0nsterrr/homepage (OCI) | 4.12.1 | `:31569` |
| qBittorrent | qbittorrent | raw manifest (no chart) | gluetun v3.41.1 / qbittorrent 5.2.3 | `:<nodeport>` |

## Cluster

- **Type**: K3s single-node
- **Kubeconfig**: `~/kube/homelab` (env `KUBECONFIG=~/.kube/homelab`)
- **API server**: `https://10.250.163.241:6443`
- **kube-version suffix**: `+k3s1` (e.g. `1.33.6+k3s1`)
- **Node IP**: `10.250.163.241`, internal node: `khadas` (`192.168.51.15`)

## Deploy

```bash
kubectl apply -f k8s/   # PVs/PVCs, Postgres cluster, ConfigMaps, qBittorrent+gluetun Deployment (once)
helmfile apply           # all helm-based apps, or --selector name=<app>
```

All releases use `createNamespace: true` — namespaces are created automatically by helmfile. Raw manifests in `k8s/` must be applied first for PV/PVC/ConfigMap dependencies.

## Conventions

- **Service type**: `NodePort` (no ingress controller)
- **Storage**: `hostPath` PVs with `storageClassName: manual`, `ReclaimPolicy: Retain`
- **Chart versions**: pinned explicitly in `helmfile.yaml`
- **Config**: per-app values in `values/<app>.yaml`
- **Raw manifests**: `k8s/` for PVs, PVCs, Postgres clusters, and ConfigMaps

## Service notes

### CNPG

Postgres operator required by Immich. Version unpinned, runs latest stable.

### Jellyfin

Port `8096`. Uses two hostPath PVs: `jellyfin-config` (5Gi at `/srv/jellyfin/config`) and `jellyfin-media` (250Gi at `/srv/jellyfin/media`).

### Immich

Depends on CNPG Postgres cluster (`immich-database`) with vector extensions (`pgvector` via `cloudnative-vectorchord`). Uses `immich-library` PVC (5Gi, hostPath `/srv/immich/library`). Machine learning disabled. Valkey enabled for job queuing.

### Homepage

**Chart source**: OCI registry `ghcr.io/m0nsterrr/helm-charts/homepage`. Not a regular Helm repo — uses `oci: true` in helmfile. The `url` field must NOT include `oci://` prefix (helmfile adds it, double-prefix breaks it).

```
url: ghcr.io/m0nsterrr/helm-charts
oci: true
```

**Config split across two files**:
- `values/homepage.yaml` — chart values (allowed hosts, service, RBAC, volume mounts)
- `k8s/homepage-config.yaml` — ConfigMap with `services.yaml`, `settings.yaml`, `widgets.yaml`

**Homepage doesn't support wildcard `*` in multi-value `HOMEPAGE_ALLOWED_HOSTS`**. The chart generates a comma-separated list from internal FQDNs + `config.allowedHosts`. Adding `*` to the list doesn't work — Homepage treats `*` only when it's the sole value. The chart has no mechanism to set it to just `*` because it always prepends internal FQDNs.

**Workaround**: Add explicit hosts to `config.allowedHosts`, including the NodePort (e.g. `10.250.163.241:31569`). The NodePort changes on reinstall — update this value after each deploy.

**Dashboard config** (services, settings, widgets) is in `k8s/homepage-config.yaml` as a ConfigMap mounted into `/app/config/`.

### qBittorrent (behind gluetun VPN)

Not a helm release — deployed as a raw two-container Deployment in `k8s/qbittorrent.yaml` (plus `k8s/qbittorrent-namespace.yaml` and `k8s/qbittorrent-storage.yaml`), because the gluetun-sidecar pattern is just a Deployment spec, not something worth a chart for one app. All containers in a pod already share a network namespace in Kubernetes, so qBittorrent's traffic is routed through gluetun for free — no `network_mode: service:` trick needed like in Docker Compose.

- **VPN**: gluetun (`ghcr.io/qdm12/gluetun`), provider ProtonVPN, WireGuard. Note the project's GitHub org was renamed from `qdm12` to `passteque` (same repo, same history/stars — GitHub auto-redirects); image name (`qmcgaw/gluetun` / `ghcr.io/qdm12/gluetun`) is unchanged.
- **Torrent client**: `lscr.io/linuxserver/qbittorrent`, chosen over Transmission/Deluge — most stable under load and has the largest ecosystem of gluetun sidecar examples in the community.
- **Port forwarding**: intentionally not configured (no port-sync sidecar). Simpler and more stable; costs some seeding/upload throughput. Add a port-forward-sync sidecar later if that matters. Note: `PORT_FORWARD_ONLY=on` *is* still set on the gluetun container — for ProtonVPN in gluetun this is actually a server-selection filter (restricts to P2P-capable servers), not the sync feature. Without it gluetun can land on a non-P2P ProtonVPN server and silently block torrent traffic.
- **Requires before first deploy**: a `gluetun-secret` K8s Secret with key `wireguardPrivateKey`, generated from ProtonVPN's account page (Downloads → WireGuard configuration → extract `PrivateKey` from the generated `.conf`). Not stored in this repo.
  ```bash
  kubectl create secret generic gluetun-secret -n qbittorrent \
    --from-literal=wireguardPrivateKey='<key-from-protonvpn>'
  ```
- **Storage**: `qbittorrent-config` (1Gi, hostPath `/srv/qbittorrent/config`) and `qbittorrent-downloads` (100Gi placeholder, hostPath `/srv/qbittorrent/downloads`) — adjust the downloads PV size in `k8s/qbittorrent-storage.yaml` to match actual free disk before applying.
- **Firewall**: gluetun blocks all inbound traffic by default; `FIREWALL_INPUT_PORTS=8080` on the gluetun container allows the WebUI through. If you change qBittorrent's `WEBUI_PORT`, update this too.
- **Health check**: gluetun's built-in health server must bind `0.0.0.0` (`HEALTH_SERVER_ADDRESS=0.0.0.0:9999`), not the `127.0.0.1` default — Kubernetes' `httpGet` liveness probe always targets the pod IP, never `localhost`, so a loopback-only bind causes an endless restart loop (each restart re-negotiates the VPN and briefly drops the firewall rules, disrupting the WebUI).
- **Known gotcha**: qBittorrent's WebUI Host header validation rejects requests whose `Host` doesn't match its allowlist (confirmed: NodePort IP got 401, `Host: localhost` got 200), even `WebUI\ServerDomains=*` doesn't cover numeric IP:port hosts. Fix is `WebUI\HostHeaderValidation=false` in `qBittorrent.conf` on the config PVC — not in git, so a fresh volume needs this reapplied. To edit it safely: scale the deployment to 0 first (qBittorrent rewrites its own config on save/exit, so editing it while the process is running races the process and gets overwritten), edit via a temporary pod mounting `qbittorrent-config`, then scale back up.
- **Known gotcha**: gluetun needs `/dev/net/tun` on the host node. If the gluetun container fails to start, run `modprobe tun` on the node (`khadas`) and make it persistent (e.g. add `tun` to `/etc/modules-load.d/`).

## Checking for updates

Check latest available chart versions against the pinned versions in `helmfile.yaml`:

```bash
# Update repo indexes first
helm repo update

# Check latest version for each pinned chart
helm search repo jellyfin/jellyfin --versions | head -5
helm search repo immich/immich --versions | head -5
helm search repo cnpg/cloudnative-pg --versions | head -5

# OCI chart (homepage) — list tags via crane or skopeo
crane ls ghcr.io/m0nsterrr/helm-charts/homepage | sort -V | tail -5
# or: skopeo list-tags docker://ghcr.io/m0nsterrr/helm-charts/homepage
```

Current pinned versions (update this table after bumping `helmfile.yaml`):

| App | Pinned | Chart |
|---|---|---|
| Jellyfin | 3.2.0 | jellyfin/jellyfin |
| Immich | 0.12.0 | immich/immich |
| CNPG | unpinned | cnpg/cloudnative-pg |
| Homepage | unpinned | m0nsterrr/homepage (OCI) |

After bumping a version in `helmfile.yaml`, run `helmfile apply --selector name=<app>` to deploy. Check the chart's release notes for breaking changes before upgrading.

## Directory structure

```
├── helmfile.yaml          # Repos + releases
├── k8s/
│   ├── homepage-config.yaml       # Homepage dashboard ConfigMap
│   ├── homepage-namespace.yaml    # (redundant with createNamespace: true)
│   ├── immich-namespace.yaml
│   ├── immich-postgres.yaml       # CNPG Cluster CRD
│   ├── immich-storage.yaml        # PV + PVC
│   ├── jellyfin-namespace.yaml
│   ├── jellyfin-storage.yaml      # PVs + PVCs
│   ├── qbittorrent-namespace.yaml
│   ├── qbittorrent-storage.yaml   # PVs + PVCs
│   └── qbittorrent.yaml           # gluetun + qBittorrent Deployment, Service (no chart)
├── values/
│   ├── homepage.yaml
│   ├── immich.yaml
│   └── jellyfin.yaml
└── README.md
```
