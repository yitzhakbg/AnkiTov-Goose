#!/usr/bin/env bash
# =============================================================================
# env-deploy.sh — Goose/AnkiTov full-environment capture & deploy
# =============================================================================
# Purpose: redeploy the complete working environment (Goose + goose-related +
# AnkiTov + ankitov-related) on a fresh/lost/replacement machine.
#
# Design principle: git-backed things are CLONED, not copied. Only volatile
# state (configs, small DBs, schedules, launchd jobs) is captured into a
# bundle. Sessions DB is handled by sync-sessions.sh (git snapshot archive).
#
# Subcommands:
#   inventory              show every component: present? size? git state?
#   capture [DEST] [--light|--no-sessions-snapshot]
#                          build restorable bundle  (DEST default below)
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

VERSION="2026-10-06.1"
HOST="$( (hostname -s 2>/dev/null || hostname) | tr '[:upper:]' '[:lower:]' | sed 's/\.local$//;s/\.//g' )"
OS="$(uname -s)"
HOME_CONFIG="$HOME/.config/goose"
HOME_DATA="$HOME/.local/share/goose"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/Volumes/YBG1TB4Mac}"        # override on other machines
GOOSE_WS="${GOOSE_WS:-$WORKSPACE_ROOT/AnkiTov-goose}"          # goose repo workspace
ANKITOV="${ANKITOV:-$WORKSPACE_ROOT/AnkiTov}"                  # main repo
BUNDLE_ROOT="${BUNDLE_ROOT:-$WORKSPACE_ROOT/goose-env-bundles}"
SESSIONS_SCRIPT="${SESSIONS_SCRIPT:-$GOOSE_WS/scripts/sync-sessions.sh}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[X]${NC} $*" >&2; }
step() { echo -e "${BLUE}──${NC} $*"; }

du_h() { du -sh "$1" 2>/dev/null | cut -f1; }
sha256() { if command -v shasum >/dev/null; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }

# ── component definitions ────────────────────────────────────────────────────
# name | kind | path(s) | tar-excludes
REPOS="AnkiTov:$ANKITOV AnkiTov-Goose:$GOOSE_WS"

launchd_files() {
  [ "$OS" = "Darwin" ] || return 0
  ls ~/Library/LaunchAgents/ 2>/dev/null | grep -E '^com\.(ankitov|user\.goose)' || true
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

  step "1/7 goose config (~/.config/goose) incl. secrets.yaml, custom_providers, memory, .headroom"
  tar -cf "$DEST/goose-config.tar" -C "$HOME/.config" ${TAR_OPTS[@]+"${TAR_OPTS[@]}"} goose
  step "2/7 goose data (~/.local/share/goose) — WITHOUT sessions/; /tmp-symlinked jsons materialized"
  local STAGE="$DEST/.stage"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  if command -v rsync >/dev/null 2>&1; then
    # exit 23 = partial transfer; tolerated — broken volatile symlinks (e.g.
    # schedule.json → /tmp) are handled explicitly below from .bak fallbacks
    rsync -aL --exclude 'sessions/' --exclude '.DS_Store' --exclude '*.bak*' \
      "$HOME_DATA/" "$STAGE/" 2>/dev/null || warn "rsync partial (expected if volatile /tmp symlinks are broken) — continuing"
  else
    warn "rsync missing — fallback tar copy"
    tar -cf - -C "$HOME_DATA" --exclude './sessions' --exclude './*.bak*' --exclude './.DS_Store' . | tar -xf - -C "$STAGE"
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
  tar -cf "$DEST/goose-data.tar" -C "$STAGE" . && rm -rf "$STAGE"
  if [ "$LIGHT" = 1 ]; then warn "3/7 opencode SKIPPED (--light)"; else
    step "3/7 opencode config"; tar -cf "$DEST/opencode.tar" -C "$HOME/.config" ${TAR_OPTS[@]+"${TAR_OPTS[@]}"} opencode 2>/dev/null || warn "no ~/.config/opencode"
  fi
  step "4/7 gbrain wrappers from ~/.bun/bin (bun itself NOT captured — reinstall)"
  mkdir -p "$DEST/bun-gbrain"
  cp -p ~/.bun/bin/gbrain* "$DEST/bun-gbrain/" 2>/dev/null || warn "no gbrain wrappers in ~/.bun/bin"
  [ -f "$GOOSE_WS/.gbrain-owner.json" ] && cp -p "$GOOSE_WS/.gbrain-owner.json" "$DEST/bun-gbrain/gbrain-owner.json" || true
  step "5/7 launchd agents + crontab + mutagen spec"
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
  step "6/7 repo manifest (remote + sha; clone on restore)"
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
  step "7/7 sessions snapshot via sync-sessions.sh (git archive)"
  if [ "$SNAP_SESSIONS" = 1 ] && [ -x "$SESSIONS_SCRIPT" ]; then
    "$SESSIONS_SCRIPT" snapshot || warn "sessions snapshot failed — live .bak still exists"
  elif [ "$SNAP_SESSIONS" = 1 ]; then warn "sync-sessions.sh not found at $SESSIONS_SCRIPT"
  else warn "sessions snapshot skipped (--no-sessions-snapshot)"; fi
  step "checksums + manifest"
  ( cd "$DEST" && sha256 *.tar *.txt *.tsv 2>/dev/null > SHA256SUMS || true )
  local TOTAL; TOTAL="$(du -sh "$DEST" | cut -f1)"
  cat > "$DEST/MANIFEST.md" <<EOF
# goose-env bundle — $HOST @ $TS (env-deploy.sh $VERSION)
DEST=$DEST
- goose-config.tar   — ~/.config/goose (config, secrets.yaml, custom_providers, memory, .headroom, recipes)
- goose-data.tar     — ~/.local/share/goose minus sessions (+ volatile /tmp-backed projects/schedule json as REAL files)
- opencode.tar       — ~/.config/opencode $([ "$LIGHT" = 1 ] && echo "(SKIPPED --light)")
- bun-gbrain/        — gbrain-mcp wrapper(s) + .gbrain-owner.json
- launchd/ crontab.txt mutagen-sessions.txt mutagen-restore.sh
- repos.tsv          — clone list: AnkiTov, AnkiTov-Goose (+SHA), ankitov-goose-state.tar for AnkiTov/.goose
- Sessions DB: NOT in bundle → \`sync-sessions.sh restore\` (git archive github.com/yitzhakbg/AnkiTov-Sessions)
- Excluded by design: ~/.bun (2.4G), AnkiTov/.goose/venvs, scratch, offload, legacy sessions copies
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
  [ -f "$B/opencode.tar" ] && tar -xf "$B/opencode.tar" -C "$HOME/.config" && ok "opencode restored" || warn "no opencode.tar in bundle"
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
  restore)   shift; cmd_restore "$@" ;;
  doctor)    cmd_doctor ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
