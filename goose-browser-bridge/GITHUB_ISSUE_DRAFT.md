# Goose Bridge — Chrome extension that attaches a browser Side Panel directly to `goose serve` (ACP)

## Summary

A working, self-contained **Chrome MV3 Side Panel extension** (~590 lines, zero dependencies, no build step) that turns any Chromium browser (Chrome / Brave / Helium / Edge) into a **first-class goose client**. It speaks ACP (JSON-RPC 2.0) over WebSocket directly to a local `goose serve` process — no second agent runtime, no duplicated context, no proxy layer.

**Repo with full source + docs:** https://github.com/yitzhakbg/AnkiTov-Goose/tree/main/goose-browser-bridge

We'd like to publish it to the Chrome Web Store as an official/community goose companion, and are opening this issue to (a) share the working implementation, (b) get feedback on the approach, and (c) coordinate on anything upstream (docs, `goose serve` flags, deep links) that would make the published version smoother.

---

## Why this matters

goose already separates its harness from its UI via ACP, and `goose serve` exposes ACP over HTTP + WebSocket with browser-friendly auth (`?token=` query param) and CORS (`--allowed-origin`). That means a **thin browser extension can be a full goose client** — sharing the exact same sessions, memory, and tools as Desktop/CLI — with ~600 lines of vanilla JS.

What you get in the browser:

- **Sidebar chat with the real goose** — same `sessions.db`, same providers, same extensions as Desktop/CLI (`session/list` → `session/load` / `session/new` → `session/prompt`).
- **Page/selection injection** — right-click any text → "Send selection / page to Goose", or one click to grab the current tab's title + URL.
- **Tool-call approvals in the sidebar** — every `session/request_permission` renders a card with the tool's arguments and allow/reject buttons; nothing executes without an explicit click.
- **Desktop handoff** — one click opens `goose://resume/<sessionId>` to continue the same conversation in Goose Desktop.
- **Auto-start backend** — a small LaunchAgent (macOS) / systemd unit (Linux) keeps `goose serve` on `127.0.0.1:3285` running at login.

## Architecture (single harness, no parallel agent)

```
┌─────────────────────────────┐        ws://127.0.0.1:3285/acp?token=…
│  Chromium Side Panel (MV3)  │◄──────────────────────────────────────┐
│  sidepanel.js (ACP client)  │                                       │
└─────────────┬───────────────┘                                       │
              │ chrome.storage.session (pendingClip)                  │
┌─────────────▼───────────────┐   ┌───────────────────────────────────┴──┐
│  background.js (SW)         │   │  goose serve --platform desktop      │
│  context menu + side panel  │   │  --allowed-origin chrome-extension://│
└─────────────────────────────┘   │  (same sessions.db as Desktop/CLI)   │
                                  └──────────────────────────────────────┘
```

- **Zero host permissions** — manifest requests only `sidePanel`, `tabs`, `contextMenus`, `storage`. No `<all_urls>`, no content scripts, no remote code.
- **Exact-origin CORS** — the LaunchAgent passes `--allowed-origin chrome-extension://<EXT_ID>`, so only the installed extension can open the WebSocket.
- **Shared secret** — `GOOSE_SERVER__SECRET_KEY` is generated locally per machine (`openssl rand -hex 32`); the extension is a dumb client that authenticates with whatever the local server was started with. No global password exists anywhere.

## Gotchas we hit and fixed (useful reference for other ACP client authors)

These are all verified against goose 1.60.2 source + live smoke tests:

1. **`GOOSE_MODE=approve` does NOT cover `session/load`.** It only sets the default for `session/new`; `session/load` restores `session.goose_mode` from `sessions.db` (usually `auto`), silently re-enabling auto-approval. **Fix:** after `session/load`, the client must call `session/set_mode` (`modeId: "approve"`) — and remember the original mode to restore before `session/close` or handoff.
2. **`session/load` mutates `working_dir` in `sessions.db`** whenever the passed `cwd` differs from the stored one. A naive `cwd: meta?.cwd || "/"` fallback will clobber real project directories. **Fix:** refuse to load if `session.cwd` is missing; never fall back.
3. **`--platform desktop` matters** for `goose serve` when you want Desktop-equivalent platform identity/extension behavior (the CLI default is `--platform cli`).
4. **Unbounded replay on `session/load`.** Large sessions replay their entire history as `session/update` notifications. **Fix:** pass `_meta: { replayTail: 20 }` (server honors it and returns `replaySkipped` in the response `_meta`).
5. **`session/close` on switch** prevents orphaned in-memory agents accumulating in the `goose serve` process when the user hops between sessions.
6. **`chrome.runtime.onStartup`** is needed (not just `onInstalled`) to re-register Side Panel behavior + context menus after every browser restart.

## What's in the repo

```
goose-browser-bridge/
├── extension/                  # MV3 source: manifest.json, background.js, sidepanel.html, sidepanel.js
├── goose-browser-bridge.sh     # CLI: set-origin / start / stop / restart / status / secret / test
├── com.goose.serve.browser.plist  # macOS LaunchAgent template (secret placeholder)
├── install.sh                  # one-shot installer (copies ext, generates secret, renders plist, loads agent)
├── README.md                   # setup + daily use + security notes
└── PUBLISHING.md               # Chrome Web Store packaging + key/secret model
```

`install.sh` auto-derives the extension ID from `manifest.json`'s `"key"` field when present (published builds) or prompts for it (unpacked builds), so the same script works pre- and post-publication.

## What we're asking

1. **Feedback on the approach** — is a browser Side Panel as an official goose client something goose wants to endorse/link from the docs? (The [Build an app over ACP](https://goose-docs.ai/docs/oi-kit/acp) doc already points in this direction; this is a concrete, working instance.)
2. **Chrome Web Store publication** — we plan to publish under a goose-aligned name ("Goose Bridge"). Happy to transfer/hand over to the aaif-goose org if preferred, or keep it community-maintained with a docs link. What's the preferred path?
3. **Small upstream asks** (optional, would improve the published UX):
   - Document `_meta: { replayTail }` on `session/load` (it's implemented but not in the ACP docs).
   - Consider a `goose serve` flag to force a minimum mode for all sessions (e.g. `--min-mode approve`) so clients can't accidentally inherit `auto` from `sessions.db` via `session/load`.
   - The `goose://resume/<id>` deep link is great; documenting it publicly would help third-party clients.

Happy to iterate on any of this. The extension is MIT/Apache-2.0-licensable (our choice to match goose's licensing), fully local, and sends nothing off-machine.
