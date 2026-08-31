---
name: restore-drill
description: >
  Run a restore drill for the Immich photo library backed up by kopia to Backblaze
  B2 — connects kopia to the repository, restores the latest snapshot into
  restore-drill/library, brings up a throwaway Immich stack against it, and reports
  the local URL to verify in a browser. Use when the user asks to "restore drill
  Immich", "test the Immich backup", "verify the kopia backup works", or similar.
  Project-scoped to this repo only.
---

# Immich restore drill

Validates that the kopia → Backblaze B2 backup of Immich's library is actually
recoverable, end to end, on this local machine. See `AGENTS.md` → "Backups
(Immich)" for how the backup pipeline itself is wired (kopia timer, Immich's own
DB-dump cron, why they're offset 15 minutes apart).

All work happens inside `restore-drill/` — nothing here touches the production
k3s stack or the real `containerd/` Immich instance.

## What this restores automatically, and what it doesn't

Kopia only snapshots the library folder, not Postgres directly. But Immich's own
scheduled DB backup job writes `pg_dump` output into `library/backups/` inside
that same folder, so the dump rides along in the snapshot. This means:

- **Automated by this skill**: all library files (`upload/`, `thumbs/`,
  `encoded-video/`, `backups/`) restored, and a fresh Immich instance brought up
  against them.
- **Left for the user, in-browser**: replaying the newest `immich-db-backup-*.sql.gz`
  from `library/backups/` via Immich's own "Restore Your Library" wizard, which
  appears automatically on first load when it finds files but no DB. Don't script
  the `psql` restore directly — the wizard is the supported path and handles
  version/migration concerns kopia and this skill know nothing about.

## Steps

1. **Check prerequisites.**
   - `which kopia` — if missing, tell the user to install it themselves (they've
     preferred doing this manually before) and stop.
   - `restore-drill/keys.txt` — if missing, tell the user to
     `cp restore-drill/keys.txt.example restore-drill/keys.txt` and fill in
     `B2_BUCKET`, `B2_KEY_ID`, `B2_APPLICATION_KEY`, then stop. Never ask the
     user to paste these values into chat — they belong in the gitignored
     `keys.txt` only. This is the *only* manual input the drill needs.

2. **Generate the compose stack.**
   Run `restore-drill/setup.sh` — it derives `restore-drill/docker-compose.yml`
   from `containerd/docker-compose.yml` (the single source of truth for the
   Immich compose spec) via `sed`, renaming the project/containers/port so it
   can coexist with the real `containerd/` stack, and writes a throwaway `.env`
   with a fresh DB password (only on first run — reruns reuse the existing one
   so it still matches the `./postgres` volume). Don't hand-maintain a second
   compose file — always regenerate through this script so version bumps in
   `containerd/docker-compose.yml` can't silently drift out of sync here.

3. **Connect kopia to the repository, if not already connected.**
   Check with:
   ```
   kopia repository status --config-file=restore-drill/.kopia/repository.config
   ```
   If not connected, source `restore-drill/keys.txt` and print this command for
   the **user** to run themselves — it prompts interactively for the repository
   password, which must never be typed into chat or handled by Claude:
   ```
   cd restore-drill
   source keys.txt
   kopia repository connect b2 \
     --bucket="$B2_BUCKET" \
     --key-id="$B2_KEY_ID" \
     --key="$B2_APPLICATION_KEY" \
     --config-file=./.kopia/repository.config
   ```
   Stop and wait for the user to confirm they've run it before continuing.

4. **Restore the latest snapshot.**
   Run `restore-drill/restore.sh` in the background (it can take a long time —
   the library has been observed at ~56GB; expect this on a home connection).
   It already handles what a live drill surfaced as necessary:
   - Auto-selects the latest snapshot for the library path via `kopia snapshot
     list --all --json` + `jq` (don't hand-parse the plain-text list output).
   - Retries automatically (up to 15 attempts, 15s apart) on transient B2 errors
     (`unexpected EOF`, `internal_error` from GetBlob) — confirmed in a live run
     these are retry-exhaustion blips under concurrent range-fetches, not actual
     data corruption (a direct `kopia blob show` of an affected blob matched its
     expected size exactly).
   - Uses `--skip-existing` so retries and reruns don't re-download completed
     files.
   - Verifies completeness against kopia's own restored+skipped tally from its
     output, **not** an independent rescan of the target directory — that
     directory is also the live Immich container's data dir once step 5 runs, so
     a naive rescan false-positives on files Immich itself writes later (e.g. the
     `restore-point-*` safety dump it makes before a DB restore).

   If the script reports a mismatch after exhausting retries, stop and report it
   rather than proceeding to bring up Immich against a possibly-incomplete
   restore.

5. **Bring up the Immich stack.**
   From `restore-drill/`, try `nerdctl compose up -d` first (matches this repo's
   convention in `containerd/`). If nerdctl/containerd isn't usable (observed
   failure mode: rootless containerd not set up, `sudo` blocked in a sandboxed
   shell), fall back to `docker compose up -d` — same generated compose file,
   both read it identically.

6. **Wait for health**, don't just assume it's up:
   ```
   until curl -sf -o /dev/null http://localhost:2284/api/server/ping; do sleep 2; done
   ```
   Run this with a backgroundable wait rather than a blind fixed sleep.

7. **Report to the user:**
   - The URL: **http://localhost:2284**
   - That a fresh admin account is needed on first load, or — if files were found
     with no DB — the "Restore Your Library" wizard will appear; point them at
     the newest `restore-drill/library/backups/immich-db-backup-*.sql.gz` for the
     DB half of the restore.
   - Any warnings surfaced during the restore verification step.

## Notes

- `restore-drill/keys.txt`, `restore-drill/docker-compose.yml`,
  `restore-drill/.env`, `restore-drill/library/`, `restore-drill/postgres/`, and
  `restore-drill/.kopia/` are all gitignored — credentials, generated config, and
  restored photos/DB data never get committed. Only `setup.sh`, `restore.sh`, and
  `keys.txt.example` are checked into the repo.
- Safe to rerun this skill anytime — `setup.sh` reuses the existing `.env` rather
  than rotating the DB password, and `restore.sh` resumes via `--skip-existing`
  rather than re-downloading a fresh 50+GB each time.
