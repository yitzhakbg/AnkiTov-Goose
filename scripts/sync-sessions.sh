#!/usr/bin/env bash
# sync-sessions.sh — git-backed archive of goose sessions.
#
# Why this exists:
#   Goose stores sessions in a live SQLite DB (~/.local/share/goose/sessions/sessions.db,
#   with -wal/-shm). Mutagen must NEVER two-way sync that directory — two processes
#   writing the same DB = corruption. This script takes a *consistent* snapshot
#   (sqlite3 .backup, safe even while goose is running) and distributes it via git.
#
# Usage:
#   sync-sessions.sh snapshot                # backup THIS machine's sessions -> git -> push
#   sync-sessions.sh pull                    # fetch latest snapshots from the archive
#   sync-sessions.sh restore [machine]       # replace THIS machine's sessions with a snapshot
#                                            #   (machine = mac-mini | ybgxps; default: this host)
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
HOST="$(hostname -s 2>/dev/null || hostname | tr '[:upper:]' '[:lower:]' | sed 's/\.local$//' | sed 's/\.//g')"
SNAPSHOT="$ARCHIVE_DIR/sessions-${HOST}.db"

say() { printf '\033[1;32m%s\033[0m\n' "$*"; }
info() { printf '\033[1;36m%s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

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
}

snapshot() {
  ensure_archive
  [ -f "$STORE_DIR/sessions.db" ] || die "No sessions.db found at $STORE_DIR"
  say "Snapshotting sessions from $HOST -> $SNAPSHOT"
  # .backup is the only safe way to copy a live WAL-mode DB.
  sqlite3 "$STORE_DIR/sessions.db" ".backup '$SNAPSHOT'"
  git -C "$ARCHIVE_DIR" add -A
  if git -C "$ARCHIVE_DIR" diff --cached --quiet; then
    say "No changes since last snapshot — nothing to commit."
    return 0
  fi
  git -C "$ARCHIVE_DIR" commit -q -m "snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ) from $HOST"
  say "Committed. Pushing to origin..."
  if git -C "$ARCHIVE_DIR" push origin HEAD 2>/dev/null; then
    say "Pushed. Remote now has: $(git -C "$ARCHIVE_DIR" ls-remote --get-url origin)"
  else
    info "Push failed (offline / auth). Snapshot is safe locally — retry later with: $0 push"
  fi
}

push() {
  ensure_archive
  say "Pushing any unpushed snapshots..."
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
  src="$(printf '%s' "$src" | tr '[:upper:]' '[:lower:]')"
  pull
  local snap="$ARCHIVE_DIR/sessions-${src}.db"
  [ -f "$snap" ] || die "No snapshot for '$src'. Available: $(ls "$ARCHIVE_DIR"/sessions-*.db 2>/dev/null | xargs -n1 basename || echo none)"
  if pgrep -x goose >/dev/null 2>&1; then
    die "goose is running. Quit it first — restore replaces the live DB underneath it."
  fi
  [ -f "$STORE_DIR/sessions.db" ] && cp "$STORE_DIR/sessions.db" "$STORE_DIR/sessions.db.pre-restore"
  say "Restoring $snap -> $STORE_DIR/sessions.db"
  cp "$snap" "$STORE_DIR/sessions.db"
  rm -f "$STORE_DIR/sessions.db-wal" "$STORE_DIR/sessions.db-shm"
  say "Restored. Pre-restore DB saved as sessions.db.pre-restore (delete when happy)."
}

list() {
  pull 2>/dev/null || true
  say "Snapshots available in $ARCHIVE_DIR:"
  ls -lh "$ARCHIVE_DIR"/sessions-*.db 2>/dev/null | awk '{print "  "$NF" ("$5") — "$6" "$7" "$8}' \
    || say "  none yet — run '$0 snapshot' on a machine"
}

usage() {
  echo "Usage: $0 {snapshot|pull|restore [machine]|list|push}"
  echo "  snapshot              backup this machine's sessions -> git -> push"
  echo "  pull                  fetch latest snapshots"
  echo "  restore [machine]     replace this machine's sessions (machine: mac-mini|ybgxps)"
  echo "  list                  show available snapshots"
  echo "  push                  retry pushing local snapshots"
  exit 1
}

case "${1:-}" in
  snapshot) snapshot ;;
  pull)     pull ;;
  restore)  restore "${2:-$HOST}" ;;
  list)     list ;;
  push)     push ;;
  *)        usage ;;
esac
