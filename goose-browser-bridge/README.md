# Goose Browser Bridge

A thin Chromium Side Panel extension (Brave / Chrome / Helium) that attaches directly to a dedicated local `goose serve` ACP process over WebSocket (`ws://127.0.0.1:3285/acp`), plus a macOS LaunchAgent and a CLI helper to manage it.

## Layout

```
goose-browser-bridge/
├── extension/                        # MV3 extension source (load unpacked from here)
│   ├── manifest.json
│   ├── background.js
│   ├── sidepanel.html
│   ├── sidepanel.js
│   └── README.md                     # user-facing docs (setup, daily use, fixes)
├── goose-browser-bridge.sh           # CLI helper (set-origin / start / stop / restart / status / secret / test)
├── com.goose.serve.browser.plist     # macOS LaunchAgent template (REPLACE_WITH_HEX_SECRET placeholder)
├── PUBLISHING.md                     # How to publish to the Chrome Web Store + key/secret handling
└── README.md                         # This file
```

## Quick Start (Local, Unpacked)

1. Copy the extension to a stable path and load it unpacked:
   ```bash
   mkdir -p ~/.local/share/goose-browser-ext
   cp -a extension/. ~/.local/share/goose-browser-ext/
   ```
   Open `brave://extensions` (or `chrome://extensions`), enable **Developer mode**, click **Load unpacked**, and select `~/.local/share/goose-browser-ext`.
2. Copy the 32-character **Extension ID** shown on the card.
3. Generate a secret, install the LaunchAgent, bind the origin, and start:
   ```bash
   SECRET=$(openssl rand -hex 32)
   mkdir -p ~/.local/share/goose-browser-ext
   printf '%s\n' "$SECRET" > ~/.local/share/goose-browser-ext/.secret
   chmod 600 ~/.local/share/goose-browser-ext/.secret

   sed "s|REPLACE_WITH_HEX_SECRET|$SECRET|; s|REPLACE_WITH_EXTENSION_ID|<EXT_ID>|" \
     com.goose.serve.browser.plist > ~/Library/LaunchAgents/com.goose.serve.browser.plist
   chmod 600 ~/Library/LaunchAgents/com.goose.serve.browser.plist

   ~/bin/goose-browser-bridge start   # or: cp goose-browser-bridge.sh ~/bin/goose-browser-bridge && chmod +x ~/bin/goose-browser-bridge
   ~/bin/goose-browser-bridge test
   ```
4. Click the **Goose Bridge** toolbar icon, expand **Connection**, paste the secret + your default `cwd`, and click **Save & Connect**.

## What It Does

- **Shared goose context:** The Side Panel speaks ACP (JSON-RPC 2.0) directly to `goose serve` — `initialize`, `session/list`, `session/new`, `session/load`, `session/prompt`, `session/cancel`, `session/set_mode`, `session/close`.
- **Approve-mode enforcement:** After `session/load`, the extension captures the session's original `modes.currentModeId`, calls `session/set_mode` (`modeId: "approve"`), and restores the original mode before `session/close` or `Desktop ↗` handoff. This guarantees every tool call waits for explicit sidebar approval.
- **No `cwd` clobbering:** `session/load` refuses to run if `session.cwd` is missing (prevents overwriting `working_dir` in `sessions.db` with a bogus `"/"`).
- **Bounded history replay:** `session/load` sends `_meta: { replayTail: 20 }` (configurable, `0` = all) so large sessions don't flood the sidebar DOM.
- **Desktop handoff:** `Desktop ↗` opens `goose://resume/<sessionId>`; the original mode is restored first so Desktop resumes in its own mode.
- **Auto-start:** The LaunchAgent (`RunAtLoad` + `KeepAlive`) starts `goose serve` at login and restarts it if it exits. The extension re-registers its Side Panel behavior and context menu on every browser startup (`chrome.runtime.onStartup`).

## Security Notes

- The shared secret lives in `~/.local/share/goose-browser-ext/.secret` (`0600`) and in the LaunchAgent plist (`0600`). Never commit it — the repo copy uses a `REPLACE_WITH_HEX_SECRET` placeholder.
- `--allowed-origin` is an exact-origin allowlist (replaces the default loopback origins), so only your loaded extension ID can open the WebSocket.
- `GOOSE_MODE=approve` + per-session `session/set_mode("approve")` means tool calls always require explicit human approval in the sidebar.

## Backup / Revert

A full pre-change Goose backup (config, data, sessions.db snapshot, app support, LaunchAgents, binaries) lives at:
`/Volumes/YBG1TB4Mac/goose-env-bundles/goose-full-backup-20261122-123355/` — run `RESTORE.sh` inside it to revert everything.

To remove only the browser bridge:
```bash
goose-browser-bridge stop
rm -f ~/Library/LaunchAgents/com.goose.serve.browser.plist ~/bin/goose-browser-bridge
rm -rf ~/.local/share/goose-browser-ext
```
