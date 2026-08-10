# containerd / nerdctl

Immich running standalone on containerd via `nerdctl compose`, as a first step in migrating this homelab off K3s/Helmfile. Independent of `k8s/`/`values/` — fresh Postgres, fresh library, not connected to the CNPG cluster or the `immich-library` PVC.

## Setup

1. `rsync` your backed-up Immich library into `./library` (relative to this folder — hardcoded in `docker-compose.yml`, along with `./postgres` for the database).
2. Bring it up:

   ```bash
   nerdctl compose up -d
   ```

3. Open `http://<host>:2283` and create the admin account.

## Notes

- `.env` holds `DB_PASSWORD` — gitignored, don't commit it.
- `docker-compose.yml` is copied from [immich-app/immich's release compose file](https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml). When bumping `IMMICH_VERSION`, diff against that file first and re-sync any changes (image digests, service definitions).
- Machine learning is enabled (CPU inference, no hardware acceleration configured) — unlike the k8s deployment, which has it disabled.
- `nerdctl compose` reads the same compose spec as `docker compose`; commands are otherwise identical (`nerdctl compose logs -f`, `nerdctl compose down`, etc).
