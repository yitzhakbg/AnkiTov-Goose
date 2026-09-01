# Goose Session Sync — Mac ↔ ybgXPS laptop

Keep both machines showing the same Goose chats.

## How it works
- **Live DB:** `~/.local/share/goose/sessions/sessions.db` (SQLite WAL). Cannot be
  real-time synced — it corrupts. We snapshot it safely instead.
- **Transport:** `scripts/sync-sessions.sh` makes a git-backed snapshot in
  `~/.goose-sessions-archive/` and pushes to GitHub
  (`yitzhakbg/AnkiTov-Sessions`). The other machine pulls and restores it.
- **Machine keys** (friendly → snapshot file):
  | you type | snapshot file |
  |---|---|
  | `mac` / `mac-mini` / `ybgmacmini` | `sessions-ybgmacmini.db` |
  | `laptop` / `xps` / `ybgxps` | `sessions-ybgxps.db` |
- **`restore` auto-runs `remap`**, rewriting each session's `working_dir` to the
  nearest existing local path (or `$HOME`). This fixes the "Invalid directory
  path" error that foreign absolute paths cause.

## Commands

### Mac → laptop
```bash
# Mac
cd ~/AnkiTov-goose && bash scripts/sync-sessions.sh snapshot
# Laptop — quit Goose first, then:
cd ~/AnkiTov-goose && bash scripts/sync-sessions.sh restore mac
```

### Laptop → Mac
```bash
# Laptop
cd ~/AnkiTov-goose && bash scripts/sync-sessions.sh snapshot
# Mac — quit Goose first, then:
cd ~/AnkiTov-goose && bash scripts/sync-sessions.sh restore laptop
```

### Useful extras
```bash
bash scripts/sync-sessions.sh list     # show available snapshots
bash scripts/sync-sessions.sh remap    # fix working_dir without a restore
bash scripts/sync-sessions.sh pull     # just fetch latest snapshots
```

## Rules
- **Quit Goose on the target machine before `restore`** — it replaces the live DB
  underneath. (The script checks and refuses if Goose is running.)
- Backups: `sessions.db.pre-restore` and `sessions.db.pre-remap` are saved in the
  live dir each time. Delete when happy.
- **Config** (`custom_providers/`, `memory/`, buzz agents/harnesses) syncs
  separately — NOT via this script:
  - Mac → laptop: `~/.local/bin/goose-buzz-sync.sh`
  - Laptop → Mac: `~/.local/bin/goose-sync-reverse.sh --update`
- **Workspace** is owned by **mutagen** (`ankitov-goose` 2-way session). Never
  rsync it — it causes Repo A / Repo B cross-contamination.
- **Repo A (`AnkiTov`, full dev)** and **Repo B (`AnkiTov-goose`, lightweight)**
  must stay isolated. This doc + script live in Repo B.

## Verify
```bash
sqlite3 ~/.local/share/goose/sessions/sessions.db 'SELECT COUNT(*) FROM sessions'
# both machines should report the same number
```
