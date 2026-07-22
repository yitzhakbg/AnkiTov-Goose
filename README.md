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

## Repository Structure

```
ankitov-goose/
├── bootstrap.sh                  🚀  Master setup script
├── scripts/
│   └── deploy-headroom.sh        🚀  Headroom proxy installer (macOS + Linux)
├── config/                        Goose configuration
│   ├── global-config.yaml         ~/.config/goose/config.yaml
│   └── project-config.yaml        AnkiTov project config (goose_config.yaml)
├── custom_providers/              Custom LLM provider definitions
│   └── custom_agnes.json          Agnes AI provider
├── recipes/                       System-level Goose recipes
│   ├── automated-video-generator-review.yaml
│   ├── gbrain-reminder.yaml
│   └── topcoat-review.yaml
├── scheduled_recipes/             Cron-triggered recipe jobs
│   ├── agent_created_*.yaml       13 scheduled tasks
│   └── goose-openclaw-alternatives.yaml
├── apps/                          Goose HTML apps
│   ├── ankitov-management-console.html        (64 KB)
│   ├── ankitov-management-console-v2.html     (189 KB)
│   └── clock.html                             (7 KB)
├── memory/global/                 Goose global memory store
│   ├── ankiplayground.txt         AnkiPlayGround profiles runbook
│   ├── goose-config.txt           Goose configuration reference
│   ├── gui-rewire-v2.txt          Management Console evolution
│   ├── i18n-system.txt            i18n architecture & translation gate
│   ├── project-context.txt        Key file locations & architecture
│   ├── project-documentation.txt  Documentation layers & mdBook
│   ├── scheduled-tasks.txt        Pending & active scheduled tasks
│   └── wasm-strategy.txt          WASM tactical extraction plan
├── schedule.json                   Scheduled job registry (templated)
├── projects.json                   Project tracking metadata (templated)
└── .gitignore                      Session files, OS files, bak files
```

## What Goes Where

| What | Where | Managed By |
|---|---|---|
| **Global Goose config** | `~/.config/goose/config.yaml` | This repo |
| **Custom providers** | `~/.config/goose/custom_providers/` | This repo |
| **Global memory** | `~/.config/goose/memory/` | This repo |
| **System recipes** | `~/.local/share/goose/recipes/` | This repo |
| **Scheduled recipes** | `~/.local/share/goose/scheduled_recipes/` | This repo |
| **Goose apps** | `~/.local/share/goose/apps/` | This repo |
| **Job registry** | `~/.local/share/goose/schedule.json` | This repo |
| **Project config** | `ankitov/goose_config.yaml` | [AnkiTov repo](https://github.com/ankitov/ankitov) |
| **AnkiTov slash commands** | `ankitov/recipes/` | [AnkiTov repo](https://github.com/ankitov/ankitov) |
| **Summon subagents** | `ankitov/.goose/recipes/` | [AnkiTov repo](https://github.com/ankitov/ankitov) |
| **Project memory** | `ankitov/.goose/memory/` | [AnkiTov repo](https://github.com/ankitov/ankitov) |

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

# 2. Bootstrap
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

# 4. Verify and start
cd ~/ankitov
goose session -r
```

### What bootstrap.sh does

The bootstrap script is idempotent — run it as many times as you like. It:

1. **Symlinks** all Goose files from this repo into `~/.config/goose/` and `~/.local/share/goose/`
2. **Substitutes paths** — resolves `{{GOOSE_HOME}}` and `{{ANKITOV_REPO}}` template variables in `schedule.json` and `projects.json` to your actual paths
3. **Backs up** any existing files before overwriting (appends timestamp, e.g. `.bak.1712345678`)
4. **Links AnkiTov project recipes** — connects slash commands, subrecipes, and summon subagents from the cloned AnkiTov repo
5. **Verifies** — reports file counts for every linked directory

### Environment Variables

| Variable | Purpose | Required |
|---|---|---|
| `OPENROUTER_API_KEY` | OpenRouter API key for LLM access | Yes |
| `CUSTOM_AGNES_API_KEY` | Agnes AI provider key | Optional |
| `GOOSE_MODE` | Operator mode (`smart_approve` recommended) | Recommended |
| `GOOSE_TOOLSHIM` | Enable tool shim (set to `true`) | Recommended |

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
- **Budget gate binary** — compiled from the AnkiTov repo
- **API keys** — set via environment variables only

### Path templating

The `schedule.json` and `projects.json` use `{{GOOSE_HOME}}` and `{{ANKITOV_REPO}}` template variables that `bootstrap.sh` substitutes at install time. This keeps the repo portable across machines and directory layouts.

## License

MIT — use freely, adapt as needed.
>>>>>>> 28086cb (Initial commit: AnkiTov Goose environment)
