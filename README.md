# homelab

Kubernetes home server managed with [Helmfile](https://github.com/roboll/helmfile).

## Services

| App | Purpose | Chart | Version |
|---|---|---|---|
| [CNPG](https://cloudnative-pg.io) | Postgres operator | cnpg/cloudnative-pg | — |
| [Immich](https://immich.app) | Photo/video backup | immich/immich | 0.12.0 |
| [Jellyfin](https://jellyfin.org) | Media streaming | jellyfin/jellyfin | 3.2.0 |
| [Homepage](https://gethomepage.dev) | Dashboard | m0nsterrr/homepage (OCI) | 4.12.1 |

## Usage

```bash
helmfile apply
```

## Structure

```
├── helmfile.yaml    # Helm repositories and releases
├── k8s/             # Namespaces, PVs, PVCs, Postgres cluster, ConfigMaps
└── values/          # Per-app Helm values
```
