# AGENTS.md

## Project

Containerd/nerdctl Compose stack for the homelab — Immich, Gitea, Caddy, AdGuard,
Jellyfin, Hermes, Plik, Multica, all defined in `containerd/docker-compose.yml` (see
`containerd/README.md` for per-service notes). Host-level config (systemd units)
is applied with Ansible via `just deploy` (`ansible/playbook.yml`).

This repo used to be a single-node K3s/Helmfile homelab on host `khadas`
(`10.250.163.241`). The K3s stack, the Helmfile releases (`k8s/`, `values/`,
`helmfile.yaml`) and the host itself were retired in 2026-10 — Compose is the
only deployment mechanism now. Service notes for apps that were dropped with the
cluster (Radarr, Prowlarr, Homepage) live in the *private* repo's `FUTURE.md`.

## Conventions

- `nerdctl compose`, never `docker compose` — named volumes resolve differently
  (`homelab_*` prefix) and mixing the two creates empty volumes.
- Service data lives under `DATA_ROOT` (see `containerd/README.md`), outside any
  git tree on the server. Never commit it.
- `containerd/docker-compose.yml` is the single source of truth for the Immich
  compose spec — `restore-drill/setup.sh` generates its copy from it; never
  hand-duplicate.

## Backups (Immich)

Kopia snapshots `/home/rafaelhdr/homelab/library` (Immich's `UPLOAD_LOCATION`) every 4h via a systemd timer/service pair templated by Ansible (`ansible/templates/kopia-immich-backup.{service,timer}.j2`, applied via `just deploy`). Only the library folder is snapshotted — Postgres isn't backed up directly by kopia.

Immich's own scheduled DB backup (Administration → Settings → Backup in the UI, not stored in git) writes `pg_dump` output into `library/backups/`, which rides along inside the same kopia snapshot since it's just another file under the snapshotted path — that's how the Postgres state actually gets backed up, not via kopia talking to the DB.

**Cadence is intentionally offset, not identical.** Immich's DB backup cron is `0 */4 * * *` — the same 4h grid as kopia. Kopia's timer runs 15 minutes later (`OnCalendar=*-*-* 0/4:15:00`) so it reliably picks up the dump that was *just* written instead of racing it: firing both at `:00` risks kopia grabbing yesterday's dump file and not catching the fresh one until the next cycle, four hours later.

**After editing the timer/service templates**, `just deploy` alone is sufficient — `daemon-reload` doesn't restart an already-running timer with the old `OnCalendar` baked in, so the playbook notifies a handler (`Restart kopia-immich-backup timer`) whenever the template content actually changes, restarting it automatically. No manual `systemctl restart` needed after a normal deploy.

**Restore drills**: `restore-drill/` is a throwaway Immich instance for testing recovery locally, driven by the project-scoped `restore-drill` skill (`.claude/skills/restore-drill/`) plus two checked-in scripts. `setup.sh` generates `docker-compose.yml` from `containerd/docker-compose.yml` (the single source of truth for the compose spec — never hand-duplicated) and a throwaway `.env` with a fresh DB password; `restore.sh` connects to the already-authenticated kopia repository and restores the latest snapshot into `restore-drill/library`. B2 credentials (bucket, key ID, application key) live in `restore-drill/keys.txt` (gitignored, template at `keys.txt.example`) — deliberately separate from the compose `.env`, and the repository *password* itself is never stored anywhere, only supplied interactively when connecting kopia. The skill restores the snapshot, brings the stack up, then leaves the DB half to Immich's own "Restore Your Library" wizard, which replays the newest `library/backups/immich-db-backup-*.sql.gz` against the fresh Postgres container. `restore-drill/keys.txt`, `docker-compose.yml`, `.env`, `library/`, `postgres/`, and `.kopia/` are all gitignored — credentials, generated config, and restored data never get committed.

## Directory structure

```
├── containerd/
│   ├── docker-compose.yml      # The whole stack (Immich, Gitea, Caddy, AdGuard, Jellyfin, Hermes, Plik, Multica)
│   ├── Caddyfile
│   ├── README.md               # Per-service notes (data layout, gotchas)
│   └── hermes/                 # Hermes personas + .example config seeds
├── ansible/                    # Kopia Immich backup timer (systemd), via `just deploy`
├── restore-drill/              # Scripts for the throwaway Immich restore-drill instance
├── .claude/skills/restore-drill/  # The restore-drill skill itself
└── justfile                    # `just deploy` — runs ansible/playbook.yml against $HOST
```
