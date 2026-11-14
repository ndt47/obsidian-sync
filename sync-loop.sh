#!/bin/sh
# Guarded one-shot sync loop for Obsidian Headless on an NFS-mounted vault.
#
# Why a loop of one-shot `ob sync` and not `ob sync --continuous`:
# continuous mode learns about local changes only through fs.watch (inotify), and
# on an NFS client inotify sees only writes made on this host. Agents on other
# hosts (villa, chatsubo) write the vault over NFS, so those edits would sit
# unsynced until a restart. Each one-shot run rescans the vault against its
# state DB (adds, edits AND deletes) and exits cleanly after "Fully synced", so
# there is never a kill in the middle of a file write.
#
# Guards, checked before every run, because `ob` treats a file that is missing
# locally but present remotely as a LOCAL DELETE and pushes it to every device:
#   - the sentinel file must exist (an unmounted or empty mount fails this)
#   - the vault must hold at least MIN_FILES files
#   - $HOME/PAUSE must not exist (touch it to hold sync for maintenance)
set -u

VAULT=${VAULT_PATH:-/vault}
INTERVAL=${SYNC_INTERVAL:-60}
SENTINEL=${VAULT_SENTINEL:-wiki/Index.md}
MIN_FILES=${MIN_FILES:-50}
PAUSE_FILE=${HOME:-/state}/PAUSE
OB=${OB:-ob}

log() { echo "$(date -Is) sync-loop: $*"; }

last_state=""
say_once() {  # log a waiting state once, not every interval
  [ "$last_state" = "$1" ] && return
  last_state=$1
  log "$2"
}

trap 'log "stopping"; exit 0' TERM INT

log "vault=$VAULT interval=${INTERVAL}s sentinel=$SENTINEL min_files=$MIN_FILES"
while :; do
  if [ -e "$PAUSE_FILE" ]; then
    say_once paused "paused: $PAUSE_FILE exists; remove it to resume"
  elif [ ! -f "$VAULT/$SENTINEL" ]; then
    say_once nosentinel "GUARD: $VAULT/$SENTINEL missing (vault not mounted?); not syncing"
  elif [ "$(find "$VAULT" -type f -not -path '*/.*' 2>/dev/null | head -n "$MIN_FILES" | wc -l)" -lt "$MIN_FILES" ]; then
    say_once fewfiles "GUARD: fewer than $MIN_FILES files under $VAULT; not syncing"
  else
    out=$("$OB" sync --path "$VAULT" 2>&1)
    rc=$?
    if [ $rc -eq 3 ]; then
      say_once unconfigured "not set up yet: run ob login / sync-setup (see README); waiting"
    elif [ $rc -ne 0 ]; then
      last_state=""
      log "ob sync failed (exit $rc):"
      printf '%s\n' "$out"
    else
      # Quiet when nothing moved: only print runs that uploaded, downloaded or deleted.
      changes=$(printf '%s\n' "$out" | grep -E 'Upload complete|Downloaded|Deleting|Removing|Merg|Renaming|Restoring|Reverting|Rejected|Skipped|Ignoring|rror|ail' || true)
      [ "$last_state" != syncing ] && log "syncing" && last_state=syncing
      [ -n "$changes" ] && printf '%s\n' "$changes"
    fi
  fi
  sleep "$INTERVAL" &
  wait $!
done
