# AnkiTov Goose environment — DISASTER RECOVERY (from ground up)

Generated: 2026-10-11 · env-deploy.sh v2026-10-11.1 · machine that died: **ybgmacmini** (macOS, arm64)
Lives in the AnkiTov-Goose repo (survives machine loss); `capture` copies it into every bundle.
Scenario: **the Mac is gone.** You have: a new/bare machine, a browser, and this Drive folder.

---

## 0. Where everything lives (the asset map)

| Asset | Where | How you get it back |
|---|---|---|
| Goose config, **secrets.yaml**, custom_providers, memory, recipes, headroom state | **This Drive folder** → `goose-env-ybgmacmini-20261010-232116/goose-config.tar` | restore step 3 |
| Goose data (apps, model_catalog, models, moose, scheduled_recipes, projects/schedule json) | bundle → `goose-data.tar` | restore step 4 |
| **All Goose chats (sessions DB)** | bundle → `sessions-ybgmacmini.db.zst` **and** git archive `github.com/yitzhakbg/AnkiTov-Sessions` | §6 |
| opencode config + credentials | bundle → `opencode.tar` | restore step 5 |
| gbrain-mcp wrappers + owner json | bundle → `bun-gbrain/` | restore step 6 |
| **gbrain brain (Postgres-backed since 2026-10-11)** | bundle → `gbrain-postgres/` (config.json, DB password, physical markers, `brain.dump.sql.zst` live pg_dump) | §6b — `restore-gbrain-postgres.sh` |
| AnkiTov-C/.goose state (recipes incl. verify-loop, briefs, offload manifest, memory) | bundle → `ankitov-c-goose-state.tar` | like AnkiTov/.goose: `tar -xf … -C /Volumes/YBG1TB4Mac/AnkiTov-C` |
| launchd agents, crontab, mutagen spec | bundle → `launchd/`, `crontab.txt`, `mutagen-restore.sh` | restore step 8 |
| Code repos (AnkiTov, AnkiTov-C, AnkiTov-Goose, buzz-hive) | **GitHub** (URLs in bundle `repos.tsv`, with recorded SHAs) | restore step 7 |
| Unpushed commits + uncommitted files (WIP) | bundle → `repo-wip/*.bundle`, `repo-wip/*.tar` | §7 manual |
| AnkiTov/.goose project state (agents, recipes, secrets) | bundle → `ankitov-goose-state.tar` | restore step 7 |
| The restore tooling itself | bundle → `scripts/env-deploy.sh`, `scripts/sync-sessions.sh` (also in AnkiTov-Goose repo) | §4 |
| Production box ub3090 (RTX 3090) | **separate runbook**: `ub3090-recovery/README.md` in the AnkiTov repo — not covered here | — |

**Rule of thumb:** GitHub = code. This Drive folder = volatile state + sessions. The bundle is
self-contained for everything except full code clones.

---

## 1. Ground zero — bare machine prep (~15 min)

```bash
# 1. Command-line tools (gives you git)
xcode-select --install
# 2. Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# 3. The tools the restore needs
brew install rclone zstd sqlite3 mutagen jj bun opencode
# 4. goose itself
curl -fsSL https://goose.ai/install.sh | bash
# 5. Workspace root (adjust if the new disk isn't named YBG1TB4Mac — then also export
#    WORKSPACE_ROOT=/your/path for every env-deploy/sync-sessions command below)
mkdir -p /Volumes/YBG1TB4Mac
```

## 2. Connect rclone to this Drive folder

`client_id` / `client_secret`: **see Appendix B** (your own OAuth client — the shared rclone
one is being retired during 2026).

```bash
rclone config create gdrive drive \
  client_id='<APPENDIX-B-CLIENT-ID>' \
  client_secret='<APPENDIX-B-SECRET>' \
  root_folder_id='1DlvAUG4M-aGGI307kIXWXZfp-55mTRxp'
rclone lsf gdrive:          # must list this folder's contents
```

A browser opens → sign in with the Google account that owns this Drive → allow.
(The OAuth token lands in `~/.config/rclone/rclone.conf` — back it up with the next capture.)

## 3. Download the bundle

```bash
BUNDLE_ROOT=/Volumes/YBG1TB4Mac/goose-env-bundles
rclone copy gdrive:goose-env-ybgmacmini-20261010-232116 \
  $BUNDLE_ROOT/goose-env-ybgmacmini-20261010-232116 -P
cd $BUNDLE_ROOT/goose-env-ybgmacmini-20261010-232116 && shasum -a 256 -c SHA256SUMS
```

## 4. Run the restore (the bundle drives everything)

```bash
bash $BUNDLE_ROOT/goose-env-ybgmacmini-20261010-232116/scripts/env-deploy.sh \
  restore $BUNDLE_ROOT/goose-env-ybgmacmini-20261010-232116
```

It asks `Proceed? [y/N]` (set `FORCE=1` to skip). What it does, in order:
1. goose binary check/install → 2. brew tools → 3. `~/.config/goose` (existing dirs are moved
aside to `*.pre-restore.<ts>`, never deleted) → 4. `~/.local/share/goose` (sessions/ untouched)
→ 5. opencode → 6. gbrain wrappers → 7. **clones all repos from `repos.tsv` and checks out the
recorded SHAs**; unpushed bundles fetched as `refs/remotes/wipbundle/*`; AnkiTov/.goose state
→ 8. sessions via sync-sessions.sh, launchd agents loaded, crontab merged.

## 5. Sessions (if step 8 needs the manual path)

```bash
# Quit goose first. Option A — straight from the bundle:
zstd -d -c $BUNDLE_ROOT/goose-env-ybgmacmini-20261010-232116/sessions-ybgmacmini.db.zst \
  > ~/.local/share/goose/sessions/sessions.db
rm -f ~/.local/share/goose/sessions/sessions.db-{wal,shm}
# Option B — from the git archive:
bash .../scripts/sync-sessions.sh pull && bash .../scripts/sync-sessions.sh restore ybgmacmini
# Verify:
sqlite3 ~/.local/share/goose/sessions/sessions.db "PRAGMA quick_check; SELECT COUNT(*) FROM sessions;"
```

## 6. Manual checklist after restore (things no script should decide for you)

- `goose --version` && `goose session list` — chats are back; API keys in `~/.config/goose/secrets.yaml` present.
- **Paths changed?** (disk not named `YBG1TB4Mac`) → export `WORKSPACE_ROOT` / `GOOSE_WS` / `ANKITOV` / `ANKITOV_C` for every script run; also fix `mutagen-restore.sh` paths before running it.
- **Uncommitted WIP is NOT auto-applied** — per repo: `tar -xf $B/repo-wip/<repo>-uncommitted.tar -C <repo-root>`; unpushed commits are in `refs/remotes/wipbundle/*` — merge/reset deliberately.
- **Scheduled recipes:** at capture time `projects.json`/`schedule.json` were recovered from a STALE Aug-2025 `.bak` (live copies lived in `/tmp`). Verify `~/.local/share/goose/scheduled_recipes` + schedule.json and re-check schedules.
- Rebuild by design (not in bundle): `AnkiTov/.goose/venvs`, `~/.bun` packages, scratch/offload.
- gbrain: run §6b (Postgres brain) FIRST, then verify `gbrain status` shows all sources OK and `gbrain doctor` passes. The gbrain HTTP LaunchAgent (`user.ybg.gbrain-serve`) is **disabled on purpose** — the brain is Postgres-backed and concurrent stdio clients are safe; do NOT recreate it.
- Mutagen: `bash $B/mutagen-restore.sh` (edit paths first). NEVER mutagen-sync the live sessions dir.
- End-to-end: `env-deploy.sh doctor` → expect ALL CRITICAL CHECKS PASS.

## 6b. gbrain brain (Postgres-backed) — restore

Since the 2026-10-11 graduation the brain lives in a dedicated Postgres container
(`gbrain-postgres`, image `pgvector/pgvector:pg17`, port 127.0.0.1:5433, volume
`gbrain_pgdata`) — NOT in a file. The bundle carries a live `pg_dump` plus everything
needed to recreate it:

```bash
# 1. Recreate container + schema + data + gbrain config (one command):
bash $B/gbrain-postgres/restore-gbrain-postgres.sh
#    (runs: docker run pgvector/pgvector:pg17 → CREATE EXTENSION vector →
#     zstd -dc brain.dump.sql.zst | psql → installs ~/.gbrain/config.json)

# 2. gbrain CLI itself (bun global, NOT in bundle by design):
bun add -g github:garrytan/gbrain
cp $B/bun-gbrain/gbrain-mcp ~/.bun/bin/ && chmod +x ~/.bun/bin/gbrain-mcp

# 3. Verify:
gbrain status          # all sources OK, embed=100%
gbrain doctor          # no failing checks
printf '…initialize+tools/list…' | gbrain serve --surface starter   # 35 tools

# 4. goose side: the gbrain extension entry in ~/.config/goose/config.yaml
#    (restored with goose-config.tar) points at ~/.bun/bin/gbrain-mcp — nothing to edit.
```

Notes:
- `gbrain-postgres/backups/` in the bundle holds the DB password and the physical-root
  ownership markers (needed only if a managed source's checkout identity is ever questioned).
- The pre-migration PGLite backup (`brain-pglite-2026-10-11.tar.gz`, 379 MB) lived only on
  the dead machine's disk and is NOT in the bundle — it is redundant: the pg_dump contains
  the same memory, migrated.
- Concurrent gbrain clients (goose + Buzz agents) are safe: Postgres handles concurrency;
  there is no single-writer lock anymore.

## 7. If GitHub is also unreachable

The bundle alone restores: goose state, sessions, opencode, gbrain, launchd/cron/mutagen, WIP
tars, AnkiTov/.goose. It does **not** contain full code clones (only SHAs + WIP) — GitHub is the
code store of record. Re-point repos.tsv URLs to whatever mirror exists, or skip step 7 and
re-clone later; everything else works.

## 8. After you're back — restart the backup cycle

```bash
bash .../scripts/env-deploy.sh capture          # fresh bundle (sessions snapshot included)
rclone copy $BUNDLE_ROOT/goose-env-<new> gdrive:goose-env-<new> -P
bash .../scripts/sync-sessions.sh push          # fresh sessions git archive
bash .../scripts/env-deploy.sh doctor
```

---

## Appendix A — identifiers

- Drive folder ID: `1DlvAUG4M-aGGI307kIXWXZfp-55mTRxp` · bundle: `goose-env-ybgmacmini-20261010-232116` (297.7 MiB, 22 files)
- GitHub: `yitzhakbg/AnkiTov` · `yitzhakbg/AnkiTov-C` · `yitzhakbg/AnkiTov-Goose` · `yitzhakbg/AnkiTov-Sessions` (sessions archive) · `block/buzz` (buzz-hive, branch ankitov-hive)
- Recorded SHAs at capture: AnkiTov `a1be03b` (main) · AnkiTov-C `4f9559b` (detached) · AnkiTov-Goose `9cb9b52` (main)
- Machines: Mac = `ybgmacmini` · laptop = `ybgxps` (tailscale `ybg@100.68.132.81`, ssh alias `ybgxps`)
- Key paths: workspace `/Volumes/YBG1TB4Mac` · goose ws `AnkiTov-goose/` · main `AnkiTov/` · C checkout `AnkiTov-C/` · bundles `goose-env-bundles/`
- Sessions DB: `~/.local/share/goose/sessions/sessions.db` (SQLite WAL — never two-way-sync live)

## Appendix B — rclone OAuth client (your own client_id)

- client_id: `PENDING — paste after creating in Google Cloud Console`
- client_secret: `PENDING`

> ⚠️ **This copy is the public-safe template** — the AnkiTov-Goose repo is PUBLIC, so real
> credentials are intentionally NOT stored here. The **filled master** (real client_id/secret
> in Appendix B) lives at `goose-env-bundles/DISASTER-RECOVERY.md` on the machine and at the
> Drive folder root; `env-deploy.sh capture` copies the filled master into every bundle.
> If you change this file's structure, mirror the edit into the filled master (and leave
> Appendix B as PENDING here).

- How to create: https://rclone.org/drive/#making-your-own-client-id — API Console → enable
  **Google Drive API** → Credentials → configure OAuth consent screen (External, add yourself
  as test user, scopes `.../auth/drive` + `.../auth/drive.metadata.readonly` + `.../auth/docs`)
  → Overview → Create OAuth client → **Desktop app** → copy ID + secret → Publish app.
- If the token ever expires/breaks: just re-run the §2 `rclone config create` — same client, new token.
