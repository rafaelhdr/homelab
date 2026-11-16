# GitHub CLI token renewal

> **Dormant.** `gh` and the `rafaelhdr-bot` GitHub App are deliberately not part
> of this container yet, so the procedure below has nothing to act on. It is
> kept verbatim so the profile is ready the day they land — see
> `containerd/hermes/README.md`. The `monthly-repo-updates` cron job is seeded
> disabled for the same reason.

`gh` authenticates via a GitHub App installation token that expires after 1 hour.
If a `gh` command fails with an auth error, run this to renew:

```bash
source /opt/data/profiles/root/.env
header=$(printf '{"alg":"RS256","typ":"JWT"}' | base64 | tr -d '=\n' | tr '/+' '_-')
now=$(date +%s)
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now-60))" "$((now+600))" "$GITHUB_APP_ID" \
  | base64 | tr -d '=\n' | tr '/+' '_-')
sig=$(printf '%s.%s' "$header" "$payload" \
  | openssl dgst -sha256 -sign /opt/data/profiles/root/github_app.pem | base64 | tr -d '=\n' | tr '/+' '_-')
jwt="${header}.${payload}.${sig}"

install_id=$(curl -sf \
  -H "Authorization: Bearer $jwt" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/app/installations \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

token=$(curl -sf -X POST \
  -H "Authorization: Bearer $jwt" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/${install_id}/access_tokens" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

printf '%s' "$token" | gh auth login --with-token --hostname github.com
```

After running this, retry the original `gh` command.

## GitHub App token permissions via `gh api`

The `gh api repos/<owner>/<repo>` endpoint (and `gh repo view --json permissions`) returns
unreliable `permissions` fields when authenticated with a **GitHub App installation token**
(`ghs_...` prefix). It may show `push: false`, `pull: false`, etc. even when the GitHub App
has read/write access to code and pull requests, and the actual git operations (push, PR create)
**succeed fine**.

**Do not trust these API fields to determine if a GitHub App can push or create PRs.**
Instead, attempt the actual operation — if the GitHub App has the permission granted in its
app settings, git operations will work even if the REST API metadata says otherwise.

## Homelab ops (MCP tools)

The `homelab` MCP server gives you service operations on the host: tools
appear prefixed as `mcp_homelab_*` — `list_services`, `service_status`,
`service_logs`, `service_start`, `service_stop`, `service_restart`, plus
`request_permission` and `refresh_permissions`. Use names from
`list_services` only; never invent one.

Everything is gated by an operator-approved allowlist. A refusal names the
missing grant — **never try to work around it** (no curl to the services, no
alternative paths). When you need a grant:

1. Call `request_permission` with the action, the service, and a concrete
   reason (what task needs it; why a narrower grant won't do).
2. Relay the PR link it returns to the operator and **stop there** — only the
   operator merges it. Do not merge it yourself, ever.
3. When the operator says the PR is merged, call `refresh_permissions` — it
   reports exactly which grants changed — then retry the original task.

`request_permission` and `refresh_permissions` are always allowed; you never
need a grant to ask for one. If a grant seems to be missing but the operator
says it was already merged, call `refresh_permissions` first — the policy is
cached and only updates on that call.

Operational rules:

- Read before acting: `list_services` first when asked to manage services.
- Respect dependencies. The tools do plain container operations with no
  ordering:
  - `gluetun` and `qbittorrent` share a network namespace — stopping gluetun
    kills qbittorrent too.
  - `database` / `redis` are Immich's data layer — stop or start them only
    together with `immich-server` (dependents first when starting, dependents
    first when stopping: immich-server before database/redis).
  - `hermes` is your own gateway — do not stop it while serving someone.
- When asked to "keep only a few services up", say what stays and what goes
  before stopping anything, and confirm the list if anything looks load-bearing
  (caddy, adguardhome, gitea).
