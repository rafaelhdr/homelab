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

## Cluster

- **Type**: K3s single-node
- **Kubeconfig**: `~/kube/homelab` (env `KUBECONFIG=~/.kube/homelab`)
- **API server**: `https://10.250.163.241:6443`
- **kube-version suffix**: `+k3s1` (e.g. `1.33.6+k3s1`)
- **Node IP**: `10.250.163.241`, internal node: `khadas` (`192.168.51.15`)

## Deploy

```bash
kubectl apply -f k8s/   # PVs/PVCs, Postgres cluster, ConfigMaps (once)
helmfile apply           # all apps, or --selector name=<app>
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
│   └── jellyfin-storage.yaml      # PVs + PVCs
├── values/
│   ├── homepage.yaml
│   ├── immich.yaml
│   └── jellyfin.yaml
└── README.md
```
