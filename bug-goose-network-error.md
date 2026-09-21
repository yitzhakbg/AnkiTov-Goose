# Bug: "Network error: Could not connect to <provider-host>:<port>" for a custom LLM provider is a hard, non-recoverable failure in Desktop — only restarting the app unblocks the session

**Filed against:** `aaif-goose/goose` (Goose Desktop, AAIF)

> 💡 Before filing, please check common issues: https://goose-docs.ai/docs/troubleshooting
> 📦 A diagnostics zip is attached/referenced below.

---

## Describe the bug

When the active provider is a **custom, self-hosted LLM endpoint** (a custom "OpenAI-compatible" provider whose `base_url` points at a box on my Tailscale tailnet), every message I send fails with the exact error below — and **no amount of resending works**. The *only* thing that recovers the session is **quitting and relaunching Goose**.

```
Network error: Could not connect to 100.116.49.86:18020 — check your network connection and try again.

Please resend your message to try again.
```

I have confirmed (while the error was showing) that the provider endpoint was **not** actually down:

- `ping 100.116.49.86` → 0% loss, ~1.5 ms RTT (direct LAN link, not a relay)
- `curl http://100.116.49.86:18020/v1/models` → `HTTP 401` in ~3 ms (server up, auth required)

So this is a **client-side connect/transport failure in how Goose opens the HTTP connection to a custom provider**, surfaced as a dead end that blocks the whole chat until the app is restarted.

The endpoint in question is my local `qwen3.8-27b` running under vLLM on the machine `ub3090`, reached over Tailscale. The address `100.116.49.86:18020` is a **custom-provider `base_url`**, not a Goose ACP/serve endpoint (those bind to `127.0.0.1` on a random ephemeral port per launch, e.g. `wss://127.0.0.1:54010/acp`).

---

## To Reproduce

1. Configure a **custom OpenAI-compatible provider** whose `base_url` is a self-hosted endpoint reachable over a private network / tailnet, e.g. `http://<tailscale-ip>:18020/v1` (my case: `custom_qwen_ub3090`, vLLM serving `qwen3.8-27b`).
2. Set that provider as the **active provider**.
3. Start a new chat in **Goose Desktop** and send any message.
4. Observe that (re)connection to the provider fails and the error above is shown for **every** message.
5. Resend the message several times → same error, no recovery.
6. **Quit Goose and relaunch** → the same message now succeeds (the connect race / stale transport is cleared).

Notes on the failure window (from my side): the endpoint was healthy before and after (ping 1.5 ms, HTTP 401), so the window in which Goose *cannot* open the TCP/TLS connect is short enough that a fresh process recovers but in-place retries do not.

---

## Expected behavior

When a transient connect failure occurs against a **custom / self-hosted provider**, Goose should:

1. **Retry in the background** with exponential backoff (connect-level errors like `ECONNREFUSED`/timeout/`is_connect` should be retryable — they already map to `ProviderError::NetworkError`, which `should_retry()` in `crates/goose/src/providers/retry.rs` lists as retryable), so a transient tailnet/link blip does not lock the user out.
2. If a **retry is genuinely in progress**, the "Please resend your message to try again." prompt should be replaced with an accurate state (e.g. "reconnecting (2/3)…") instead of telling the user to resend a message that is already failing on the transport layer.
3. Provide a **non-restart recovery path**: an in-app "Retry" that re-opens the provider transport, and/or a "Test connection" button in provider settings, so the user doesn't have to kill the whole app.

Today: **only quitting and relaunching unblocks the session.**

---

## Root-cause pointers for the maintainer

This message is produced here (current `main` @ `c6a3b5b4e`):

```rust
// crates/goose-providers/src/errors.rs  — fn provider_error_from_reqwest
fn is_network_error(err: &reqwest::Error) -> bool {
    err.is_connect() || err.is_timeout() || (err.status().is_none() && err.is_request())
}

// ...
} else if error.is_connect() {
    if let Some(url) = error.url() {
        if let Some(host) = url.host_str() {
            let port_info = url.port().map(|p| format!(":{}", p)).unwrap_or_default();
            format!("Could not connect to {}{} — check your network connection and try again.", host, port_info)
        } ...
```

So `100.116.49.86:18020` is literally the **custom-provider request URL** (`host` + `:port`), and the failure is a **reqwest connect error** (`is_connect()`) — i.e. the TCP/TLS connect to the custom provider never completed on that attempt.

Retry plumbing that appears to exist but does not recover in the Desktop/ACP path:

- `crates/goose/src/providers/retry.rs` → `should_retry()` returns `true` for `ProviderError::NetworkError(_)`; `retry_operation()` loops up to `max_retries` (default 3) with exponential backoff.
- Observed: in the **custom-provider / Desktop (Electron over ACP)** path this does not surface as a working background retry — the `NetworkError` is returned to the client and rendered as a dead-end "resend" prompt. Worth confirming whether `retry_operation` is actually on the code path the Desktop client's provider call takes, and whether the ACP transport drops/propagates the retry rather than surfacing it.

Hypotheses to check (I can reproduce/confirm on my side with a diagnostics zip):
- The connect race happens right after `goose serve`/ACP backend (re)start or after an idle gap; the reqwest `Connector` may not be re-established in place, so in-process retries keep hitting the same dead socket until the process restarts.
- The "resend" button re-issues the LLM call on the **same transport** instead of a fresh connect, so it deterministically fails the same way.

---

## Please provide the following information

- **OS & Arch:** macOS 26.6.2 (BuildVersion 25G83), Darwin 25.6.0, arm64 (Apple M-series, `ybgMacMini`)
- **Interface:** UI (Goose **Desktop** — Electron app, `com.electron.goose`)
- **Version:** Goose Desktop **1.38.0** (`/Users/ybg/.local/bin/goose` → Mach-O arm64)
- **Extensions enabled:** developer (default set); plus local extensions (codegraph, headroom, apps, analyze) — none network/LLM-related to the failure
- **Provider & Model:** **Custom provider** `custom_qwen_ub3090` (engine `openai`/OpenAI-compatible), model **`qwen3.8-27b`**, served by **vLLM** on host `ub3090`
  - `base_url`: `http://100.116.49.86:18020/v1` (Tailscale IP; previous value was the LAN IP `http://192.168.1.9:18020/v1` — both fail identically when the connect window closes, so it is **not** an IP-scheme issue)
  - Network path: Tailscale tailnet, **direct** link (not relay) — `ub3090` is `192.168.1.9:41641`, RTT ~1.5 ms
- **`active_provider` in config:** `custom_qwen_ub3090`

---

## Diagnostics

I can attach a `diagnostics_{session_id}.json` bundle (per https://goose-docs.ai/docs/troubleshooting/diagnostics-and-reporting/).

Relevant local evidence I already captured:
- `lsof -nP -iTCP:18020` during the failure window → the Goose process had an `ESTABLISHED`/attempted socket to `100.116.49.86:18020` (i.e. the request *did* target the provider URL, not a Goose backend).
- `~/Library/Application Support/goose/logs/startup/goose-serve-startup-*.json` → Goose's own ACP backend is `wss://127.0.0.1:<ephemeral>/acp`; the `100.x` address is only reachable from the **custom-provider** `base_url`, confirming the failing hop is the LLM request, not the ACP session.
- `main.log` around the incident shows repeated `Starting goose serve … on port <port>` / `Terminating goose serve` cycles and `Network online status: undefined` — consistent with the app repeatedly cycling its local serve transport around the custom-provider failure.

---

## Additional context

- This is the **second** time in a row I've hit it; both times **only a full restart** recovered.
- Workarounds I have used: switch `active_provider` to a different provider and switch back; or restart the app. Neither is a fix — they confirm the issue is the in-process transport to the *custom* provider.
- Not specific to Qwen/vLLM: any custom OpenAI-compatible provider over a private network is exposed to this (LM Studio / llama.cpp / vLLM all share the `openai` engine + `base_url` path).
- Related issues I found (not duplicates, but worth cross-linking):
  - `#11895` — Network error using LM Studio API
  - `#3979` — Goose connection errors despite functional llama.cpp server
  - `#10917` — Ensure all retryable provider errors are retried with backoff and UI feedback
  - `#9921` — TUI ACP handshake `Method not found` (different transport, included for completeness)

**Suggested scope:** treat as *bug + enhancement* — (a) make `NetworkError`/connect failures genuinely retry in the Desktop/ACP custom-provider path, and (b) replace the "Please resend" dead-end with a real in-app reconnect + provider "Test connection" affordance so a full restart is no longer required.
