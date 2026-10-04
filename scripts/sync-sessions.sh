#!/usr/bin/env bash
# sync-sessions.sh — git-backed archive of goose sessions.
#
# Why this exists:
#   Goose stores sessions in a live SQLite DB (~/.local/share/goose/sessions/sessions.db,
#   with -wal/-shm). Mutagen must NEVER two-way sync that directory — two processes
#   writing the same DB = corruption. This script takes a *consistent* snapshot
#   (sqlite3 .backup, safe even while goose is running) and distributes it via git.
#
# Why snapshots are compressed:
#   The raw DB passed GitHub's 100MB hard file limit at ~187MB (328 sessions) and
#   every push was rejected by the pre-receive hook (GH001). Snapshots are stored
#   as sessions-<host>.db.zst instead — zstd -19 takes 187MB to ~36MB (5x), which
#   keeps the plain-git workflow with years of headroom. Legacy uncompressed
#   sessions-<host>.db snapshots are still accepted by restore/list.
#
# Usage:
#   sync-sessions.sh snapshot                # backup THIS machine's sessions -> git -> push
#   sync-sessions.sh pull                    # fetch latest snapshots from the archive
#   sync-sessions.sh restore [machine]       # replace THIS machine's sessions with a snapshot
#                                            #   (machine = mac | laptop; default: this host)
#   sync-sessions.sh list                    # show available snapshots
#
# Env overrides:
#   GOOSE_SESSIONS_ARCHIVE   archive repo location (default ~/.goose-sessions-archive)
#   GOOSE_SESSIONS_STORE     live sessions dir  (default ~/.local/share/goose/sessions)
#   GOOSE_SESSIONS_REMOTE    git remote         (default https://github.com/yitzhakbg/AnkiTov-Sessions.git)
set -euo pipefail

ARCHIVE_DIR="${GOOSE_SESSIONS_ARCHIVE:-$HOME/.goose-sessions-archive}"
STORE_DIR="${GOOSE_SESSIONS_STORE:-$HOME/.local/share/goose/sessions}"
REMOTE_URL="${GOOSE_SESSIONS_REMOTE:-https://github.com/yitzhakbg/AnkiTov-Sessions.git}"
HOST="$( (hostname -s 2>/dev/null || hostname) | tr '[:upper:]' '[:lower:]' | sed 's/\.local$//' | sed 's/\.//g' )"
SNAPSHOT="$ARCHIVE_DIR/sessions-${HOST}.db.zst"
ZSTD_LEVEL="-${GOOSE_SESSIONS_ZSTD_LEVEL:-19}"

# List snapshot files, compressed form first. Returns 0 even when there are none
# so callers can distinguish "empty archive" from "ls failed on a glob".
snapshot_files() {
  local f
  for f in "$ARCHIVE_DIR"/sessions-*.db.zst "$ARCHIVE_DIR"/sessions-*.db; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  return 0
}

need_zstd() {
  command -v zstd >/dev/null 2>&1 \
    || die "zstd is required to snapshot/restore compressed archives. Install: brew install zstd"
}

# Print the snapshot path for a machine key, preferring the compressed form and
# falling back to the legacy raw .db so old archives keep working.
snapshot_path() {
  local host="$1"
  if [ -f "$ARCHIVE_DIR/sessions-${host}.db.zst" ]; then
    printf '%s' "$ARCHIVE_DIR/sessions-${host}.db.zst"
  elif [ -f "$ARCHIVE_DIR/sessions-${host}.db" ]; then
    printf '%s' "$ARCHIVE_DIR/sessions-${host}.db"
  fi
}

say() { printf '\033[1;32m%s\033[0m\n' "$*"; }
info() { printf '\033[1;36m%s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

# Map friendly machine keys to the real snapshot base name derived from each
# host's OS hostname (lowercased, dots stripped).
#   Mac   hostname ybgMacMini.lan -> ybgmacmini
#   laptop hostname ybgXPS        -> ybgxps
# Accepts aliases so users can type natural names.
key_to_snapshot() {
  local k
  k="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d ' ' | tr '-' '_')"
  case "$k" in
    mac|macmini|mac_mini|ybgmacmini)      echo "ybgmacmini" ;;
    laptop|laptopxps|xps|ybgxps)         echo "ybgxps" ;;
    *)                                    echo "$k" ;;   # pass through already-normalized hostnames
  esac
}

ensure_archive() {
  if [ ! -d "$ARCHIVE_DIR/.git" ]; then
    info "First run: cloning archive from $REMOTE_URL"
    if ! git clone "$REMOTE_URL" "$ARCHIVE_DIR" 2>/dev/null; then
      info "Remote unreachable — initializing empty archive locally (push later)."
      git init "$ARCHIVE_DIR"
      git -C "$ARCHIVE_DIR" remote add origin "$REMOTE_URL"
      git -C "$ARCHIVE_DIR" config user.name  >/dev/null 2>&1 || git -C "$ARCHIVE_DIR" config user.name "$(git config --get user.name || echo 'goose-sessions')"
      git -C "$ARCHIVE_DIR" config user.email >/dev/null 2>&1 || git -C "$ARCHIVE_DIR" config user.email "$(git config --get user.email || echo 'goose-sessions@localhost')"
    fi
  fi
  # Keep the archive repo to compressed snapshots only. Uncompressed DBs breach
  # GitHub's 100MB limit; WAL/SHM sidecars are runtime noise, never archive data.
  # Merge (never overwrite) so a hand-maintained .gitignore keeps its entries.
  local gi="$ARCHIVE_DIR/.gitignore"
  touch "$gi"
  grep -qxF '*.db' "$gi" || cat >> "$gi" <<'EOF'

# --- sync-sessions.sh ---
# Snapshots are stored compressed (sessions-<host>.db.zst): a raw 187MB DB was
# rejected by GitHub's 100MB hard limit (GH001). Never commit an uncompressed DB.
*.db
# Interrupted .backup leftovers — never archive data.
*.tmp-*
EOF
}

snapshot() {
  ensure_archive
  need_zstd
  [ -f "$STORE_DIR/sessions.db" ] || die "No sessions.db found at $STORE_DIR"
  say "Snapshotting sessions from $HOST -> $SNAPSHOT"
  local raw; raw="$(mktemp -t goose-sessions-raw)"
  # .backup is the only safe way to copy a live WAL-mode DB. The raw copy stays
  # outside the archive repo so git never sees the uncompressed 100MB+ blob.
  sqlite3 "$STORE_DIR/sessions.db" ".backup '$raw'"
  local compressed; compressed="$(mktemp -t goose-sessions-zst)"
  zstd "$ZSTD_LEVEL" -f -q "$raw" -o "$compressed" 2>/dev/null \
    || die "zstd compression failed"
  mv -f "$compressed" "$SNAPSHOT"
  rm -f "$raw"
  say "  $(basename "$SNAPSHOT"): $(du -h "$SNAPSHOT" | cut -f1) (raw was $(du -h "$STORE_DIR/sessions.db" | cut -f1))"
  # A legacy raw snapshot for this host would be re-committed by `add -A` and
  # blow the GitHub 100MB limit again. Drop it; history keeps the old blob.
  if [ -f "$ARCHIVE_DIR/sessions-${HOST}.db" ]; then
    info "Removing legacy uncompressed snapshot sessions-${HOST}.db"
    rm -f "$ARCHIVE_DIR/sessions-${HOST}.db"
  fi
  git -C "$ARCHIVE_DIR" add -A
  if git -C "$ARCHIVE_DIR" diff --cached --quiet; then
    say "No changes since last snapshot — nothing to commit."
    return 0
  fi
  git -C "$ARCHIVE_DIR" commit -q -m "snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ) from $HOST"
  say "Committed. Pushing to origin..."
  # Surface git's stderr — the old `2>/dev/null` hid the real reason (a 100MB+
  # blob gets rejected by GitHub's pre-receive hook with no hint on our side).
  local err; err="$(mktemp -t goose-sessions-pusherr)"
  if git -C "$ARCHIVE_DIR" push origin HEAD 2>"$err"; then
    say "Pushed. Remote now has: $(git -C "$ARCHIVE_DIR" ls-remote --get-url origin)"
  else
    info "Push failed. Snapshot is safe locally — retry later with: $0 push"
    [ -s "$err" ] && sed 's/^/  /' "$err"
  fi
  rm -f "$err"
}

push() {
  ensure_archive
  say "Pulling any remote snapshots first (rebase), then pushing..."
  git -C "$ARCHIVE_DIR" pull --rebase origin HEAD 2>/dev/null || true
  git -C "$ARCHIVE_DIR" push origin HEAD
}

pull() {
  ensure_archive
  info "Fetching archive..."
  git -C "$ARCHIVE_DIR" pull --ff-only origin HEAD 2>/dev/null \
    || git -C "$ARCHIVE_DIR" pull --rebase origin HEAD \
    || info "Pull had conflicts — resolve manually in $ARCHIVE_DIR"
}

restore() {
  local src="${1:-$HOST}"
  src="$(key_to_snapshot "$src")"
  pull
  local snap avail; snap="$(snapshot_path "$src")"
  avail="$(snapshot_files | xargs -n1 basename | tr '\n' ' ')"
  [ -n "$avail" ] || avail="none"
  [ -n "$snap" ] && [ -f "$snap" ] || die "No snapshot for '$src'. Available: $avail"
  if pgrep -x goose >/dev/null 2>&1; then
    die "goose is running. Quit it first — restore replaces the live DB underneath it."
  fi
  [ -f "$STORE_DIR/sessions.db" ] && cp "$STORE_DIR/sessions.db" "$STORE_DIR/sessions.db.pre-restore"
  say "Restoring $(basename "$snap") -> $STORE_DIR/sessions.db"
  if [ "${snap%.zst}" != "$snap" ]; then
    need_zstd
    zstd -d -f -q "$snap" -o "$STORE_DIR/sessions.db" \
      || die "zstd decompression failed for $snap"
  else
    cp "$snap" "$STORE_DIR/sessions.db"
  fi
  rm -f "$STORE_DIR/sessions.db-wal" "$STORE_DIR/sessions.db-shm"
  say "Restored. Pre-restore DB saved as sessions.db.pre-restore (delete when happy)."
  # Foreign paths from the source machine will fail to load; fix them now.
  remap_paths
}

# Rewrite sessions.working_dir to paths that exist ON THIS machine.
# A synced DB carries the source machine's absolute paths (e.g. /Users/ybg/...
# on a Mac) which the GUI rejects as "Invalid directory path". For each distinct
# working_dir we walk up to the nearest existing ancestor; if none exists (e.g.
# a foreign home), we fall back to $HOME. Content is untouched — only the path.
remap_paths() {
  local db="$STORE_DIR/sessions.db"
  [ -f "$db" ] || die "No live DB at $db (run restore first)."
  say "Remapping working_dir to local paths in $db"
  cp "$db" "$db.pre-remap"
  # sqlite3 -cmd '.read' runs a file; build one UPDATE per distinct path.
  local tmp; tmp="$(mktemp)"
  while IFS= read -r wd; do
    [ -z "$wd" ] && continue
    local target="" p="$wd"
    if [ -d "$wd" ]; then
      target="$wd"
    else
      # walk up to nearest existing ancestor
      while [ -n "$p" ] && [ "$p" != "/" ]; do
        if [ -d "$p" ]; then target="$p"; break; fi
        p="$(dirname "$p")"
      done
      [ -z "$target" ] && target="$HOME"
    fi
    printf "UPDATE sessions SET working_dir='%s' WHERE working_dir='%s';\n" \
      "${target//\'/\'\'}" "${wd//\'/\'\'}" >> "$tmp"
  done < <(sqlite3 "$db" "SELECT DISTINCT working_dir FROM sessions ORDER BY working_dir;")
  if [ -s "$tmp" ]; then
    sqlite3 "$db" < "$tmp"
    say "Remapped. Preview (working_dir -> count):"
    sqlite3 "$db" "SELECT '  '||working_dir||'  ('||cnt||')' FROM (SELECT working_dir, COUNT(*) cnt FROM sessions GROUP BY working_dir ORDER BY cnt DESC);"
    say "Pre-remap DB saved as sessions.db.pre-remap (delete when happy)."
  else
    say "Nothing to remap."
  fi
  rm -f "$tmp"
}

list() {
  pull 2>/dev/null || true
  say "Snapshots available in $ARCHIVE_DIR:"
  local found f
  found="$(snapshot_files)"
  if [ -z "$found" ]; then
    say "  none yet — run '$0 snapshot' on a machine"
    return 0
  fi
  while IFS= read -r f; do
    [ -n "$f" ] && printf '  %s (%s)\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
  done <<< "$found"
}

usage() {
  echo "Usage: $0 {snapshot|pull|restore [machine]|remap|list|push}"
  echo "  snapshot              backup this machine's sessions -> zstd -> git -> push"
  echo "  pull                  fetch latest snapshots"
  echo "  restore [machine]     replace this machine's sessions (machine: mac|laptop)"
  echo "                        [auto-runs remap to fix foreign paths]"
  echo "  remap                 rewrite working_dir to existing local paths"
  echo "  list                  show available snapshots"
  echo "  push                  retry pushing local snapshots"
  exit 1
}

case "${1:-}" in
  snapshot) snapshot ;;
  pull)     pull ;;
  restore)  restore "${2:-$HOST}" ;;
  remap)    remap_paths ;;
  list)     list ;;
  push)     push ;;
  *)        usage ;;
esac
