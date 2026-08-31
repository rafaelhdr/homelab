# AGENTS.md

## Project

Single-node K3s homelab managed with Helmfile. Runs on host `10.250.163.241` (node: `khadas`).

**Immich moved off this stack** — now runs standalone via containerd/nerdctl, see `containerd/README.md`. Its k8s manifests (`k8s/immich-*.yaml`, `values/immich.yaml`) and helmfile release were removed from this repo in 2026-08; the old `immich-library-pv`/`immich-database` k8s objects may still exist live in-cluster (not yet torn down) but are no longer managed here.

## Quick reference

| App | Namespace | Chart | Version | Access |
|---|---|---|---|---|
| CNPG | cnpg-system | cnpg/cloudnative-pg | — | operator |
| Jellyfin | jellyfin | jellyfin/jellyfin | 3.2.0 | `:30619` |
| Homepage | homepage | m0nsterrr/homepage (OCI) | 4.12.1 | `:31569` |
| qBittorrent | qbittorrent | raw manifest (no chart) | gluetun v3.41.1 / qbittorrent 5.2.3 | ClusterIP only, `kubectl port-forward` for WebUI |
| Radarr | radarr | raw manifest (no chart) | radarr 6.3.0.10514-ls312 | `:<nodeport>` |
| Prowlarr | prowlarr | raw manifest (no chart) | prowlarr 2.5.2.5491-ls155 | `:<nodeport>` |

## Cluster

- **Type**: K3s single-node
- **Kubeconfig**: `~/kube/homelab` (env `KUBECONFIG=~/.kube/homelab`)
- **API server**: `https://10.250.163.241:6443`
- **kube-version suffix**: `+k3s1` (e.g. `1.33.6+k3s1`)
- **Node IP**: `10.250.163.241`, internal node: `khadas` (`192.168.51.15`)

## Deploy

```bash
kubectl apply -f k8s/   # PVs/PVCs, Postgres cluster, ConfigMaps, qBittorrent+gluetun Deployment (once)
helmfile apply           # all helm-based apps, or --selector name=<app>
```

All releases use `createNamespace: true` — namespaces are created automatically by helmfile. Raw manifests in `k8s/` must be applied first for PV/PVC/ConfigMap dependencies.

## Conventions

- **Service type**: `NodePort` (no ingress controller)
- **Storage**: `hostPath` PVs with `storageClassName: manual`, `ReclaimPolicy: Retain`, split across two physical disks on `khadas` — see [External storage](#external-storage-mntstorage) below
- **Chart versions**: pinned explicitly in `helmfile.yaml`
- **Config**: per-app values in `values/<app>.yaml`
- **Raw manifests**: `k8s/` for PVs, PVCs, Postgres clusters, and ConfigMaps

## External storage (`/mnt/storage`)

`khadas`'s root disk is small (~28Gi), so bulk media lives on a separate external SSD/NVMe (USB-attached), mounted at `/mnt/storage` via `/etc/fstab` (UUID-pinned, `nofail`, `x-systemd.device-timeout=10` so boot doesn't hang if USB enumeration is slow).

**On `/mnt/storage`** (bulk media only):
```
/mnt/storage/
├── immich/library              # orphaned — was immich-library-pv, Immich now runs via containerd/nerdctl
├── jellyfin/media               # jellyfin-media-pv
└── shared-downloads/
    ├── downloads/                # qbittorrent-downloads-pv AND part of radarr-data-pv
    └── movies/                   # part of radarr-data-pv AND jellyfin-radarr-movies-pv (read-only)
```

**Radarr mounts `shared-downloads` as one PV** (`radarr-data-pv`, at `/data` in the container → `/data/downloads`, `/data/movies`) instead of separate `movies`/`downloads` PVs — required for hardlinking to work, see the gotcha below. Scoped to just `shared-downloads` (not all of `/mnt/storage`) specifically so Radarr's container can't see Immich/Jellyfin's directories — qBittorrent mounts only the narrower `shared-downloads/downloads` for the same reason (it never touches `movies`).

**Still on the root disk** (`/srv/<app>/...`, unchanged): all `*-config` PVs (`jellyfin-config`, `qbittorrent-config`, `radarr-config`, `prowlarr-config`), `planka-data`, and the CNPG Postgres PVCs (`local-path` StorageClass, includes the now-orphaned `immich-database` cluster). Small, low-volume, and kept independent of the USB device's reliability.

Migrated from `/srv/<app>/...` to `/mnt/storage/...` in 2026-08 once the external disk was added — old `/srv/<app>/{library,media,movies,downloads}` paths no longer exist.

## Service notes

### CNPG

Postgres operator. Version unpinned, runs latest stable.

### Jellyfin

Port `8096`. Uses `jellyfin-config` (5Gi at `/srv/jellyfin/config`) and `jellyfin-media` (250Gi at `/mnt/storage/jellyfin/media`, see [External storage](#external-storage-mntstorage)) via the chart's `persistence` block.

**Also mounts Radarr's movie library read-only**, via the chart's generic `volumes`/`volumeMounts` in `values/jellyfin.yaml` (not the fixed `persistence.media` slot) — `jellyfin-radarr-movies` PVC → `jellyfin-radarr-movies-pv` → hostPath `/mnt/storage/shared-downloads/movies`, mounted at `/radarr-movies` in the container. Deliberately a *second*, separate mount rather than folding it into `jellyfin-media` or hardlinking: Jellyfin only ever reads these files, so there's no duplication/lifecycle problem to solve the way there was for qBittorrent↔Radarr — it just needs to see the same directory Radarr organizes into. Add `/radarr-movies` as an additional folder on a Movies library in Jellyfin's dashboard (Libraries → Add Media Library, or edit the existing one) to make it show up.

### Homepage

**Chart source**: OCI registry `ghcr.io/m0nsterrr/helm-charts/homepage`. Not a regular Helm repo — uses `oci: true` in helmfile. The `url` field must NOT include `oci://` prefix (helmfile adds it, double-prefix breaks it).

```
url: ghcr.io/m0nsterrr/helm-charts
oci: true
```

**Config split across two files**:
- `values/homepage.yaml` — chart values (allowed hosts, service, RBAC, volume mounts)
- `k8s/homepage-config.yaml` — ConfigMap with `services.yaml`, `settings.yaml`, `widgets.yaml`

**Homepage doesn't support wildcard `*` in multi-value `HOMEPAGE_ALLOWED_HOSTS`**. The chart generates a comma-separated list from internal FQDNs + `config.allowedHosts`. Adding `*` to the list doesn't work — Homepage treats `*` only when it's the sole value. The chart has no mechanism to set it to just `*` because it always prepends internal FQDNs.

**Workaround**: Add explicit hosts to `config.allowedHosts`, including the NodePort (e.g. `10.250.163.241:31569`). The NodePort changes on reinstall — update this value after each deploy.

**Dashboard config** (services, settings, widgets) is in `k8s/homepage-config.yaml` as a ConfigMap mounted into `/app/config/`.

### qBittorrent (behind gluetun VPN)

Not a helm release — deployed as a raw two-container Deployment in `k8s/qbittorrent.yaml` (gluetun, qbittorrent; plus `k8s/qbittorrent-namespace.yaml` and `k8s/qbittorrent-storage.yaml`), because the gluetun-sidecar pattern is just a Deployment spec, not something worth a chart for one app. All containers in a pod already share a network namespace in Kubernetes, so qBittorrent's traffic is routed through gluetun for free — no `network_mode: service:` trick needed like in Docker Compose.

- **VPN**: gluetun (`ghcr.io/qdm12/gluetun`), provider ProtonVPN, WireGuard. Note the project's GitHub org was renamed from `qdm12` to `passteque` (same repo, same history/stars — GitHub auto-redirects); image name (`qmcgaw/gluetun` / `ghcr.io/qdm12/gluetun`) is unchanged.
- **Torrent client**: `lscr.io/linuxserver/qbittorrent`, chosen over Transmission/Deluge — most stable under load and has the largest ecosystem of gluetun sidecar examples in the community.
- **Port forwarding**: intentionally not configured (no port-sync sidecar). Simpler and more stable; costs some seeding/upload throughput. Add a port-forward-sync sidecar later if that matters. Note: `PORT_FORWARD_ONLY=on` *is* still set on the gluetun container — for ProtonVPN in gluetun this is actually a server-selection filter (restricts to P2P-capable servers), not the sync feature. Without it gluetun can land on a non-P2P ProtonVPN server and silently block torrent traffic.
- **Requires before first deploy**: a `gluetun-secret` K8s Secret with key `wireguardPrivateKey`, generated from ProtonVPN's account page (Downloads → WireGuard configuration → extract `PrivateKey` from the generated `.conf`). Not stored in this repo.
  ```bash
  kubectl create secret generic gluetun-secret -n qbittorrent \
    --from-literal=wireguardPrivateKey='<key-from-protonvpn>'
  ```
- **Storage**: `qbittorrent-config` (1Gi, hostPath `/srv/qbittorrent/config`) and `qbittorrent-downloads` (100Gi placeholder, hostPath `/mnt/storage/downloads`, see [External storage](#external-storage-mntstorage)) — adjust the downloads PV size in `k8s/qbittorrent-storage.yaml` to match actual free disk before applying.
- **Firewall**: gluetun blocks all inbound traffic by default; `FIREWALL_INPUT_PORTS=8080` on the gluetun container allows the WebUI through. If you change qBittorrent's `WEBUI_PORT`, update this too. This is required even though the Service is ClusterIP-only (see below) — Radarr's connection to the WebUI/API is still an inbound packet from gluetun's point of view.
- **Service is ClusterIP-only, no NodePort**: qBittorrent's WebUI is deliberately not exposed outside the cluster. Radarr reaches it via `qbittorrent.qbittorrent.svc.cluster.local:8080`; for manual browser access use `kubectl port-forward -n qbittorrent svc/qbittorrent 8080:8080`.
- **VPN port forwarding**: `VPN_PORT_FORWARDING=on` plus `VPN_PORT_FORWARDING_UP_COMMAND`/`_DOWN_COMMAND` call qBittorrent's own API at `http://127.0.0.1:8080` (same pod, same netns) to set its listening port whenever ProtonVPN assigns or rotates a forwarded port — this is gluetun's native mechanism, so no extra sidecar is needed for it. **Requires** qBittorrent's WebUI "Bypass authentication for clients on localhost" (`WebUI\LocalHostAuth=false` in `qBittorrent.conf`) enabled on the config PVC — same not-in-git caveat as the Host-header fix below; this has not yet been applied, so the up/down command will get a 401 until it is.
- **Server list freshness**: `UPDATER_PERIOD=480h` makes gluetun periodically refresh its ProtonVPN server list through the tunnel (~20 days, per gluetun's "no less than 360h" guidance) instead of relying solely on whatever server list shipped baked into the image.
- **Health check**: gluetun's built-in health server must bind `0.0.0.0` (`HEALTH_SERVER_ADDRESS=0.0.0.0:9999`), not the `127.0.0.1` default — Kubernetes' `httpGet` liveness probe always targets the pod IP, never `localhost`, so a loopback-only bind causes an endless restart loop (each restart re-negotiates the VPN and briefly drops the firewall rules, disrupting the WebUI).
- **Known gotcha**: qBittorrent's WebUI Host header validation rejects requests whose `Host` doesn't match its allowlist (confirmed: ClusterIP got 401, `Host: localhost` got 200), even `WebUI\ServerDomains=*` doesn't cover numeric IP:port hosts. Fix is `WebUI\HostHeaderValidation=false` in `qBittorrent.conf` on the config PVC — not in git, so a fresh volume needs this reapplied. To edit it safely: scale the deployment to 0 first (qBittorrent rewrites its own config on save/exit, so editing it while the process is running races the process and gets overwritten), edit via a temporary pod mounting `qbittorrent-config`, then scale back up.
- **Known gotcha**: gluetun needs `/dev/net/tun` on the host node. If the gluetun container fails to start, run `modprobe tun` on the node (`khadas`) and make it persistent (e.g. add `tun` to `/etc/modules-load.d/`).
- **Known gotcha (considered, then ruled out) — a `netfix` sidecar**: opening `FIREWALL_INPUT_PORTS=8080` makes gluetun add its own policy-routing rule (`ip rule: from <podIP> lookup <table>`) so WebUI reply traffic skips the VPN tunnel and goes back out the pod's normal interface — necessary, since the WebUI must reply from the pod's real IP, not the tunnel IP. This was suspected to be too broad and to also catch qBittorrent's own outbound P2P/tracker/DHT traffic, kicking it out of the tunnel and getting it firewalled (symptom: `"Operation not permitted"`, torrents stuck in `stalledDL` with 0 peers). A three-container `netfix` sidecar (CONNMARK + custom policy routing, re-applied on a loop) was built to narrow the rule down to only genuine inbound WebUI requests — but it was never actually validated before being shelved mid-debug. A clean retest without it showed the rule is only ever hit by reply traffic on already-established connections: `tun0`/`eth0` packet counts matched almost exactly (1:1) for outbound traffic during an active download, and the firewall's `OUTPUT` DROP counter barely moved — i.e. qBittorrent's P2P traffic was fully tunneled, no leak, no `netfix` required. If the `stalledDL`/`Operation not permitted` symptom ever resurfaces, this rule is the mechanism to revisit, but reach for something smaller first (e.g. gluetun's `/iptables/post-rules.txt` custom-rules hook) before rebuilding a whole CONNMARK sidecar.

### Radarr (NOT behind gluetun, by design)

Movie management: watches for wanted movies, searches indexers/trackers, sends the result to qBittorrent, then renames/moves the finished file into the library. Raw manifest (`k8s/radarr.yaml`, `k8s/radarr-namespace.yaml`, `k8s/radarr-storage.yaml`) — single container, no chart needed.

- **Deliberately not routed through the gluetun sidecar** that qBittorrent uses. Only the torrent client's peer-to-peer traffic needs VPN protection; Radarr's own traffic (TMDB metadata lookups, indexer/tracker API calls, talking to Jellyfin/Bazarr/notification services) is normal outbound HTTPS with nothing to hide from a swarm. Putting Radarr in the same pod as gluetun would force *all* of that traffic through the VPN for no benefit, and every new integration (a new indexer, a new notification webhook) would require another `FIREWALL_INPUT_PORTS`/allowlist entry on gluetun just to keep working. It would also put Radarr's own WebUI behind the same inbound firewall qBittorrent's WebUI fights with (see the Host-header gotcha above).
- Radarr talks to qBittorrent over the cluster network as a normal Download Client: host `qbittorrent.qbittorrent.svc.cluster.local`, port `8080`. This works even though qBittorrent's pod is VPN-routed, because gluetun's firewall only filters *inbound* connections to the ports listed in `FIREWALL_INPUT_PORTS` (already `8080` for the WebUI/API) — it doesn't care that the caller is another in-cluster pod rather than a browser.
- **Storage**: `radarr-config` (1Gi, hostPath `/srv/radarr/config`) and `radarr-data` (300Gi placeholder, hostPath `/mnt/storage/shared-downloads`, mounted at `/data` in the container → `/data/downloads`, `/data/movies`, adjust size to actual free disk). qBittorrent's `qbittorrent-downloads-pv` points at `/mnt/storage/shared-downloads/downloads` independently, so both apps see the same completed-download files without Radarr needing broader access than `shared-downloads`.
- **Avoiding duplicate storage on import — must be ONE shared mount, not two**: Radarr's Settings → Media Management → "Use Hardlinks instead of Copy" only avoids duplicating a file if the source (`/downloads`) and destination (`/movies`) are part of the *same bind mount* inside the container. Confirmed by hitting this directly: with `radarr-movies` and `radarr-downloads` as two separate PVs/PVCs (even though both hostPaths lived on the identical physical disk), every import silently fell back to a full copy — `ln` inside the Radarr container failed with `Cross-device link` (`EXDEV`), because Kubernetes bind-mounts each `hostPath` volume independently and the kernel refuses hardlinks across separate mounts, regardless of the underlying disk being the same. Fixed by giving Radarr a single `radarr-data-pv` covering just `/mnt/storage/shared-downloads` (not all of `/mnt/storage` — kept narrow so Radarr can't see Immich/Jellyfin's directories) mounted once at `/data`, so `/data/downloads` and `/data/movies` share one mount and hardlinks actually work. **Don't reintroduce split mounts for anything that needs to hardlink across them.**
  - **Manual follow-up required in Radarr's WebUI after this change** (not in git): update the Root Folder from `/movies` to `/data/movies`, add a Remote Path Mapping for the qBittorrent download client (qBittorrent still reports paths as `/downloads/...`; Radarr now sees the same files at `/data/downloads/...`), and re-point/rescan existing movie entries so Radarr's DB matches the new path — the files themselves haven't moved, only the container path prefix changed.
- **First-time setup**: open the WebUI, add the qBittorrent download client (see above), add at least one indexer (or point Radarr at a Prowlarr instance if one gets added later), then add movies from the search page — Radarr searches indexers, sends the chosen release to qBittorrent, and imports the finished file into `/movies` once qBittorrent reports it complete.

### Prowlarr (indexer manager, NOT behind gluetun)

Manages torrent/Usenet indexers in one place and syncs them into Radarr (and Sonarr, if added later) via Radarr's API, instead of configuring each indexer inside every *arr app separately. Raw manifest (`k8s/prowlarr.yaml`, `k8s/prowlarr-namespace.yaml`, `k8s/prowlarr-storage.yaml`) — single container, config-only storage (no movies/downloads volumes, Prowlarr never touches media files).

- **Not routed through gluetun**, same reasoning as Radarr: Prowlarr's traffic is indexer search/API calls, not P2P traffic — nothing here needs VPN protection, and routing it through the sidecar would add firewall-config overhead for no benefit.
- **Storage**: `prowlarr-config` only (1Gi, hostPath `/srv/prowlarr/config`). Unlike Radarr's extra `/movies` volume, this hostPath got auto-chowned to the `PUID`/`PGID` user (`1000:1000`) by the linuxserver image's own s6-init on first boot — no manual `chown` needed. (The gotcha we hit with Radarr's `/movies` only affects *non-standard* extra volumes; linuxserver images fix up the conventional `/config` mount themselves.)
- **Wiring to Radarr**: in Prowlarr, Settings → Apps → add Radarr with URL `http://radarr.radarr.svc.cluster.local:7878` and Radarr's API key (`/config/config.xml` inside the Radarr pod, or Settings → General in Radarr's WebUI). Then add indexers in Prowlarr — it pushes them to Radarr automatically, no per-indexer setup inside Radarr itself.

## Backups (Immich)

Kopia snapshots `/home/rafaelhdr/homelab/library` (Immich's `UPLOAD_LOCATION`) every 4h via a systemd timer/service pair templated by Ansible (`ansible/templates/kopia-immich-backup.{service,timer}.j2`, applied via `just deploy`). Only the library folder is snapshotted — Postgres isn't backed up directly by kopia.

Immich's own scheduled DB backup (Administration → Settings → Backup in the UI, not stored in git) writes `pg_dump` output into `library/backups/`, which rides along inside the same kopia snapshot since it's just another file under the snapshotted path — that's how the Postgres state actually gets backed up, not via kopia talking to the DB.

**Cadence is intentionally offset, not identical.** Immich's DB backup cron is `0 */4 * * *` — the same 4h grid as kopia. Kopia's timer runs 15 minutes later (`OnCalendar=*-*-* 0/4:15:00`) so it reliably picks up the dump that was *just* written instead of racing it: firing both at `:00` risks kopia grabbing yesterday's dump file and not catching the fresh one until the next cycle, four hours later.

**After editing the timer/service templates**, `just deploy` alone is sufficient — `daemon-reload` doesn't restart an already-running timer with the old `OnCalendar` baked in, so the playbook notifies a handler (`Restart kopia-immich-backup timer`) whenever the template content actually changes, restarting it automatically. No manual `systemctl restart` needed after a normal deploy.

**Restore drills**: `restore-drill/` is a throwaway Immich instance for testing recovery locally, driven by the project-scoped `restore-drill` skill (`.claude/skills/restore-drill/`) plus two checked-in scripts. `setup.sh` generates `docker-compose.yml` from `containerd/docker-compose.yml` (the single source of truth for the compose spec — never hand-duplicated) and a throwaway `.env` with a fresh DB password; `restore.sh` connects to the already-authenticated kopia repository and restores the latest snapshot into `restore-drill/library`. B2 credentials (bucket, key ID, application key) live in `restore-drill/keys.txt` (gitignored, template at `keys.txt.example`) — deliberately separate from the compose `.env`, and the repository *password* itself is never stored anywhere, only supplied interactively when connecting kopia. The skill restores the snapshot, brings the stack up, then leaves the DB half to Immich's own "Restore Your Library" wizard, which replays the newest `library/backups/immich-db-backup-*.sql.gz` against the fresh Postgres container. `restore-drill/keys.txt`, `docker-compose.yml`, `.env`, `library/`, `postgres/`, and `.kopia/` are all gitignored — credentials, generated config, and restored data never get committed.

## Checking for updates

Check latest available chart versions against the pinned versions in `helmfile.yaml`:

```bash
# Update repo indexes first
helm repo update

# Check latest version for each pinned chart
helm search repo jellyfin/jellyfin --versions | head -5
helm search repo cnpg/cloudnative-pg --versions | head -5

# OCI chart (homepage) — list tags via crane or skopeo
crane ls ghcr.io/m0nsterrr/helm-charts/homepage | sort -V | tail -5
# or: skopeo list-tags docker://ghcr.io/m0nsterrr/helm-charts/homepage
```

Current pinned versions (update this table after bumping `helmfile.yaml`):

| App | Pinned | Chart |
|---|---|---|
| Jellyfin | 3.2.0 | jellyfin/jellyfin |
| CNPG | unpinned | cnpg/cloudnative-pg |
| Homepage | unpinned | m0nsterrr/homepage (OCI) |

After bumping a version in `helmfile.yaml`, run `helmfile apply --selector name=<app>` to deploy. Check the chart's release notes for breaking changes before upgrading.

## Directory structure

```
├── helmfile.yaml          # Repos + releases
├── k8s/
│   ├── homepage-config.yaml       # Homepage dashboard ConfigMap
│   ├── homepage-namespace.yaml    # (redundant with createNamespace: true)
│   ├── jellyfin-namespace.yaml
│   ├── jellyfin-storage.yaml      # PVs + PVCs
│   ├── qbittorrent-namespace.yaml
│   ├── qbittorrent-storage.yaml   # PVs + PVCs
│   ├── qbittorrent.yaml           # gluetun + qBittorrent Deployment, Service (no chart)
│   ├── radarr-namespace.yaml
│   ├── radarr-storage.yaml        # PVs + PVCs (config, shared /data mount for movies+downloads)
│   ├── radarr.yaml                # Radarr Deployment, Service (no chart, no VPN)
│   ├── prowlarr-namespace.yaml
│   ├── prowlarr-storage.yaml      # PV + PVC (config only)
│   └── prowlarr.yaml              # Prowlarr Deployment, Service (no chart, no VPN)
├── values/
│   ├── homepage.yaml
│   └── jellyfin.yaml
└── README.md
```
