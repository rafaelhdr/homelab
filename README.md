# homelab

Kubernetes home server managed with [Helmfile](https://github.com/roboll/helmfile).

## Services

| App | Purpose | Chart |
|---|---|---|
| [Immich](https://immich.app) | Photo/video backup | immich/immich |
| [Jellyfin](https://jellyfin.org) | Media streaming | jellyfin/jellyfin |

## Usage

```bash
helmfile apply
```

## Structure

```
├── helmfile.yaml    # Helm repositories and releases
├── k8s/             # Namespaces, PVs, PVCs, Postgres cluster
└── values/          # Per-app Helm values
```
