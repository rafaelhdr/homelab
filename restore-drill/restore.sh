#!/usr/bin/env bash
# Restore the latest kopia snapshot of the Immich library into restore-drill/library.
#
# Requires the repository to already be connected (restore-drill/.kopia/repository.config) —
# that step needs the repo password interactively, so it's not done here. See SKILL.md.
#
# Retries on transient B2 errors (observed: "unexpected EOF" / "internal_error" on
# GetBlob during concurrent range-fetches). Verified during a live drill that the
# underlying blobs were intact (a plain `kopia blob show` of a "failed" blob matched
# its expected size exactly) — these are retry-exhaustion blips, not corruption, so
# resuming with --skip-existing is safe and won't re-download completed files.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

CONFIG_FILE=./.kopia/repository.config
SOURCE_PATH=/home/rafaelhdr/homelab/library
MAX_ATTEMPTS=15
RETRY_DELAY=15

if ! kopia repository status --config-file="$CONFIG_FILE" >/dev/null 2>&1; then
  echo "kopia repository not connected — run the connect command from SKILL.md first." >&2
  exit 1
fi

SNAPSHOT_ID=$(kopia snapshot list --all --json --config-file="$CONFIG_FILE" \
  | jq -r --arg path "$SOURCE_PATH" \
    '[.[] | select(.source.path == $path)] | sort_by(.startTime) | last | .rootEntry.obj // empty')
EXPECTED_FILES=$(kopia snapshot list --all --json --config-file="$CONFIG_FILE" \
  | jq -r --arg path "$SOURCE_PATH" \
    '[.[] | select(.source.path == $path)] | sort_by(.startTime) | last | .rootEntry.summ.files // empty')

if [ -z "$SNAPSHOT_ID" ]; then
  echo "No snapshots found for source path $SOURCE_PATH" >&2
  exit 1
fi

echo "Restoring latest snapshot $SNAPSHOT_ID ($EXPECTED_FILES files expected) into ./library ..."

# Verify against kopia's own restored+skipped tally, not an independent `find` scan of
# ./library — that directory doubles as the running Immich container's live data dir
# (backups/, uploads), so a rescan would false-positive on files Immich itself wrote
# after the fact (e.g. the "restore-point-*" safety dump Immich makes before a DB restore).
RESTORE_LOG=$(mktemp)
trap 'rm -f "$RESTORE_LOG"' EXIT

attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  echo "=== Attempt $attempt/$MAX_ATTEMPTS ($(date)) ==="
  if kopia snapshot restore "$SNAPSHOT_ID" ./library \
    --skip-existing --parallel=2 --config-file="$CONFIG_FILE" 2>&1 | tee "$RESTORE_LOG"; then
    echo "=== Restore command completed on attempt $attempt ==="
    break
  fi
  echo "=== Attempt $attempt failed, retrying in ${RETRY_DELAY}s ==="
  attempt=$((attempt + 1))
  sleep "$RETRY_DELAY"
done

if [ "$attempt" -gt "$MAX_ATTEMPTS" ]; then
  echo "Giving up after $MAX_ATTEMPTS attempts" >&2
  exit 1
fi

# e.g. "Restored 6 files, 20764 directories and 0 symbolic links (78 B), skipped 40967 (56.1 GB)."
SUMMARY=$(grep -E "^Restored [0-9]+ files" "$RESTORE_LOG" | tail -1)
RESTORED=$(echo "$SUMMARY" | grep -oE "^Restored [0-9]+" | grep -oE "[0-9]+")
SKIPPED=$(echo "$SUMMARY" | grep -oE "skipped [0-9]+" | grep -oE "[0-9]+")
TOTAL=$((${RESTORED:-0} + ${SKIPPED:-0}))

echo "kopia accounted for $TOTAL files (restored $RESTORED + skipped $SKIPPED); expected $EXPECTED_FILES."
if [ -n "$EXPECTED_FILES" ] && [ "$TOTAL" != "$EXPECTED_FILES" ]; then
  echo "WARNING: file count mismatch — restore may be incomplete." >&2
  exit 1
fi

echo "Restore verified complete."
