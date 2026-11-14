# homelab

Containerd/nerdctl Compose stack for the homelab. This repo used to be a
K3s/Helmfile cluster; that stack was removed in 2026-10 and Compose is the only
deployment mechanism now.

## Services

| App | Purpose |
|---|---|
| [Immich](https://immich.app) | Photo/video backup |
| [Gitea](https://gitea.com) | Self-hosted Git |
| [Caddy](https://caddyserver.com) | Reverse proxy |
| [AdGuard Home](https://adguard.com) | DNS |
| [Jellyfin](https://jellyfin.org) | Media streaming |
| [Hermes](https://github.com/NousResearch/hermes-agent) | AI agent in Matrix |

Full service notes (env, data layout, gotchas): [`containerd/README.md`](containerd/README.md).

## Usage

```bash
cd containerd
nerdctl compose up -d
```

Host-level config (e.g. the Kopia Immich backup timer) is managed with Ansible, run via `just`:

```bash
cp .env.example .env  # set HOST and ANSIBLE_USER
just deploy
```

## Structure

```
├── containerd/      # The Compose stack (services + per-service source config)
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
