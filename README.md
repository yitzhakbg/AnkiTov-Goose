<p align="center">
  <img src="https://img.shields.io/badge/status-active-success" alt="Status: Active">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT">
  <img src="https://img.shields.io/badge/goose-smart__approve-8A2BE2" alt="Goose Mode: smart_approve">
</p>

# 🦆 AnkiTov Goose Environment

**Your entire Goose development environment for the AnkiTov project — config, recipes, apps, memory, and scheduled tasks — ready to clone and bootstrap on any machine.**

---

## Overview

The [AnkiTov](https://github.com/ankitov/ankitov) backend is a Rust-native knowledge retention infrastructure built with Loco.rs, SeaORM, and libSQL. This repository captures **everything Goose-related** about the AnkiTov development environment so you can reconstruct your full setup on a new machine in minutes.

Combined with the AnkiTov source repo, a single `bootstrap.sh` run:

- Links your global Goose config into place
- Installs all custom recipes, scheduled tasks, and summon subagents
- Registers your Goose apps and global memory store
- Wires up AnkiTov project recipes (slash commands, subrecipes, spec generator)
- Restores the scheduled job registry with correct paths
- **Resolves architecture-specific paths** (ARM64 vs x86_64)

## Cross-Architecture Support

This repository is designed to work on both **Apple Silicon (ARM64)** and **Intel (x86_64)** Macs, with architecture-dependent path resolution handled by `bootstrap.sh`. Key differences:

| Component | ARM64 Mac | Intel Mac |
|-----------|----------|-----------|
| Homebrew prefix | `/opt/homebrew` | `/usr/local` |
| Goose binary | brew-installs ARM64 | brew-installs x86_64 |
| Budget gate binary | must rebuild on target | must rebuild on target |
| Rust target | `aarch64-apple-darwin` | `x86_64-apple-darwin` |

See [ARCHITECTURE.md](ARCHITECTURE.md) for a full cross-platform portability audit.

## Repository Structure

```
ankitov-goose/
├── bootstrap.sh                  🚀  Master setup script (arch-aware)
├── ARCHITECTURE.md               🏛  Cross-platform portability audit
├── scripts/
│   └── deploy-headroom.sh        🚀  Headroom proxy installer (macOS + Linux)
├── config/                        Goose configuration (templated paths)
│   ├── global-config.yaml         ~/.config/goose/config.yaml
│   └── project-config.yaml        AnkiTov project config (goose_config.yaml)
├── custom_providers/              Custom LLM provider definitions
│   └── custom_agnes.json          Agnes AI provider
├── recipes/                       System-level Goose recipes
│   ├── automated-video-generator-review.yaml
│   ├── gbrain-reminder.yaml
│   └── topcoat-review.yaml
├── scheduled_recipes/             Cron-triggered recipe jobs
│   ├── agent_created_*.yaml       10 scheduled tasks
│   └── goose-openclaw-alternatives.yaml
├── apps/                          Goose HTML apps
│   ├── ankitov-management-console.html
│   ├── ankitov-management-console-v2.html
│   └── clock.html
├── memory/global/                 Goose global memory store
│   ├── ankiplayground.txt
│   ├── goose-config.txt
│   ├── gui-rewire-v2.txt
│   ├── i18n-system.txt
│   ├── project-context.txt
│   ├── project-documentation.txt
│   ├── scheduled-tasks.txt
│   └── wasm-strategy.txt
├── schedule.json                   Scheduled job registry (templated)
├── projects.json                   Project tracking metadata (templated)
└── .gitignore                      Session files, OS files, bak files
```

## What Goes Where

| What | Where | Managed By |
|---|---|---|
| **Global Goose config** | `~/.config/goose/config.yaml` | This repo (templated paths) |
| **Custom providers** | `~/.config/goose/custom_providers/` | This repo |
| **Global memory** | `~/.config/goose/memory/` | This repo |
| **System recipes** | `~/.local/share/goose/recipes/` | This repo |
| **Scheduled recipes** | `~/.local/share/goose/scheduled_recipes/` | This repo |
| **Goose apps** | `~/.local/share/goose/apps/` | This repo |
| **Job registry** | `~/.local/share/goose/schedule.json` | This repo (templated) |
| **Project config** | `ankitov/goose_config.yaml` | [AnkiTov repo](https://github.com/ankitov/ankitov) |
| **AnkiTov slash commands** | `ankitov/recipes/` | [AnkiTov repo](https://github.com/ankitov/ankitov) |
| **Summon subagents** | `ankitov/.goose/recipes/` | [AnkiTov repo](https://github.com/ankitov/ankitov) |
| **Project memory** | `ankitov/.goose/memory/` | [AnkiTov repo](https://github.com/ankitov/ankitov) |
| **Budget gate binary** | `ankitov/ankitov-budget-gate/target/release/` | Compiled locally (arch-specific) |

## Quick Start

### Prerequisites

- [Goose CLI](https://github.com/block/goose) installed (`brew install goose` or `cargo install goose`)
- [AnkiTov repo](https://github.com/ankitov/ankitov) cloned locally
- API keys for your configured providers (set as environment variables)

### Setup

```bash
# 1. Clone both repos
git clone https://github.com/ankitov/ankitov.git
git clone https://github.com/ankitov/ankitov-goose.git

# 2. Bootstrap (auto-detects architecture)
cd ankitov-goose
chmod +x bootstrap.sh
./bootstrap.sh ~/ankitov

# 3. Set environment variables
export OPENROUTER_API_KEY="sk-or-v1-..."
export CUSTOM_AGNES_API_KEY="..."
export GOOSE_MODE=smart_approve
export GOOSE_TOOLSHIM=true
export GOOSE_THINKING_EFFORT=off
export GOOSE_TELEMETRY_ENABLED=false

# 4. If on Intel laptop, rebuild budget gate:
cd ~/ankitov/ankitov-budget-gate && cargo build --release

# 5. Verify and start
cd ~/ankitov
goose session -r
```

### What bootstrap.sh does

The bootstrap script is idempotent — run it as many times as you like. It:

1. **Auto-detects architecture** (ARM64 vs x86_64) and prints portability notes
2. **Resolves headroom binary** via mise → PATH → common install locations
3. **Resolves goose-sh path** for the GOOSE_SHELL config
4. **Templates all config files** — substitutes `{{ANKITOV_REPO}}`, `{{HEADROOM_CMD}}`, `{{GOOSE_SHELL_CMD}}`, `{{GOOSE_HOME}}` with actual paths
5. **Symlinks** all Goose files from this repo into `~/.config/goose/` and `~/.local/share/goose/`
6. **Backs up** any existing files before overwriting (appends timestamp, e.g. `.bak.1712345678`)
7. **Links AnkiTov project recipes** — connects slash commands, subrecipes, and summon subagents from the cloned AnkiTov repo
8. **Verifies** — reports file counts for every linked directory

### Environment Variables

| Variable | Purpose | Required |
|---|---|---|
| `OPENROUTER_API_KEY` | OpenRouter API key for LLM access | Yes |
| `CUSTOM_AGNES_API_KEY` | Agnes AI provider key | Optional |
| `GOOSE_MODE` | Operator mode (`smart_approve` recommended) | Recommended |
| `GOOSE_TOOLSHIM` | Enable tool shim (set to `true`) | Recommended |

## Architecture Portability

This repo handles the following architecture-dependent concerns:

### Templated Paths (resolved by bootstrap.sh)
- `{{ANKITOV_REPO}}` — path to AnkiTov source repo
- `{{HEADROOM_CMD}}` — path to headroom binary (searched: mise → PATH → common install dirs)
- `{{GOOSE_SHELL_CMD}}` — path to goose-sh wrapper
- `{{GOOSE_HOME}}` — `~/.local/share/goose`

### Items requiring manual setup per machine
- **Budget gate binary**: Must be compiled natively (`cargo build --release`)
- **Anki.app**: Download architecture-specific version from ankiweb.net
- **Rust target**: Already handled by rustup's auto-detection
- **Goose binary**: Installed via brew (architecture-appropriate)

### Items NOT in this repo (machine-specific)
- **Session database** (`sessions.db`) — too large, machine-specific
- **Goose binary** — install via `brew` or `cargo`
- **Budget gate binary** — compiled from the AnkiTov repo
- **API keys** — set via environment variables only
- **backend/.env** — lives in AnkiTov repo, has machine-specific paths

## Path Templating

All config files in this repo use template variables that `bootstrap.sh` resolves at install time:

| Template | Resolved to |
|----------|-------------|
| `{{ANKITOV_REPO}}` | Absolute path to cloned AnkiTov repo |
| `{{HEADROOM_CMD}}` | Full path to headroom binary |
| `{{GOOSE_SHELL_CMD}}` | Full path to goose-sh |
| `{{GOOSE_HOME}}` | `~/.local/share/goose` |

This keeps the repo portable across machines and directory layouts.

## Design Decisions

### Why a separate repository?

- **Clean separation** — Goose configuration evolves independently of AnkiTov source code
- **Machine migration** — Clone + bootstrap = complete environment reconstruction
- **No bloat** — AnkiTov repo stays focused on product code, not developer tooling
- **Shareable** — Team members can clone the same Goose environment with their own API keys

### What's NOT in this repo

- **Session data** (`sessions.db`) — too large, machine-specific, and transient
- **Goose binary** — install via `brew` or `cargo`
- **AnkiTov source code** — cloned separately
- **Budget gate binary** — compiled from the AnkiTov repo (arch-specific)
- **API keys** — set via environment variables only
- **backend/.env** — machine-specific paths (AnkiTov repo)

## License

MIT — use freely, adapt as needed.