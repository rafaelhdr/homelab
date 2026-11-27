# containerd / nerdctl

The homelab's containerd/nerdctl Compose stack (Immich, Gitea, Caddy, AdGuard, Jellyfin, Hermes, Plik, Multica) — the only deployment mechanism since the old K3s/Helmfile stack was removed in 2026-10.

## Setup (Immich)

1. `rsync` your backed-up Immich library into `./library` (under `DATA_ROOT` — see [Data root](#data-root); `./postgres` for the database).
2. Bring it up:

   ```bash
   nerdctl compose up -d
   ```

3. Open `http://<host>:2283` and create the admin account.

## Data root

Service data (Immich `library`/`postgres`, `adguard/`, `jellyfin/`, `gitea/`, `hermes-data/`, `plik/`, `multica/`) lives under `DATA_ROOT`, which defaults to `.` (this folder) so the stack stays standalone. On the server it points at a directory outside any git tree — set `DATA_ROOT=/home/rafaelhdr/homelab-data` in `.env` to keep live state out of clones (`git clean` can't touch it).

## Notes (Immich)

- `.env` holds `DB_PASSWORD` — gitignored, don't commit it.
- `docker-compose.yml` is copied from [immich-app/immich's release compose file](https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml). When bumping `IMMICH_VERSION`, diff against that file first and re-sync any changes (image digests, service definitions).
- Machine learning is enabled (CPU inference, no hardware acceleration configured).
- `nerdctl compose` reads the same compose spec as `docker compose`; commands are otherwise identical (`nerdctl compose logs -f`, `nerdctl compose down`, etc).

## Plik

Temporary file and text sharing ([source](https://github.com/root-gg/plik)): open the web UI on one device, upload a file or paste text, then open the link on another.

- **Web**: `http://share.internal` (Caddy → `plik:8080`). No host port is published, so Caddy is the only way in. AdGuard needs a DNS rewrite `share.internal` pointing at the same address as `photos.internal`/`git.internal`.
- **Auth**: optional. Anonymous uploads work, but uploads made while logged in are listed under **My uploads** on any device, so there's no link to pass around. Uploads expire after 30 days by default.
- **First login**: user `admin` is created on first start with a random password printed once in the logs: `nerdctl logs plik | grep -i password`. Log in and change it in the UI.
- **Data**: `./plik` (under `DATA_ROOT`): `files/` holds the uploads and `plik.db` holds the metadata. Never commit it.

## Multica

Issue tracker with AI coding agents as assignees ([source](https://github.com/multica-ai/multica), [self-hosting docs](https://github.com/multica-ai/multica/blob/main/SELF_HOSTING.md)). Three containers: `multica-backend` (Go API + WebSocket, runs its own migrations), `multica-frontend` (Next.js) and `multica-postgres` (pgvector/pg17). The server never runs agents itself. A `multica` daemon does that, on any machine where an agent CLI (Claude Code, Codex, …) is installed and logged in.

- **Web**: `http://kanban.internal`. Caddy sends `/ws` to the backend and everything else to the frontend. No host ports are published.
- **Secrets** (`.env`): `MULTICA_DB_PASSWORD` and `MULTICA_JWT_SECRET`, each `openssl rand -hex 32`. Compose refuses to start until both are set.
- **Login**: email + one-time code. No mail server is configured, so the code is written to the log: `nerdctl logs multica_backend 2>&1 | grep 'Verification code'`. Signup is open to anyone who can reach the site, and the first account creates the workspace.
- **Agents**: on the machine that runs them, install the CLI (`curl -fsSL https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.sh | bash`), then `multica setup self-host` and point it at `http://kanban.internal`. The runtime shows up under **Settings → Runtimes**.
- **Data**: `./multica` (under `DATA_ROOT`). `postgres/` holds the database and `uploads/` holds attachments. Never commit it.
- **Telemetry** is off (`DO_NOT_TRACK=1`). Upstream turns it on by default.

### First run

1. Add `MULTICA_DB_PASSWORD` and `MULTICA_JWT_SECRET` to `.env`.
2. AdGuard: DNS rewrite `kanban.internal`, same answer as `photos.internal`.
3. `nerdctl compose up -d`, then log in with the code from the backend log.

### Bumping the version

The backend and web images share one tag (`v0.13.0`). Change both together, diff `docker-compose.selfhost.yml` upstream for new required env, then `nerdctl compose up -d`.

## Gitea

Self-hosted Git service ([docs](https://docs.gitea.com/installation/install-with-docker/)), configured entirely from `docker-compose.yml` — SQLite on a bind mount, so no extra database service and nothing new in `.env`.

- **Web**: `http://git.internal` (Caddy → `gitea:3000`), also published directly on `:3000`.
- **SSH**: host port `2222` → container `22`. Host port 22 stays this machine's own `sshd`. `GITEA__server__SSH_PORT=2222` is set so clone URLs show the real port.
- **Data**: `./gitea` (relative to this folder) — git repos, the SQLite DB, and `gitea/conf/app.ini`, which holds Gitea's auto-generated `SECRET_KEY`/`INTERNAL_TOKEN`. Back this directory up and never commit it.
- **Registration** is disabled and the install wizard is locked (`INSTALL_LOCK=true`), so clone URLs are correct on first boot.

### First run

1. AdGuard: add a DNS rewrite `git.internal` → `100.82.83.52`, like `photos.internal`/`dns.internal`.
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

## Hermes

[Hermes Agent](https://github.com/NousResearch/hermes-agent) — an AI agent that lives in Matrix. One gateway process, two equal agents:

| Profile | Role | Matrix room |
|---|---|---|
| *(host)* | empty default profile — multiplexing host + dashboard, **not an agent** | — |
| `ons-thuis` | grocery list, storeroom, family calendar | the home/grocery room |
| `root` | repo dependency updates | the root room |

Neither agent is "the main one": `~/.hermes` is always the multiplexing host and cannot be renamed, but it is deliberately left empty so both real agents sit beside each other as named profiles. Both run Xiaomi MiMo (`mimo-v2-flash`) via the built-in `xiaomi` provider.

- **Web**: `http://hermes.internal` (Caddy → `hermes:9119`, the dashboard the gateway serves in-process when `HERMES_DASHBOARD=1`; login with the basic-auth user in `hermes/host/.env`). The dashboard publishes **no** host port — Caddy is the only route in. **Auth is mandatory**: Hermes refuses to bind `0.0.0.0` without an auth provider and requires auth whenever `HERMES_DASHBOARD_PUBLIC_URL` is set, even behind a reverse proxy. That URL must match the Caddy site name or the Host guard rejects requests. `GET /` answers `302 → /login`; `/api/status` is public by design.
- **Data**: `./hermes-data` (relative to this folder, under `DATA_ROOT`) — host `config.yaml`/`.env`, then `profiles/{ons-thuis,root}/` each holding their own config, `.env` secrets and Matrix device tokens, `state.db`, sessions, and the E2EE crypto store. Back it up; never commit it (gitignored).
- **Source**: `./hermes/` — `host/` (gateway settings), plus per-agent personas (`AGENTS.md`, `SOUL.md`, bind-mounted read-only) and `.example` files for the `config.yaml` / `cron/jobs.json` that Hermes keeps writable in `hermes-data/`.

Hermes runs two Matrix **devices** on one bot account, one per agent. The multiplexing gateway refuses to poll a single token from two profiles, so each gets its own `MATRIX_ACCESS_TOKEN` / `MATRIX_DEVICE_ID`. Pin both — restarting must never mint a fresh device.

The root profile's `monthly-repo-updates` cron job is seeded **disabled**: it needs `gh` and a GitHub App that are deliberately not in the image. See `hermes/README.md`.

### First run

1. Seed the config, cron and `.env` files into `hermes-data/` from the `.example` files under `hermes/` (host, then `profiles/ons-thuis/` and `profiles/root/`), then fill in the secrets (Xiaomi key, Matrix credentials, room ids). Steps in `hermes/README.md`.
2. Carry the household state over from wherever Hermes ran before, into `hermes-data/profiles/ons-thuis/`: `grocery.md`, `future-appointments.md`, `past-appointments.md`, `memories/`. Not `state.db`, `sessions/`, `platforms/` or `config.yaml`.
3. AdGuard: add a DNS rewrite `hermes.internal` → `100.82.83.52`, like `photos.internal`/`git.internal` (same answer as its neighbours — check what they resolve to and match, rather than trusting a literal here).
4. `nerdctl compose up -d`, then `nerdctl logs -f hermes` — expect both profiles served and both Matrix devices claimed.

### Bumping the version

`image: docker.io/nousresearch/hermes-agent:<version>` in `docker-compose.yml` — change the tag, then `nerdctl compose up -d`. Hermes migrates its own `config.yaml`. For a significant release, diff `hermes/*/config.yaml.example` against the new upstream [`cli-config.yaml.example`](https://github.com/NousResearch/hermes-agent/blob/main/cli-config.yaml.example) and re-apply the deltas.
