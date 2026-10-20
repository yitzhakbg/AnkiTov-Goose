#!/usr/bin/env bash
# =============================================================================
# env-deploy.sh — Goose/AnkiTov full-environment capture & deploy
# =============================================================================
# Purpose: redeploy the complete working environment (Goose + goose-related +
# AnkiTov + ankitov-related) on a fresh/lost/replacement machine.
#
# Design principle: git-backed things are CLONED, not copied. Only volatile
# state (configs, small DBs, schedules, launchd jobs) is captured into a
# bundle. Sessions DB is snapshotted by sync-sessions.sh (git snapshot archive)
# AND copied into the bundle, so a bundle alone is a complete restore point.
#
# Subcommands:
#   inventory              show every component: present? size? git state?
#   capture [DEST] [--light|--no-sessions-snapshot]
#                          build restorable bundle  (DEST default below)
#   push [BUNDLE]          upload newest (or named) bundle to gdrive:, then keep
#                          only the newest 2 bundles on the remote (standing policy)
#   restore BUNDLE         deploy bundle on a (new) machine — interactive
#   doctor                 health-check this machine against expectations
#
# Bundles land OUTSIDE the repos (default /Volumes/YBG1TB4Mac/goose-env-bundles)
# so they never pollute git trees. Secrets (secrets.yaml, AnkiTov/.goose/secrets)
# ARE included, tarred with 700/600 perms — protect the bundle.
#
# This script lives in the AnkiTov-Goose repo (github.com/yitzhakbg/AnkiTov-Goose)
# which is mutagen-synced to ybgxps — it survives machine loss.
# =============================================================================
set -euo pipefail

VERSION="2026-10-11.1"
HOST="$( (hostname -s 2>/dev/null || hostname) | tr '[:upper:]' '[:lower:]' | sed 's/\.local$//;s/\.//g' )"
OS="$(uname -s)"
HOME_CONFIG="$HOME/.config/goose"
HOME_DATA="$HOME/.local/share/goose"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/Volumes/YBG1TB4Mac}"        # override on other machines
GOOSE_WS="${GOOSE_WS:-$WORKSPACE_ROOT/AnkiTov-goose}"          # goose repo workspace
ANKITOV="${ANKITOV:-$WORKSPACE_ROOT/AnkiTov}"                  # main repo
ANKITOV_C="${ANKITOV_C:-$WORKSPACE_ROOT/AnkiTov-C}"            # AnkiTov-C checkout (separate remote)
BUNDLE_ROOT="${BUNDLE_ROOT:-$WORKSPACE_ROOT/goose-env-bundles}"
SESSIONS_SCRIPT="${SESSIONS_SCRIPT:-$GOOSE_WS/scripts/sync-sessions.sh}"
SESSIONS_ARCHIVE="${GOOSE_SESSIONS_ARCHIVE:-$HOME/.goose-sessions-archive}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[X]${NC} $*" >&2; }
step() { echo -e "${BLUE}──${NC} $*"; }

du_h() { du -sh "$1" 2>/dev/null | cut -f1; }
sha256() { if command -v shasum >/dev/null; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }

# ── component definitions ────────────────────────────────────────────────────
# name | kind | path(s) | tar-excludes
REPOS="AnkiTov:$ANKITOV AnkiTov-C:$ANKITOV_C AnkiTov-Goose:$GOOSE_WS"

launchd_files() {
  [ "$OS" = "Darwin" ] || return 0
  ls ~/Library/LaunchAgents/ 2>/dev/null | grep -E '^(com\.(ankitov|user\.goose)|user\.ybg)' || true
}

# ── inventory ────────────────────────────────────────────────────────────────
cmd_inventory() {
  echo "════════ env-deploy inventory — host=$HOST os=$OS version=$VERSION ════════"
  step "tools"
  for t in goose mutagen zstd jj bun opencode sqlite3 git; do
    p="$(command -v $t || true)"
    [ -n "$p" ] && ok "$t → $p $( [ "$t" = goose ] && goose --version 2>/dev/null | head -1 )" \
                 || warn "$t MISSING"
  done
  step "goose config/data (volatile, captured by 'capture')"
  for d in "$HOME_CONFIG" "$HOME_CONFIG/custom_providers" "$HOME_CONFIG/memory" \
           "$HOME_CONFIG/.headroom" "$HOME_CONFIG/recipes" "$HOME_DATA/apps" \
           "$HOME_DATA/model_catalog" "$HOME_DATA/models" "$HOME_DATA/moose" \
           "$HOME_DATA/recipes" "$HOME_DATA/scheduled_recipes" \
           "$HOME/.config/opencode"; do
    [ -e "$d" ] && ok "$(du_h "$d")  $d" || warn "missing  $d"
  done
  echo -e "    /tmp symlinks (volatile!):"
  for f in projects.json schedule.json; do
    if [ -e "$HOME_DATA/$f" ]; then
      tgt="$(readlink "$HOME_DATA/$f" 2>/dev/null || echo "(regular file)")"
      [ -f "$HOME_DATA/$f" ] && ok "$HOME_DATA/$f → $tgt" || warn "$HOME_DATA/$f → $tgt (BROKEN)"
    else warn "$HOME_DATA/$f missing"; fi
  done
  step "launchd agents"
  lf="$(launchd_files)"; [ -n "$lf" ] && echo "$lf" | sed 's/^/    /' || warn "none"
  step "crontab"
  crontab -l 2>/dev/null | sed 's/^/    /' || warn "empty/none"
  step "mutagen sessions"
  command -v mutagen >/dev/null && mutagen sync list 2>/dev/null | sed -n '1,8p' | sed 's/^/    /' || warn "mutagen not running"
  step "repos (cloned on restore, not copied)"
  for spec in $REPOS; do
    name="${spec%%:*}"; path="${spec#*:}"
    if [ -d "$path/.git" ] || [ -d "$path/.jj" ]; then
      url="$(git -C "$path" remote get-url origin 2>/dev/null || echo '?')"
      sha="$(git -C "$path" rev-parse --short HEAD 2>/dev/null || echo '?')"
      br="$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
      ndirty="$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
      ahead="$(git -C "$path" rev-list --count origin/main..HEAD 2>/dev/null || echo '?')"
      ok "$name  $br@$sha ahead:$ahead dirty:$ndirty  → $url"
    else warn "$name MISSING at $path"
    fi
  done
  step "sessions DB (NOT in bundle → sync-sessions.sh / git archive)"
  db="$HOME_DATA/sessions/sessions.db"
  [ -f "$db" ] && ok "$(du_h "$db")  $db" || warn "no live sessions db"
  ls -lh "$HOME_DATA/sessions/backup/"*.bak 2>/dev/null | sed 's/^/    /' || true
  step "known-excluded (rebuildable): .git/.jj, ~/.bun (2.4G, reinstall bun + gbrain-mcp wrapper), AnkiTov/.goose/venvs (rebuild), scratch/offload, sessions legacy copies"
}

# ── capture ──────────────────────────────────────────────────────────────────
cmd_capture() {
  local LIGHT=0 SNAP_SESSIONS=1 DEST="" TS a
  TS="$(date +%Y%m%d-%H%M%S)"
  for a in "$@"; do case "$a" in
    --light) LIGHT=1;; --no-sessions-snapshot) SNAP_SESSIONS=0;; -*) err "unknown flag $a"; exit 2;;
    *) if [ -z "$DEST" ]; then DEST="$a"; else err "multiple destinations given"; exit 2; fi;;
  esac; done
  DEST="${DEST:-$BUNDLE_ROOT/goose-env-$HOST-$TS}"
  mkdir -p "$DEST"
  chmod 700 "$DEST"
  echo "════════ capture → $DEST ════════"
  local TAR_OPTS=(--exclude '.DS_Store' --exclude '.git' --exclude '.jj' --exclude 'node_modules')

  step "1/8 goose config (~/.config/goose) incl. secrets.yaml, custom_providers, memory, .headroom"
  tar -cf "$DEST/goose-config.tar" -C "$HOME/.config" ${TAR_OPTS[@]+"${TAR_OPTS[@]}"} goose
  if [ -d "$HOME/.agents/skills" ]; then
    tar -cf "$DEST/agents-skills.tar" -C "$HOME/.agents" ${TAR_OPTS[@]+"${TAR_OPTS[@]}"} skills 2>/dev/null \
      && ok "user-wide skills (~/.agents/skills) captured → agents-skills.tar" || warn "agents-skills.tar failed"
  fi
  step "2/8 goose data (~/.local/share/goose) — WITHOUT sessions/; /tmp-symlinked jsons materialized"
  local STAGE="$DEST/.stage"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  if command -v rsync >/dev/null 2>&1; then
    # exit 23 = partial transfer; tolerated — broken volatile symlinks (e.g.
    # schedule.json → /tmp) are handled explicitly below from .bak fallbacks
    # Excluded as re-downloadable (user policy 2026-10-12): whisper gguf model
    # (247MB, Hugging Face) and the model_catalog API cache (5MB, refetched).
    rsync -aL --exclude 'sessions/' --exclude '.DS_Store' --exclude '*.bak*' \
      --exclude 'models/whisper-*.gguf' --exclude 'model_catalog/models_dev_api.*' \
      --exclude 'reminders/log-*.txt' --exclude 'reminders/launchd.*.log' \
      "$HOME_DATA/" "$STAGE/" 2>/dev/null || warn "rsync partial (expected if volatile /tmp symlinks are broken) — continuing"
  else
    warn "rsync missing — fallback tar copy"
    tar -cf - -C "$HOME_DATA" --exclude './sessions' --exclude './*.bak*' --exclude './.DS_Store' \
      --exclude './models/whisper-*.gguf' --exclude './model_catalog/models_dev_api.json' \
      --exclude './reminders/log-*.txt' --exclude './reminders/launchd.*.log' . | tar -xf - -C "$STAGE"
  fi
  # volatile /tmp-backed state: materialize REAL content into staged dir
  local f latest
  for f in projects.json schedule.json; do
    rm -f "$STAGE/$f"
    cp -L "$HOME_DATA/$f" "$STAGE/$f" 2>/dev/null || true
    if [ ! -s "$STAGE/$f" ]; then   # broken/missing symlink → newest NON-BROKEN .bak fallback
      for cand in $(ls -t "$HOME_DATA/$f.bak."* 2>/dev/null); do
        [ -f "$cand" ] || continue   # skips broken symlinks
        cp -p "$cand" "$STAGE/$f"
        warn "$f broken on source — recovered STALE copy from $(basename "$cand"); verify scheduled recipes after restore"
        break
      done
      [ -s "$STAGE/$f" ] || warn "$f could not be recovered from any backup — restore manually"
    fi
  done
  # AnkiPlayGround student-profile collections (user policy 2026-10-12: INCLUDE —
  # 84MB of 44 generated practice profiles; regenerable via update-playground-profiles
  # but cheap to carry and preserves hand-tuned state). Anki2 (~/Library/Application
  # Support/Anki2, 8.2GB) is deliberately NOT captured (user decision).
  if [ -d "$ANKITOV/AnkiPlayGround" ]; then
    step "2b/8 AnkiPlayGround collections"
    tar -cf "$DEST/ankiplayground.tar" -C "$ANKITOV" \
      --exclude '.DS_Store' --exclude '.git' AnkiPlayGround 2>/dev/null \
      && ok "AnkiPlayGround captured ($(du -sh "$DEST/ankiplayground.tar" | cut -f1))" \
      || warn "ankiplayground.tar failed"
    printf 'ankiplayground.tar\t%s\n' "$ANKITOV/AnkiPlayGround (44 student profiles)" >> "$DEST/repos.tsv"
  fi
  tar -cf "$DEST/goose-data.tar" -C "$STAGE" . && rm -rf "$STAGE"
  if [ "$LIGHT" = 1 ]; then warn "3/8 opencode SKIPPED (--light)"; else
    step "3/8 opencode config"
    # opencode credentials live in ~/.local/share/opencode/auth.json, NOT ~/.config/opencode
    # capture both with $HOME-relative paths so a single `tar -xf -C $HOME` restores to the right places
    oc_args=(.config/opencode)
    if [ -f "$HOME/.local/share/opencode/auth.json" ]; then
      oc_args+=(.local/share/opencode/auth.json)
    else
      warn "opencode auth.json absent — manual re-auth will be needed after restore"
    fi
    tar -cf "$DEST/opencode.tar" -C "$HOME" ${TAR_OPTS[@]+"${TAR_OPTS[@]}"} "${oc_args[@]}" 2>/dev/null || warn "no ~/.config/opencode"
  fi
  # rclone config (gdrive remote + OAuth token) — DR §2: back it up with every capture
  if [ -f "$HOME/.config/rclone/rclone.conf" ]; then
    tar -cf "$DEST/rclone.tar" -C "$HOME/.config" --exclude '.DS_Store' rclone \
      && ok "rclone config captured → rclone.tar" || warn "rclone.tar failed"
  else
    warn "no ~/.config/rclone/rclone.conf — gdrive remote needs re-auth after restore"
  fi
  step "4/8 gbrain wrappers from ~/.bun/bin (bun itself NOT captured — reinstall)"
  mkdir -p "$DEST/bun-gbrain"
  cp -p ~/.bun/bin/gbrain* "$DEST/bun-gbrain/" 2>/dev/null || warn "no gbrain wrappers in ~/.bun/bin"
  [ -f "$GOOSE_WS/.gbrain-owner.json" ] && cp -p "$GOOSE_WS/.gbrain-owner.json" "$DEST/bun-gbrain/gbrain-owner.json" || true
  step "5/8 gbrain Postgres state (config, credentials, physical markers, pg_dump of the brain)"
  mkdir -p "$DEST/gbrain-postgres/backups"
  if [ -f "$HOME/.gbrain/config.json" ]; then
    cp -p "$HOME/.gbrain/config.json" "$DEST/gbrain-postgres/config.json"
  else
    warn "no ~/.gbrain/config.json — gbrain not configured here?"
  fi
  cp -p "$HOME/.gbrain/backups/gbrain-db-password.txt" "$DEST/gbrain-postgres/backups/" 2>/dev/null || warn "no gbrain db password file captured"
  cp -Rp "$HOME/.gbrain/backups/physical-markers-"* "$DEST/gbrain-postgres/backups/" 2>/dev/null || true
  cp -p "$HOME/.gbrain/backup-status.json" "$DEST/gbrain-postgres/backups/" 2>/dev/null || true
  # The brain lives in the gbrain-postgres container (volume gbrain_pgdata) since
  # the 2026-10-11 PGlite→Postgres graduation. A bundle without the dump is NOT
  # self-contained for memory. pg_dump is MVCC-consistent; no need to stop anything.
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'gbrain-postgres'; then
    if command -v zstd >/dev/null 2>&1; then
      if docker exec gbrain-postgres pg_dump -U gbrain gbrain 2>/dev/null | zstd -q -3 -o "$DEST/gbrain-postgres/brain.dump.sql.zst"; then
        ok "gbrain brain dumped → gbrain-postgres/brain.dump.sql.zst ($(du_h "$DEST/gbrain-postgres/brain.dump.sql.zst" 2>/dev/null || echo '?'))"
      else
        warn "pg_dump FAILED — brain NOT in bundle; dump manually before touching the container"
      fi
    else
      docker exec gbrain-postgres pg_dump -U gbrain gbrain > "$DEST/gbrain-postgres/brain.dump.sql" 2>/dev/null \
        && warn "zstd missing — saved UNCOMPRESSED brain.dump.sql" || warn "pg_dump failed"
    fi
  else
    warn "gbrain-postgres container not running — brain NOT captured (see DISASTER-RECOVERY.md §gbrain)"
  fi
  cat > "$DEST/gbrain-postgres/restore-gbrain-postgres.sh" <<'GBFIN'
#!/usr/bin/env bash
# Recreate the Postgres-backed gbrain brain on a fresh machine.
# Requires: docker + zstd. Dump is plain SQL from pg_dump (schema + data).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PW="$(cat "$DIR/backups/gbrain-db-password.txt" 2>/dev/null || echo 'CHANGE_ME')"
docker run -d --name gbrain-postgres --restart unless-stopped \
  -e POSTGRES_USER=gbrain -e POSTGRES_PASSWORD="$PW" -e POSTGRES_DB=gbrain \
  -p 127.0.0.1:5433:5432 -v gbrain_pgdata:/var/lib/postgresql/data \
  pgvector/pgvector:pg17
echo "waiting for postgres..."
until docker exec gbrain-postgres pg_isready -U gbrain -d gbrain >/dev/null 2>&1; do sleep 2; done
docker exec gbrain-postgres psql -U gbrain -d gbrain -c 'CREATE EXTENSION IF NOT EXISTS vector;'
zstd -dc "$DIR/brain.dump.sql.zst" | docker exec -i gbrain-postgres psql -U gbrain -d gbrain -q -v ON_ERROR_STOP=1
mkdir -p "$HOME/.gbrain"
cp "$DIR/config.json" "$HOME/.gbrain/config.json" && chmod 600 "$HOME/.gbrain/config.json"
echo "gbrain brain restored on Postgres (:5433). Verify: gbrain status && gbrain doctor"
GBFIN
  chmod +x "$DEST/gbrain-postgres/restore-gbrain-postgres.sh"
  step "6/8 launchd agents + crontab + mutagen spec"
  mkdir -p "$DEST/launchd"
  if [ "$OS" = "Darwin" ]; then
    for f in $(launchd_files); do cp -p "$HOME/Library/LaunchAgents/$f" "$DEST/launchd/"; done
  fi
  crontab -l > "$DEST/crontab.txt" 2>/dev/null || echo "# (empty)" > "$DEST/crontab.txt"
  command -v mutagen >/dev/null && { mutagen sync list > "$DEST/mutagen-sessions.txt" 2>&1 || true; } || true
  cat > "$DEST/mutagen-restore.sh" <<'MUTFIN'
#!/usr/bin/env bash
# Re-create the mutagen two-way sync (edit paths to match this machine).
# NOTE: never mutagen-sync a live sqlite DB directly; this syncs the workspace.
mutagen sync create --name ankitov-goose --default-mode-two-way-resolved \
  "<WORKSPACE_ROOT>/AnkiTov-goose" "ybg@ybgxps:/home/ybg/AnkiTov-goose"
MUTFIN
  chmod +x "$DEST/mutagen-restore.sh"
  # reminder-delivery system (2026-10-12): runner script lives in ~/.local/bin
  # (NOT covered by goose-config/goose-data tars); the plist is captured via
  # launchd/ (user.ybg.*), reminders.tsv via goose-config.tar, and
  # ~/.local/share/goose/reminders/ (recipes + state) via goose-data.tar
  # (logs excluded there).
  step "6b/8 reminder system (goose-reminder.sh)"
  mkdir -p "$DEST/reminder-system"
  if [ -f "$HOME/.local/bin/goose-reminder.sh" ]; then
    cp -p "$HOME/.local/bin/goose-reminder.sh" "$DEST/reminder-system/" \
      && ok "goose-reminder.sh captured → reminder-system/"
  else
    warn "no ~/.local/bin/goose-reminder.sh — reminder runner not captured"
  fi
  step "7/8 repo manifest (remote + sha; clone on restore)"
  : > "$DEST/repos.tsv"
  local allrepos="$REPOS" nested subrepo rel
  nested="$(find "$ANKITOV" "$GOOSE_WS" -maxdepth 2 -name .git -type d 2>/dev/null | sed 's|/\.git$||' | grep -v -e "^$ANKITOV\$" -e "^$GOOSE_WS\$" || true)"
  for subrepo in $nested; do allrepos="$allrepos $(basename "$subrepo"):$subrepo"; done
  [ -n "$nested" ] && ok "nested repos detected: $(echo $nested | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"
  for spec in $allrepos; do
    name="${spec%%:*}"; path="${spec#*:}"
    url="$(git -C "$path" remote get-url origin 2>/dev/null || true)"
    sha="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
    br="$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    dirty="$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$url" "${br:-main}" "${sha:-UNKNOWN}" "$dirty" >> "$DEST/repos.tsv"
  done
  # WIP safety-net: unpushed commits + uncommitted files for every git repo
  # (main + nested). Uses `status --porcelain -uall -z` so untracked dirs are
  # expanded to FILES (no runaway tar recursion into nested repos) and spaces
  # in filenames are safe. python3 filters junk paths NUL-safely.
  mkdir -p "$DEST/repo-wip"
  for spec in $allrepos; do
    name="${spec%%:*}"; path="${spec#*:}"
    [ -d "$path/.git" ] || continue
    local nlocal
    nlocal="$(git -C "$path" log --oneline --branches --not --remotes 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$nlocal" != "0" ]; then
      git -C "$path" bundle create "$DEST/repo-wip/$name-unpushed.bundle" --branches --not --remotes 2>/dev/null \
        && ok "WIP: $name $nlocal unpushed commits → repo-wip/$name-unpushed.bundle" \
        || warn "WIP bundle failed for $name"
    fi
    local nd
    nd="$(git -C "$path" status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$nd" != "0" ]; then
      ( cd "$path" && git status --porcelain -uall -z 2>/dev/null \
        | python3 -c 'import sys
skip=[b"node_modules/",b"/node_modules/",b"target/",b"/target/",b".hermit/",b"/.hermit/",b"__pycache__/",b"venv/",b"/venvs/",b".DS_Store",b".anki2-shm",b".anki2-wal"]
out=[]
for rec in sys.stdin.buffer.read().split(b"\0"):
    if len(rec)<4: continue
    p=rec[3:]
    if p and not any(s in p for s in skip) and not p.endswith(b"/"): out.append(p)
sys.stdout.buffer.write(b"\0".join(out))' \
        | xargs -0 tar --no-recursion -cf "$DEST/repo-wip/$name-uncommitted.tar" 2>/dev/null ) || true
      # tar exit 1 (files changing during read, e.g. live .db/.anki2) is fine if archive is non-empty
      if [ -s "$DEST/repo-wip/$name-uncommitted.tar" ]; then
        ok "WIP: $name $nd dirty files → repo-wip/$name-uncommitted.tar ($(du_h "$DEST/repo-wip/$name-uncommitted.tar" 2>/dev/null || echo '?'))"
      else
        warn "WIP tar failed for $name (continuing — dirty files still recoverable from disk)"
      fi
    fi
  done
  # volatile project-level .goose of AnkiTov (untracked but valuable: agents, recipes, memory, secrets; venvs/scratch excluded)
  if [ -d "$ANKITOV/.goose" ]; then
    tar -cf "$DEST/ankitov-goose-state.tar" -C "$ANKITOV" \
      --exclude '.goose/venvs' --exclude '.goose/scratch' --exclude '.goose/offload' \
      --exclude '.goose/peer' --exclude '.DS_Store' .goose 2>/dev/null || true
    printf 'ankitov-goose-state.tar\t%s\n' "$ANKITOV/.goose (venvs/scratch/offload/peer excluded)" >> "$DEST/repos.tsv"
  fi
  # AnkiTov-C project-level .goose (recipes incl. verify-loop, briefs + archives,
  # offload manifest + artifacts, memory, notes). venvs/scratch/peer excluded.
  if [ -d "$ANKITOV_C/.goose" ]; then
    tar -cf "$DEST/ankitov-c-goose-state.tar" -C "$ANKITOV_C" \
      --exclude '.goose/venvs' --exclude '.goose/scratch' --exclude '.goose/peer' \
      --exclude '.DS_Store' .goose 2>/dev/null || true
    [ -s "$DEST/ankitov-c-goose-state.tar" ] && \
      printf 'ankitov-c-goose-state.tar\t%s\n' "$ANKITOV_C/.goose (venvs/scratch/peer excluded)" >> "$DEST/repos.tsv"
  fi
  step "8/8 sessions snapshot via sync-sessions.sh (git archive + copy INTO bundle)"
  if [ "$SNAP_SESSIONS" = 1 ] && [ -x "$SESSIONS_SCRIPT" ]; then
    "$SESSIONS_SCRIPT" snapshot || warn "sessions snapshot failed — live .bak still exists"
    # self-contained bundle: put the fresh snapshot INTO the bundle too (git
    # archive stays the transport; the copy guards against losing GitHub access)
    local SNAPFILE="$SESSIONS_ARCHIVE/sessions-$HOST.db.zst"
    if [ -f "$SNAPFILE" ]; then
      cp -p "$SNAPFILE" "$DEST/" && ok "sessions snapshot copied into bundle: $(basename "$SNAPFILE") ($(du_h "$SNAPFILE"))"
    else
      warn "no sessions-$HOST.db.zst in $SESSIONS_ARCHIVE — bundle is NOT self-contained for sessions"
    fi
  elif [ "$SNAP_SESSIONS" = 1 ]; then warn "sync-sessions.sh not found at $SESSIONS_SCRIPT"
  else warn "sessions snapshot skipped (--no-sessions-snapshot)"; fi
  step "checksums + manifest"
  # DR runbook: prefer the FILLED master in $BUNDLE_ROOT (real Appendix B credentials).
  # The repo copy ($GOOSE_WS/scripts/) is the public-safe template with PENDING
  # placeholders — AnkiTov-Goose is a public repo, credentials must never be pasted there.
  if [ -f "$BUNDLE_ROOT/DISASTER-RECOVERY.md" ]; then
    cp -p "$BUNDLE_ROOT/DISASTER-RECOVERY.md" "$DEST/DISASTER-RECOVERY.md"
  else
    cp -p "$GOOSE_WS/scripts/DISASTER-RECOVERY.md" "$DEST/DISASTER-RECOVERY.md" 2>/dev/null \
      || warn "DISASTER-RECOVERY.md not found — bundle lacks the DR runbook"
  fi
  ( cd "$DEST" && sha256 *.tar *.txt *.tsv *.zst 2>/dev/null > SHA256SUMS || true )
  local TOTAL; TOTAL="$(du -sh "$DEST" | cut -f1)"
  cat > "$DEST/MANIFEST.md" <<EOF
# goose-env bundle — $HOST @ $TS (env-deploy.sh $VERSION)
DEST=$DEST
- goose-config.tar   — ~/.config/goose (config, secrets.yaml, custom_providers, memory, .headroom, recipes)
- goose-data.tar     — ~/.local/share/goose minus sessions (+ volatile /tmp-backed projects/schedule json as REAL files)
- opencode.tar       — ~/.config/opencode + ~/.local/share/opencode/auth.json (opencode credentials) $([ "$LIGHT" = 1 ] && echo "(SKIPPED --light)")
- rclone.tar         — ~/.config/rclone (gdrive remote + OAuth token — DR §2)
- bun-gbrain/        — gbrain-mcp wrapper(s) + .gbrain-owner.json
- gbrain-postgres/   — Postgres-backed brain (since 2026-10-11 graduation): config.json, DB password,
  physical-root markers, brain.dump.sql.zst (live pg_dump) + restore-gbrain-postgres.sh
- launchd/ crontab.txt mutagen-sessions.txt mutagen-restore.sh (incl. user.ybg.* plists; gbrain HTTP LaunchAgent is DISABLED on purpose — brain is Postgres-backed, do not recreate)
- repos.tsv          — clone list: AnkiTov, AnkiTov-Goose (+SHA), ankitov-goose-state.tar for AnkiTov/.goose, ankitov-c-goose-state.tar for AnkiTov-C/.goose (recipes incl. verify-loop, briefs, offload)
- Sessions DB: git archive (github.com/yitzhakbg/AnkiTov-Sessions) AND copied into this bundle as sessions-$HOST.db.zst (restore: zstd -d → sessions.db, or \`sync-sessions.sh restore\`)
- ankiplayground.tar — AnkiTov/AnkiPlayGround (44 student practice profiles, ~84MB)
- reminder-system/   — goose-reminder.sh runner (plist via launchd/, reminders.tsv via
  goose-config.tar, recipes+state via goose-data.tar minus logs)
- Excluded by design: ~/.bun (2.4G), AnkiTov/.goose/venvs, scratch, offload, legacy sessions copies,
  ~/Library/Application Support/Anki2 (8.2G — user decision, NOT backed up here),
  whisper gguf model (247M, re-download from HF), model_catalog API cache (refetched)
Total size: $TOTAL. PROTECT this bundle: contains secrets.yaml and AnkiTov/.goose/secrets.
EOF
  ok "bundle ready: $DEST ($TOTAL)"
  warn "bundle contains SECRETS — move it off-machine yourself (encrypted USB / private cloud), never a public share."
}

# ── restore ──────────────────────────────────────────────────────────────────
cmd_restore() {
  local B="${1:?usage: env-deploy.sh restore <bundle-dir>}"
  [ -f "$B/MANIFEST.md" ] || err "not a bundle: $B" && exit 2
  echo "════════ restore from $B → host=$HOST os=$OS ════════"
  step "checksums"
  ( cd "$B" && { shasum -a 256 -c SHA256SUMS 2>/dev/null || sha256sum -c SHA256SUMS 2>/dev/null; } ) || warn "checksum verify failed/absent — inspect manually"
  if [ "${FORCE:-0}" != 1 ]; then read -r -p "Proceed with restore? Existing configs will be backed up first. [y/N] " r; [ "${r:-n}" = "y" ] || exit 1; fi
  step "1/8 goose binary"
  if ! command -v goose >/dev/null; then
    if [ "$OS" = "Darwin" ]; then warn "install goose, then re-run"; curl -fsSL https://goose.ai/install.sh | bash
    else warn "run the repo's setup-linux-goose.sh after repos are cloned (it installs goose 1.38)"; fi
  else ok "goose $(goose --version 2>/dev/null | head -1)"
  fi
  step "2/8 tools"
  if command -v brew >/dev/null; then brew install -q mutagen zstd jj bun opencode sqlite 2>/dev/null || warn "brew install had issues — check manually"
  elif [ "$OS" = "Linux" ]; then warn "Linux: install zstd/jj/mutagen/bun per setup-linux-goose.sh"
  fi
  step "3/8 goose config"
  mkdir -p "$HOME/.config"
  [ -d "$HOME_CONFIG" ] && mv "$HOME_CONFIG" "$HOME_CONFIG.pre-restore.$(date +%s)" || true
  tar -xf "$B/goose-config.tar" -C "$HOME/.config" && chmod 700 "$HOME_CONFIG" && chmod 600 "$HOME_CONFIG/secrets.yaml" 2>/dev/null || true
  if [ -f "$B/agents-skills.tar" ]; then
    mkdir -p "$HOME/.agents"
    tar -xf "$B/agents-skills.tar" -C "$HOME/.agents" && ok "restored ~/.agents/skills" || warn "agents-skills.tar extract failed"
  fi
  ok "restored ~/.config/goose"
  step "4/8 goose data (sessions/ left untouched)"
  local DATABAK item
  if [ -d "$HOME_DATA" ]; then
    DATABAK="$HOME_DATA.pre-restore.$(date +%s)"; mkdir -p "$DATABAK"
    for item in "$HOME_DATA"/* "$HOME_DATA"/.[!.]*; do
      [ -e "$item" ] || continue
      if [ "$(basename "$item")" = "sessions" ]; then continue; fi
      mv "$item" "$DATABAK/" 2>/dev/null || true
    done
  fi
  mkdir -p "$HOME_DATA"; tar -xf "$B/goose-data.tar" -C "$HOME_DATA"
  # keep the volatile-tmp convention: copy restored real files, then repoint symlinks like the old machine
  for f in projects.json schedule.json; do
    if [ -f "$HOME_DATA/$f" ]; then cp -p "$HOME_DATA/$f" "/tmp/ankitov-$f"; ln -sfn "/tmp/ankitov-$f" "$HOME_DATA/$f"; fi
  done
  ok "restored ~/.local/share/goose (sessions/ untouched)"
  step "5/8 opencode"
  if [ -f "$B/opencode.tar" ]; then
    [ -f "$HOME/.local/share/opencode/auth.json" ] && cp -p "$HOME/.local/share/opencode/auth.json" "$HOME/.local/share/opencode/auth.json.pre-restore.$(date +%s)" || true
    tar -xf "$B/opencode.tar" -C "$HOME" && ok "opencode restored (config + auth.json if bundled)" || warn "opencode.tar extract failed"
  else
    warn "no opencode.tar in bundle"
  fi
  step "6/8 gbrain wrappers"
  if [ -d "$B/bun-gbrain" ] && ls "$B"/bun-gbrain/gbrain* >/dev/null 2>&1; then
    mkdir -p ~/.bun/bin; cp -p "$B"/bun-gbrain/gbrain* ~/.bun/bin/ && chmod +x ~/.bun/bin/gbrain* 2>/dev/null || true
    [ -f "$B/bun-gbrain/gbrain-owner.json" ] && cp -p "$B/bun-gbrain/gbrain-owner.json" "$GOOSE_WS/.gbrain-owner.json" 2>/dev/null || true
    ok "gbrain wrappers installed (bun itself: brew install bun / curl -fsSL https://bun.sh/install | bash)"
  fi
  step "7/8 repos: clone + checkout recorded SHAs"
  while IFS=$'\t' read -r name url br sha dirty; do
    [ "$name" = "ankitov-goose-state.tar" ] && continue
    case "$name" in
      AnkiTov) dest="$ANKITOV";;
      AnkiTov-C) dest="$ANKITOV_C";;
      AnkiTov-Goose) dest="$GOOSE_WS";;
      *) dest="$ANKITOV/$name";;   # nested repos (e.g. buzz-hive) live under AnkiTov
    esac
    if [ -d "$dest/.git" ]; then ok "$name already present ($dest)"
    else
      mkdir -p "$(dirname "$dest")"
      git clone "$url" "$dest" && [ "$sha" != "UNKNOWN" ] && git -C "$dest" checkout -q "$sha" && ok "$name cloned@$sha" || warn "$name clone/checkout issue"
    fi
    [ -f "$B/repo-wip/$name-unpushed.bundle" ] && { git -C "$dest" fetch -q "$B/repo-wip/$name-unpushed.bundle" '*:refs/remotes/wipbundle/*' 2>/dev/null && warn "$name: unpushed commits fetched from bundle as refs/remotes/wipbundle/* — merge/reset as appropriate" || true; }
  done < "$B/repos.tsv"
  if [ -f "$B/ankitov-goose-state.tar" ] && [ -d "$ANKITOV/.goose.pre-restore" ]; then :; fi
  [ -f "$B/ankitov-goose-state.tar" ] && { [ -d "$ANKITOV/.goose" ] && mv "$ANKITOV/.goose" "$ANKITOV/.goose.pre-restore.$(date +%s)" || true; tar -xf "$B/ankitov-goose-state.tar" -C "$ANKITOV"; ok "AnkiTov/.goose state restored (venvs/scratch NOT included — rebuild venvs as needed)"; }
  [ -f "$B/ankitov-c-goose-state.tar" ] && { [ -d "$ANKITOV_C/.goose" ] && mv "$ANKITOV_C/.goose" "$ANKITOV_C/.goose.pre-restore.$(date +%s)" || true; tar -xf "$B/ankitov-c-goose-state.tar" -C "$ANKITOV_C"; ok "AnkiTov-C/.goose state restored"; }
  if [ -f "$B/reminder-system/goose-reminder.sh" ]; then
    mkdir -p "$HOME/.local/bin"
    cp -p "$B/reminder-system/goose-reminder.sh" "$HOME/.local/bin/" && chmod +x "$HOME/.local/bin/goose-reminder.sh"
    ok "reminder runner installed → ~/.local/bin/goose-reminder.sh (plist via launchd/; reminders.tsv via goose-config.tar)"
  fi
  [ -f "$B/ankiplayground.tar" ] && { mkdir -p "$ANKITOV"; tar -xf "$B/ankiplayground.tar" -C "$ANKITOV"; ok "AnkiPlayGround collections restored (44 student profiles)"; }
  step "8/8 sessions, agents, mutagen"
  if [ -x "$SESSIONS_SCRIPT" ]; then
    local SNAP_HOST
    SNAP_HOST="$(awk -F'— ' '/^# goose-env bundle/ {print $2}' "$B/MANIFEST.md" 2>/dev/null | awk '{print $1}')"
    SNAP_HOST="${SNAP_HOST:-$HOST}"
    "$SESSIONS_SCRIPT" pull && "$SESSIONS_SCRIPT" restore "$SNAP_HOST" || warn "sessions restore needs review — run sync-sessions.sh manually (machine: $SNAP_HOST)"
  else warn "sync-sessions.sh not found; clone repos first, then re-run step 8"; fi
  if [ "$OS" = "Darwin" ] && [ -d "$B/launchd" ]; then
    cp -p "$B"/launchd/* ~/Library/LaunchAgents/ && for f in "$B"/launchd/*; do launchctl load "$HOME/Library/LaunchAgents/$(basename "$f")" 2>/dev/null || true; done
    ok "launchd agents loaded"
  fi
  if [ -s "$B/crontab.txt" ] && ! grep -q '^# (empty)' "$B/crontab.txt"; then
    ( crontab -l 2>/dev/null; cat "$B/crontab.txt" ) | sort -u | crontab - 2>/dev/null && ok "crontab merged" || warn "crontab restore failed"
  fi
  echo ""
  ok "RESTORE COMPLETE — remaining manual items:"
  echo "  • verify: goose version, \`goose session list\`, API keys in ~/.config/goose/secrets.yaml"
  echo "  • if paths differ on this machine: WORKSPACE_ROOT / GOOSE_WS / ANKITOV env overrides"
  echo "  • uncommitted WIP saved in the bundle (NOT auto-applied):"
  ls "$B"/repo-wip/*.tar 2>/dev/null | while read -r w; do echo "      tar -xf $w -C <repo-root>   # $(basename "$w")"; done
  [ -d "$B/repo-wip" ] || true
  echo "  • mutagen: bash $B/mutagen-restore.sh (edit paths first)"
  echo "  • AnkiTov/.goose/venvs + ~/.bun packages: rebuild"
  echo "  • scheduled recipes: check ~/.local/share/goose/scheduled_recipes + schedule.json"
  echo "  • gbrain memory store: verify .gbrain-owner.json + gbrain-mcp reachability"
}

# ── push: upload newest bundle to Drive + keep-2 retention ──────────────────
# Standing policy (user, 2026-10-11): every new bundle pushed to the remote deletes
# all but the last TWO bundles. Upload target: gdrive:goose-env-<bundle-name>.
cmd_push() {
  command -v rclone >/dev/null || { err "rclone not installed (brew install rclone)"; exit 2; }
  rclone listremotes 2>/dev/null | grep -q '^gdrive:$' || { err "no 'gdrive:' rclone remote — see DISASTER-RECOVERY.md §2"; exit 2; }
  local WANT="${1:-}"
  local NEWEST
  if [ -n "$WANT" ]; then
    [ -d "$BUNDLE_ROOT/$WANT" ] || { err "no such bundle: $BUNDLE_ROOT/$WANT"; exit 2; }
    NEWEST="$WANT"
  else
    NEWEST="$(ls -1dt "$BUNDLE_ROOT"/goose-env-* 2>/dev/null | head -1 | xargs -I{} basename {})"
    [ -n "$NEWEST" ] || { err "no bundles under $BUNDLE_ROOT — run 'env-deploy.sh capture' first"; exit 2; }
  fi
  step "push $NEWEST → gdrive:$NEWEST"
  rclone copy "$BUNDLE_ROOT/$NEWEST" "gdrive:$NEWEST" -P --transfers 8 || { err "rclone copy failed"; exit 1; }
  ok "uploaded gdrive:$NEWEST"
  # keep-2 retention: newest TWO goose-env-* dirs survive, older ones purged.
  # Only dirs matching goose-env-* are ever touched.
  step "retention: keeping newest 2 bundles on gdrive:"
  rclone lsd gdrive: 2>/dev/null | awk '{print $NF}' | grep '^goose-env-' | sort -r \
    | tail -n +3 | while read -r old; do
        warn "purging gdrive:$old"
        rclone purge "gdrive:$old" || warn "purge of $old failed (non-fatal)"
      done
  ok "push complete — remote now holds the newest 2 bundles"
}

# ── doctor ───────────────────────────────────────────────────────────────────
cmd_doctor() {
  echo "════════ doctor — $HOST ════════"
  local FAIL=0
  for t in goose git mutagen zstd jj bun opencode sqlite3; do command -v $t >/dev/null && ok "$t" || { warn "$t MISSING"; FAIL=1; }; done
  [ -f "$HOME_CONFIG/config.yaml" ] && ok "goose config.yaml" || { warn "no goose config.yaml"; FAIL=1; }
  [ -f "$HOME_CONFIG/secrets.yaml" ] && ok "secrets.yaml" || { warn "no secrets.yaml"; FAIL=1; }
  [ -d "$HOME_DATA/sessions" ] && ok "sessions dir" || { warn "no sessions dir"; FAIL=1; }
  [ -d "$GOOSE_WS/.git" ] && { git -C "$GOOSE_WS" fetch -q origin 2>/dev/null && { [ "$(git -C "$GOOSE_WS" rev-list --count origin/main..HEAD 2>/dev/null)" = "0" ] && ok "AnkiTov-Goose pushed" || warn "AnkiTov-Goose has UNPUSHED commits"; }; } || { warn "AnkiTov-Goose missing"; FAIL=1; }
  [ -d "$ANKITOV/.git" ] && { git -C "$ANKITOV" fetch -q origin 2>/dev/null && { [ "$(git -C "$ANKITOV" rev-list --count origin/main..HEAD 2>/dev/null)" = "0" ] && ok "AnkiTov pushed" || warn "AnkiTov has UNPUSHED commits"; }; } || { warn "AnkiTov missing"; FAIL=1; }
  [ -n "$(launchd_files)" ] && ok "launchd agents present" || warn "no launchd agents (ok on Linux)"
  for spec in $REPOS; do
    name="${spec%%:*}"; path="${spec#*:}"
    nd="$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    [ "$nd" != "0" ] && warn "$name has $nd uncommitted files — run 'env-deploy.sh capture' so they land in a bundle (git alone will NOT save them)"
  done
  [ "$FAIL" = 0 ] && ok "ALL CRITICAL CHECKS PASS" || err "some checks failed (see [!])"
  exit "$FAIL"
}

# ── main ─────────────────────────────────────────────────────────────────────
case "${1:-}" in
  inventory) cmd_inventory ;;
  capture)   shift; cmd_capture "$@" ;;
  push)      shift; cmd_push "$@" ;;
  restore)   shift; cmd_restore "$@" ;;
  doctor)    cmd_doctor ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
