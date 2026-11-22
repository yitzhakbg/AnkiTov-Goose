# Goose Browser Bridge (MV3 Side Panel + ACP)

Thin Chromium Side Panel extension (Brave / Chrome / Helium) that attaches directly to a dedicated local `goose serve` ACP process over WebSocket (`ws://127.0.0.1:3285/acp`).

## Files & Locations

- Extension source (load unpacked from here): `~/.local/share/goose-browser-ext/`
  - `manifest.json`, `background.js`, `sidepanel.html`, `sidepanel.js`, `README.md`, `.secret`
- LaunchAgent (auto-starts `goose serve` on `127.0.0.1:3285`): `~/Library/LaunchAgents/com.goose.serve.browser.plist`
- CLI helper: `~/bin/goose-browser-bridge` (`set-origin`, `start`, `stop`, `restart`, `status`, `secret`, `test`)
- Pre-change full Goose backup: `/Volumes/YBG1TB4Mac/goose-env-bundles/goose-full-backup-20261122-123355/` (`RESTORE.sh`)

## What Was Fixed vs. the Initial Proposal

1. **`session/load` mode enforcement (`approve`):** `GOOSE_MODE=approve` on `goose serve` only sets the default for *new* sessions; `session/load` restores `session.goose_mode` from `sessions.db` (usually `auto`). After `session/load`, the extension immediately calls `session/set_mode` (`modeId: "approve"`) so every tool call waits for explicit approval in the sidebar. Before switching away, closing, or handing off to Desktop, you can also toggle/open in Desktop.
2. **No `cwd: "/"` clobber:** `session/load` mutates `working_dir` in `sessions.db` if passed a `cwd` that differs from the stored one. The extension refuses to load a session if `session.cwd` is missing rather than falling back to `"/"`.
3. **`--platform desktop` + `GOOSE_DISABLE_KEYRING=true`:** Added `--platform desktop` to `goose serve` and `GOOSE_DISABLE_KEYRING=true` in the LaunchAgent env so Desktop extensions/platform identity match and Keychain never blocks headless startup.
4. **Bounded history replay + clean session lifecycle:** `session/load` passes `_meta: { replayTail: 20 }` (configurable, `0` = all) so large sessions don't flood the sidebar DOM (`replaySkipped` banner shown). Also handles `session/close` when switching sessions, ignores `agent_thought_chunk` cleanly, shows tool input in permission cards, disables `Send` while a turn runs, and cancels pending promises on socket close.

## One-Time Setup (2 Minutes)

1. Open `brave://extensions` (or `chrome://extensions`), turn on **Developer mode**, click **Load unpacked**, and select:
   `~/.local/share/goose-browser-ext`
2. Copy the 32-character **Extension ID** shown on the card.
3. Bind that origin and start the LaunchAgent:
   ```bash
   goose-browser-bridge set-origin <EXT_ID>
   goose-browser-bridge start
   goose-browser-bridge test
   ```
4. Copy the shared secret:
   ```bash
   goose-browser-bridge secret
   ```
5. Click the **Goose Bridge** toolbar icon to open the Side Panel, expand **Connection**, paste the secret + your default `cwd` (e.g. `/Volumes/YBG1TB4Mac/AnkiTov-C`), and click **Save & Connect**.

## Daily Use

- **Send current page:** Click `+ Current Tab` in the sidebar, or right-click any selection/page and choose **Send selection / page to Goose**.
- **Continue an existing session:** Pick it from the session dropdown (shows only the last 20 turns by default).
- **Approve/reject tools:** Any tool call pauses on a yellow permission card showing its arguments; click **allow_once / allow_always / reject_once / reject_always**, or **Cancel & Open in Desktop ↗**.
- **Hand off to Goose Desktop:** Click **Desktop ↗** (`goose://resume/<sessionId>`). Note: because `:3285` and Desktop's bundled server are separate processes sharing `sessions.db`, Desktop opens a fresh resumed window synced from SQLite.
- **Stop / uninstall:** `goose-browser-bridge stop` (or run `RESTORE.sh` in the backup folder to revert everything).
