# homelab

Kubernetes home server managed with [Helmfile](https://github.com/roboll/helmfile).

## Services

| App | Purpose | Chart | Version |
|---|---|---|---|
| [CNPG](https://cloudnative-pg.io) | Postgres operator | cnpg/cloudnative-pg | — |
| [Jellyfin](https://jellyfin.org) | Media streaming | jellyfin/jellyfin | 3.2.0 |
| [Homepage](https://gethomepage.dev) | Dashboard | m0nsterrr/homepage (OCI) | 4.12.1 |

[Immich](https://immich.app) (photo/video backup) runs separately via containerd/nerdctl — see `containerd/README.md`.

## Usage

```bash
helmfile apply
```

Host-level config (e.g. the Kopia Immich backup timer) is managed with Ansible, run via `just`:

```bash
cp .env.example .env  # set HOST and ANSIBLE_USER
just deploy
```

## Structure

```
├── helmfile.yaml    # Helm repositories and releases
├── k8s/             # Namespaces, PVs, PVCs, Postgres cluster, ConfigMaps
├── values/          # Per-app Helm values
├── containerd/      # Immich, run via nerdctl compose (outside the k8s stack)
├── ansible/         # Host-level config (systemd units, etc), applied via `just deploy`
├── restore-drill/   # Throwaway Immich instance for testing the kopia/B2 backup — see below
└── justfile         # `just deploy` — runs ansible/playbook.yml against $HOST
```

## Restore drills

Immich's library is backed up to Backblaze B2 via kopia (see `AGENTS.md` → "Backups
(Immich)" for how the DB dump rides along in the snapshot). To verify the backup is
actually recoverable, run the `restore-drill` skill (`.claude/skills/restore-drill/`,
project-scoped to this repo) — it restores the latest snapshot and brings up a
disposable Immich instance against it at `http://localhost:2284`. See
`restore-drill/keys.txt.example` for the B2 credentials it needs.
