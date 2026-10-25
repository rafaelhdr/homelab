# Hermes

[Hermes Agent](https://github.com/NousResearch/hermes-agent) as a container — one
gateway process, two peers, on `matrix.org`. Replaces the three systemd units
that used to run on a dedicated Hetzner box.

| Profile | Path | Role |
|---|---|---|
| *(host)* | `/opt/data` | Empty default profile. Multiplexing host + dashboard, **not an agent** |
| `ons-thuis` | `/opt/data/profiles/ons-thuis` | Household bot — grocery list, storeroom, family calendar |
| `root` | `/opt/data/profiles/root` | Ops hand — repo dependency updates |

Neither agent is "the main one". `~/.hermes` is Hermes' installation root, so
it is *always* the multiplexing host and its internal id is always `default` —
that role cannot be skipped or renamed (only given a display name). But it does
not have to hold an agent, so this one is deliberately empty: no Matrix bot, no
persona, no household data. Both real agents are named profiles beside each
other.

Both speak Xiaomi MiMo (`mimo-v2-flash`). The gateway **multiplexes**
(`gateway.multiplex_profiles` on the host), so one process serves every
profile. See
[Multi-profile gateways](https://hermes-agent.nousresearch.com/docs/user-guide/multi-profile-gateways).

## Tracked source vs live state

```
containerd/hermes/                      tracked — source of truth, in git
├── README.md                           this file
├── host/                               the empty default profile
│   ├── config.yaml.example             gateway.multiplex_profiles  → seeded
│   └── .env.example                    TZ + dashboard URL only     → seeded
├── ons-thuis/
│   ├── AGENTS.md                       tool instructions   → bind-mounted :ro
│   ├── SOUL.md                         persona             → bind-mounted :ro
│   ├── config.yaml.example             settings delta      → seeded copy
│   ├── cron-jobs.json.example          scheduled jobs      → seeded copy
│   └── .env.example                    secret *names*      → seeded copy
└── root/                               same five files

containerd/hermes-data/                 live state — gitignored, never commit
├── config.yaml, .env                   the host's (no secrets in .env)
├── logs/, gateway_state.json, installs/, cache/, skills/, plugins/
└── profiles/
    ├── ons-thuis/                     grocery.md, *-appointments.md,
    │                                   memories/, cron/, state.db*, sessions/
    └── root/                           its own config, .env, cron, state
```

`hermes-data/` rather than `hermes/` on purpose: tracked source and mutable state
would collide under the `DATA_ROOT=.` default. Keep `DATA_ROOT` pointing outside
the git tree on the server (see `../README.md`) and the split is unambiguous.

**Personas are bind-mounted, config is seeded.** `SOUL.md` and `AGENTS.md` are
read-only prompts Hermes never writes, so edits there go live on restart.
`config.yaml` and `cron/jobs.json` are *mutable* — Hermes migrates the former
(`_config_version`) and stamps run counters into the latter — so those must be
writable copies in `hermes-data/`, re-seeded by hand when you want to change
them.

## Ownership

Rootless containerd maps container UID *N* onto host `100000 + N - 1`, and that
mapping is fixed — no setting makes a bind-mounted file come out owned by your
host user. `HERMES_UID: 1000` is still worth having: it pins the container-side
UID so everything lands on host **100999**, the same subuid gitea's data uses.
Leave it out and the image's baked UID maps to a different subuid (109999),
which desyncs from a tree you have already handed over, and Hermes then refuses
to start with *"install state is not writable by this user"*.

The consequences, and the fix:

| File | Needs to be writable by | Mode |
|---|---|---|
| `grocery.md`, `*-appointments.md`, `memories/`, `state.db`, `installs/`, logs | the bot (`100999`) | owned by `100999` |
| `.env` (×3) | **both** — you edit it, the bot reads it | `0666` |

Anything you seed by hand is created as *you* and the bot cannot write it, so
hand the whole tree over once after seeding — and again whenever Hermes has
written new files as a different UID:

```bash
sudo chown -R 100999:100999 $DATA_ROOT/hermes-data
sudo chmod 0666 $DATA_ROOT/hermes-data/.env \
               $DATA_ROOT/hermes-data/profiles/ons-thuis/.env \
               $DATA_ROOT/hermes-data/profiles/root/.env
```


After that, edit `.env` as yourself (it stays `0666`) and everything else
through the bot or `sudo`. Hermes rewrites `.env` back to `0600`/`100999` on
boot and whenever `hermes config set` touches it, so it is worth re-checking
before an edit:

```bash
chmod 0666 $DATA_ROOT/hermes-data/.env \
           $DATA_ROOT/hermes-data/profiles/ons-thuis/.env \
           $DATA_ROOT/hermes-data/profiles/root/.env
```

## First run

Everything below runs from `containerd/`. `DATA_ROOT` is whatever `../.env`
sets it to (on the server, a directory outside any git tree).

### 1. Seed the config and cron files

```bash
D=$DATA_ROOT/hermes-data
mkdir -p $D/profiles/ons-thuis/cron $D/profiles/root/cron

# host (the empty default profile — gateway.multiplex_profiles lives here)
cp hermes/host/config.yaml.example       $D/config.yaml

# ons-thuis
cp hermes/ons-thuis/config.yaml.example    $D/profiles/ons-thuis/config.yaml
cp hermes/ons-thuis/cron-jobs.json.example $D/profiles/ons-thuis/cron/jobs.json

# root
cp hermes/root/config.yaml.example         $D/profiles/root/config.yaml
cp hermes/root/cron-jobs.json.example      $D/profiles/root/cron/jobs.json
```

### 2. Write the secrets

The host `.env` carries no secrets by design — only `HERMES_TIMEZONE` and
`HERMES_DASHBOARD_PUBLIC_URL`. The two agents each have their own:

```bash
cp hermes/host/.env.example       $D/.env
cp hermes/ons-thuis/.env.example $D/profiles/ons-thuis/.env
cp hermes/root/.env.example       $D/profiles/root/.env
chmod 0666 $D/.env $D/profiles/ons-thuis/.env $D/profiles/root/.env
```

> **Not `chmod 600`.** Under rootless nerdctl the container runs as the host's
> subuid (here `100999`), so a `0600` file you create as your own user is
> invisible to Hermes — and a `0600` file Hermes touches is invisible to you.
> `0666` is what makes both sides work. It is not a real exposure: `DATA_ROOT`'s
> parent is `0700`, so nothing else can reach the directory. See
> [Ownership](#ownership).

Then fill in, per profile:

| Variable | Value |
|---|---|
| `XIAOMI_API_KEY` | your MiMo key — **repeated in both** agent `.env` files (profiles share no secrets) |
| `MATRIX_USER_ID` | the bot's MXID on `matrix.org` |
| `MATRIX_ALLOWED_USERS` | who may talk to it, comma-separated |
| `MATRIX_ACCESS_TOKEN` / `MATRIX_DEVICE_ID` | **one device per profile** — see below |
| `MATRIX_RECOVERY_KEY` | the account's existing E2EE recovery key |
| `MATRIX_HOME_ROOM` / `MATRIX_ALLOWED_ROOMS` | the home/grocery room id for `ons-thuis`, the root room id for `root` |

Room ids: Element → room settings → Advanced → *Internal room ID*.

> **Xiaomi issues two kinds of key and they do not interoperate.** `sk-…` is
> pay-as-you-go on `api.xiaomimimo.com` (Hermes' default) and returns `402
> Insufficient account balance` unless topped up. `tp-…` is the flat token
> plan and is *only* accepted by `token-plan-sgp.xiaomimimo.com` — the same
> key gets `401 Invalid API Key` from the default endpoint. This deployment
> uses the token plan, so `XIAOMI_BASE_URL` in the `.env` is required, and
> `model.default` must be a name that plan actually serves (`mimo-v2.6-flash`,
> `mimo-v2.6-pro` — note `mimo-v2-flash` does not exist on either endpoint).
> Both are set in the `.example` files.

### 3. Mint one Matrix device per profile

Matrix is a per-credential platform — the multiplexer refuses to poll one token
from two profiles. Same bot account is fine, **different devices are not
optional**. Mint each one once and pin it, so restarts never mint more:

```bash
curl -sS -XPOST 'https://matrix.org/_matrix/client/v3/login' \
  -H 'Content-Type: application/json' \
  -d '{"type":"m.login.password","identifier":{"type":"m.id.user","user":"<MXID>"},"password":"<pw>","initial_device_display_name":"hermes-ons-thuis"}' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["access_token"], d["device_id"])'
```

Run it twice (`hermes-ons-thuis`, `hermes-root`) and drop each pair into the
matching `.env`. Old devices from earlier deploys pile up — clean them with
`remove-matrix-devices.yml` in the reference `hermes-deploy` repo when the list
gets long.

> **Matrix needs one extra install step.** The image ships `mautrix`, `olm` and
> `libolm`, so the imports work — but Hermes gates the platform on its own
> `pm` extras table, and without that resolved the gateway logs
> `Platform 'Matrix' requirements not met (pip install 'mautrix[encryption]')`
> and builds no adapter. Run this once after the first start:
>
> ```bash
> nerdctl exec hermes hermes pm install
> nerdctl compose restart hermes
> ```
>
> It installs into `/opt/data/installs/…`, so it survives container recreation
> — but re-run it after a **data** wipe, not after an image bump.

> **New devices cannot read old history.** With `MATRIX_RECOVERY_KEY` set, the
> bot self-signs its device on every startup, so clients will share *new*
> encryption sessions with it. Messages sent before it joined stay undecryptable
> (the log will show `no session with given ID`), and Element may still show the
> device as needing verification — Sessions → verify the bot's device if
> replies are slow to arrive.

### 4. Carry over the household state

From the old box. These four are the household's memory; everything else is
runtime state and should **not** come across (stale v0.16.0 schema, stale Matrix
device store):

```bash
scp root@<old-host>:'~hermes/hermes-grocery/{grocery.md,future-appointments.md,past-appointments.md}' \
      $DATA_ROOT/hermes-data/profiles/ons-thuis/
scp -r root@<old-host>:'~hermes/hermes-grocery/memories' $DATA_ROOT/hermes-data/profiles/ons-thuis/
```

Do **not** copy `state.db*`, `sessions/`, `platforms/`, `cron/jobs.json`, or
`config.yaml`.

### 5. DNS and start

AdGuard rewrite `hermes.internal` → whatever its `*.internal` neighbours
already answer (read one of `photos.internal` / `git.internal` and match it —
the literal has drifted before), alongside
`photos.internal` / `git.internal` / `dns.internal`. Then from the **repo root**
(no `-f` flags — the override file must be auto-discovered):

```bash
nerdctl compose up -d
```

### 6. Verify

```bash
nerdctl logs -f hermes
```

Look for the gateway claiming both Matrix devices and serving both profiles. Then
message the bot in its room and open `http://hermes.internal`.

## Upgrading

`image: docker.io/nousresearch/hermes-agent:<tag>` in
`../docker-compose.yml` — change the tag, `nerdctl compose up -d`. Check the
[changelog](https://github.com/NousResearch/hermes-agent/releases) first.
Hermes migrates its own `config.yaml`; if a release notes a schema change, diff
the seeded `config.yaml.example` against the new
[`cli-config.yaml.example`](https://github.com/NousResearch/hermes-agent/blob/main/cli-config.yaml.example)
and re-apply any deltas you care about.

## Deliberately not migrated

- **`gh` and the `rafaelhdr-bot` GitHub App.** The root profile's
  `monthly-repo-updates` cron job needs both, so it ships **disabled**
  (`enabled: false` in `root/cron-jobs.json.example`) and
  `root/AGENTS.md`'s token-renewal procedure is dormant. Add `gh` to the image
  and `GITHUB_APP_ID` + `github_app.pem` to `profiles/root/` to bring it back,
  then flip the job on.
- **Any model other than Xiaomi MiMo.** `XIAOMI_BASE_URL` is deliberately
  unset — Hermes uses Xiaomi's own endpoint.

## Dashboard

`http://hermes.internal` → the `hermes-dashboard` container on port 9119. It is
**not** published on the host and not on any public network: only Caddy reaches
it, over the compose network.

**Auth is mandatory, not a hardening extra.** Hermes refuses to bind the
dashboard to `0.0.0.0` unless an auth provider is registered, and a configured
`HERMES_DASHBOARD_PUBLIC_URL` requires auth *even when a reverse proxy is the
only thing reaching it*. There is no unauthenticated public-dashboard option —
the container exits with:

```
Refusing to bind dashboard to 0.0.0.0 — the auth gate engages on non-loopback
binds (0.0.0.0), but no auth providers are registered.
```

So both of these live in `host/.env` (the dashboard's home):

| Variable | Purpose |
|---|---|
| `HERMES_DASHBOARD_PUBLIC_URL` | must match the Caddy site name — it is what the HTTP Host / WebSocket Origin guard accepts, since `hermes.internal` never appears in the container's own bind address |
| `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` / `_PASSWORD` | activates the bundled basic-auth provider; generate the password with `openssl rand -base64 18 \| tr -d '/+=' \| head -c 20` |

`GET /` then answers `302 → /login`. `/api/status` stays public by design — it
carries no secrets and is what a health check should hit.

### Editing the personas

`AGENTS.md` and `SOUL.md` are read-only bind mounts of files in git. They do
**not** update in place: `rsync`/editors that replace the file give it a new
inode, and a running container stays bound to the old one. After changing them,
recreate (not just restart) to re-establish the mounts:

```bash
nerdctl compose up -d --force-recreate hermes hermes-dashboard caddy
```

Caddy has the same behaviour for its own `public.Caddyfile`, which is what makes
a new `*.internal` site silently look like it "doesn't work" — the change is on
disk but the container is still reading the previous inode.
