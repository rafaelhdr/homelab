# containerd / nerdctl

The homelab's containerd/nerdctl Compose stack (Immich, Gitea, Caddy, AdGuard, Jellyfin), as a first step in migrating this homelab off K3s/Helmfile. Independent of `k8s/`/`values/` — fresh Postgres, fresh library, not connected to the CNPG cluster or the `immich-library` PVC.

## Setup (Immich)

1. `rsync` your backed-up Immich library into `./library` (relative to this folder — hardcoded in `docker-compose.yml`, along with `./postgres` for the database).
2. Bring it up:

   ```bash
   nerdctl compose up -d
   ```

3. Open `http://<host>:2283` and create the admin account.

## Notes (Immich)

- `.env` holds `DB_PASSWORD` — gitignored, don't commit it.
- `docker-compose.yml` is copied from [immich-app/immich's release compose file](https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml). When bumping `IMMICH_VERSION`, diff against that file first and re-sync any changes (image digests, service definitions).
- Machine learning is enabled (CPU inference, no hardware acceleration configured) — unlike the k8s deployment, which has it disabled.
- `nerdctl compose` reads the same compose spec as `docker compose`; commands are otherwise identical (`nerdctl compose logs -f`, `nerdctl compose down`, etc).

## Gitea

Self-hosted Git service ([docs](https://docs.gitea.com/installation/install-with-docker/)), configured entirely from `docker-compose.yml` — SQLite on a bind mount, so no extra database service and nothing new in `.env`.

- **Web**: `http://git.internal` (Caddy → `gitea:3000`), also published directly on `:3000`.
- **SSH**: host port `2222` → container `22`. Host port 22 stays this machine's own `sshd`. `GITEA__server__SSH_PORT=2222` is set so clone URLs show the real port.
- **Data**: `./gitea` (relative to this folder) — git repos, the SQLite DB, and `gitea/conf/app.ini`, which holds Gitea's auto-generated `SECRET_KEY`/`INTERNAL_TOKEN`. Back this directory up and never commit it.
- **Registration** is disabled and the install wizard is locked (`INSTALL_LOCK=true`), so clone URLs are correct on first boot.

### First run

1. AdGuard: add a DNS rewrite `git.internal` → `192.168.51.17`, like `photos.internal`/`dns.internal`.
2. `nerdctl compose up -d`
3. Create the admin account — Gitea refuses to run its CLI as root, hence `-u git`:

   ```bash
   nerdctl exec -u git gitea gitea admin user create --admin \
     --username <you> --email <you@example.com> --password '<pw>' --must-change-password
   ```

4. Optional, on each machine you push from — hides the non-standard SSH port so
   `git clone git@git.internal:<you>/repo.git` carries no port in the URL:

   ```
   Host git.internal
       User git
       Port 2222
   ```

### Bumping the version

`image: docker.io/gitea/gitea:<version>` in `docker-compose.yml` — change the tag, then `nerdctl compose up -d`. Gitea migrates its own schema on start, so no manual DB step.
