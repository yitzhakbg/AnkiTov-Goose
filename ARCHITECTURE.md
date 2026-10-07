# Architecture Portability for AnkiTov

This document catalogs architecture-dependent items that may work on the Apple Silicon Mac Mini (ARM64) but **not** on an Intel laptop (x86_64), and vice versa.

## Critical: Compiled Binaries (Must Match Architecture)

| Binary | ARM64 (Mac Mini) | x86_64 (Intel Laptop) | How to get |
|--------|------------------|----------------------|------------|
| **Goose** | `/Users/ybg/.local/bin/goose` (ARM64) | Must install x86_64 version | `brew install goose` or `cargo install goose` — Homebrew auto-detects |
| **ankitov-budget-gate** | `target/release/ankitov-budget-gate` (ARM64) | Must rebuild | `cd ankitov-budget-gate && cargo build --release` |
| **Anki.app** | `/Applications/Anki.app` (ARM64) | Must download Intel version | https://apps.ankiweb.net |
| **Python (mise)** | ARM64 binary via mise | mise auto-detects arch on install | `mise install python@3.12` |

### What bootstrap.sh does about this

- `bootstrap.sh` auto-detects architecture via `uname -m`
- It prints architecture-specific setup notes at the end
- The budget gate binary is **never** symlinked — it must be compiled on each machine

## Rust Toolchain

```bash
# On ARM64 Mac Mini (already set up):
rustup show
# → stable-aarch64-apple-darwin (active)

# On Intel laptop — install the correct target:
rustup target add x86_64-apple-darwin
```

The `rust-toolchain.toml` file pins to `stable` (no architecture override) — Rust automatically selects the right target for the host architecture.

## Homebrew Prefix Differences

| Architecture | Homebrew prefix |
|-------------|----------------|
| ARM64 (Apple Silicon) | `/opt/homebrew` |
| x86_64 (Intel) | `/usr/local` |

This affects where brew-installed packages live:

- **code-graph-mcp**: symlinked from brew prefix (`/opt/homebrew/bin/code-graph-mcp` or `/usr/local/bin/code-graph-mcp`)
  - Portable because bootstrap.sh uses just `"code-graph-mcp"` as the command name (resolved via PATH)
- **node, sqlite3, etc.**: Same pattern — portable via PATH resolution

## Path Templating (How bootstrap.sh Handles It)

The `bootstrap.sh` script substitutes these template variables at install time:

| Template variable | Replaced with | Used in |
|------------------|---------------|---------|
| `{{ANKITOV_REPO}}` | Path to cloned AnkiTov repo | `global-config.yaml`, `project-config.yaml`, `schedule.json`, `projects.json` |
| `{{HEADROOM_CMD}}` | Resolved headroom binary path | `global-config.yaml`, `project-config.yaml` |
| `{{GOOSE_SHELL_CMD}}` | Resolved goose-sh binary path | `global-config.yaml` |
| `{{GOOSE_HOME}}` | `~/.local/share/goose` | `schedule.json` |

The config files in this repo use these templates so they are **architecture-independent in source** — the substitution happens at install time on each machine.

## Items That DON'T Cross Between Machines

### macOS Keychain Dependency

The `headroom-proxy-start.sh` script on the Mac Mini uses macOS Keychain for API keys:

```bash
export OPENROUTER_API_KEY=$(security find-generic-password -a "ybg" -s "OpenRouter_API_Key" -w)
```

On a new machine, either:
- Add the same keychain entry: `security add-generic-password -a "$USER" -s "OpenRouter_API_Key" -w "sk-or-v1-..."`
- Or set the `OPENROUTER_API_KEY` environment variable directly (the script falls back)

The `deploy-headroom.sh` script in this repo generates a version that uses environment variables (`$OPENROUTER_API_KEY`) instead.

### External Volume Mount Point

The AnkiTov repo on this machine lives at `/Volumes/YBG1TB4Mac/AnkiTov` — an external SSD. On another machine, the repo may be cloned to a different path (e.g., `~/ankitov`). This is handled by the `{{ANKITOV_REPO}}` template variable.

### AnkiPlayGround Data

The `.env` file in the AnkiTov backend has hardcoded paths:

```
ANKIPLAYGROUND_PATH=/Volumes/YBG1TB4Mac/AnkiTov/AnkiPlayGround
ANKICOLLECTION_PATH="/Volumes/YBG1TB4Mac/AnkiTov/AnkiPlayGround/User 1/collection.anki2"
```

These are **not** managed by this repo — they live in `backend/.env` in the AnkiTov source repo. On a new machine, create a new `.env` with the correct paths.

### Session Database

Goose session data lives at `~/.local/share/goose/sessions.db` (SQLite). This is **not** in this repo — it's too large, machine-specific, and transient.

## Quick Setup Checklist for Intel Laptop

```bash
# 1. Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 2. Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. Install Goose
brew install goose

# 4. Clone repos
git clone https://github.com/yitzhakbg/AnkiTov.git ~/ankitov
git clone https://github.com/yitzhakbg/AnkiTov-Goose.git ~/ankitov-goose

# 5. Rebuild budget gate (MUST be compiled for Intel)
cd ~/ankitov/ankitov-budget-gate && cargo build --release

# 6. Install code graph
brew install code-graph-mcp

# 7. Bootstrap Goose environment
cd ~/ankitov-goose && bash bootstrap.sh ~/ankitov

# 8. Set environment variables
export OPENROUTER_API_KEY="sk-or-v1-..."
export GOOSE_MODE=smart_approve
export GOOSE_TOOLSHIM=true

# 9. Verify
cd ~/ankitov && cargo check && goose session -r
```

---

## AnkiTov i18n & local install (integration notes)

Cross-repo integration notes for the harness team. The product-side
reference is `ankitov/docs/ankitov-i18n-and-local-deploy.md`; this section is
the **harness-side** mirror. The one item the harness *owns* is called out
explicitly at the end.

### The standing i18n rule
*Every GUI-affecting string is translated into every supported language.*
EN is the source of truth. AnkiTov has two independent i18n surfaces that
both enforce this:

- **Landing site (static):** source of truth is
  `ankitov/specs/launch/site/translations.csv` (13 language columns, `en`
  canonical). `build-site-i18n.py` compiles it to
  `locales/*.json` and is the **strict publish gate** (fails on a missing
  key, empty cell, or mojibake/mixed-script). `TRANSLATION_STATUS.md` is the
  DRAFT → VERIFIED cultural-QA gate; until a locale is VERIFIED the site
  serves it with **EN fallback** (`site-i18n.js`) so nothing renders blank.
- **Backend / dashboard (Rust):** one `backend/i18n/{locale}/main.ftl` per
  locale (13), compiled at build time by `fluent-templates static_loader!` in
  `backend/src/i18n.rs`; runtime override via `POST /api/v1/locale/set`;
  `is_rtl()` drives mirrored layout for RTL locales.

If a new GUI string is added to AnkiTov, it must be added to **both** the
landing CSV and the relevant `.ftl`, in all 13 languages, or the gate fails.

### One-click local install
`ankitov/install-locally.sh` (+ `docker-compose.local.yml`,
`.env.local.example`) brings up the whole stack **inside Docker on the
adopter's own `127.0.0.1`** — no domain, no cert, no Caddy, nothing exposed.
The adopter opens `http://localhost:5150`. `stop` / `wipe` subcommands manage
it. The static landing is shipped separately as a bundle
(`ankitov/scripts/launch/build-local-bundle.sh` →
`ankitov-local-bundle.tar.gz` → Cloudflare Pages `/ankitov-local/`), per
`ankitov/specs/launch/site/LOCAL-BUNDLE-DEPLOY.md`.

### Self-registration (no email to us)
`POST /api/v1/auth/register` is public. The role gate in
`ankitov/backend/src/controllers/auth.rs` allows self-signup for
**`student`** or **`teacher`** only; **`admin` is deliberately excluded**
(provisioned out-of-band by the operator). Unknown roles fall back to
`student`; `admin` returns a 400. This is the privilege-escalation gate —
nobody can self-promote to admin through the public endpoint.

### ⚠ Harness-owned: the Goose-paste `Content-Type` coercion
When a teacher pastes a deck from **Anki / Notion / Google Sheets** into the
import UI, the clipboard can arrive with an unexpected `Content-Type` and
the paste silently fails to bind. **The fix — a `Content-Type` coercion in
the paste handler (normalize the incoming content type before parsing the
paste payload) — belongs in THIS harness's paste path, not in the AnkiTov
product backend.** The product stays content-agnostic; the harness owns
clipboard/paste normalization. Do not move this logic into
`ankitov/backend/`; wire it into the Goose paste handler.