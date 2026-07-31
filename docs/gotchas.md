# AnkiTov Gotchas — Common AI Failure Points

> This file grows over time. Every time Goose gets something wrong, add it here.
> Referenced by `.goosehints` and `.goose/agents/` definitions.

## Rust

### Build & Test
- ❌ `cargo test` — Goose defaults to this. Must use `cargo nextest run`.
- ❌ `cargo check` from wrong directory — always `cd backend && cargo check`.
- ❌ Forgetting to check `ankitov-budget-gate/` — always check both crates.

### jj (Jujutsu)
- ❌ `jj mv` — jj has no native `mv` subcommand. Use `mv` + `jj status` for renames.
- ❌ `jj branch` — jj uses `bookmark`, not `branch`.
- ❌ `git` commands — jj is the VCS. Never use `git` unless explicitly told.
- ❌ `jj rebase` — jj uses `jj squash` or `jj edit` + `jj new` for history rewriting.

### Schema Changes
- ❌ Regular SeaORM migrations — must use `NoOpMigrator` pattern. All schema changes
  must be reversible.

### Macros & Attributes
- ❌ Forgetting `#[utoipa::path]` on new controller routes — planned but not yet
  on management controllers. Add proactively.

## Python

- ❌ `except:` — Goose writes bare excepts. Always specify exception type.
- ❌ `except Exception:` — still too broad. Catch specific exceptions.

## Shell

- ❌ `zsh` syntax — Goose sometimes produces zsh-isms. Always `bash`.
- ❌ Missing `set -euo pipefail` — required in all scripts.
- ❌ `timeout` command — not available on macOS. Use alternative patterns.

## Goose / TypeScript (code_execution)

- ❌ `const results = [];` — TypeScript infers `never[]`. Always use explicit type
  annotations: `const results: string[] = []`.
- ❌ Accessing `.memories` on unknown type from `retrieveMemories` — use type
  guards: `typeof result === 'string'` or `Array.isArray()`.
- ❌ Missing `is_global` parameter in `retrieveMemories` — required field.

## Context & Sessions

### Rewind > Correct
When a fix fails, DO NOT leave the failed attempt in context. The model degrades
when context fills with incorrect code + corrections. Instead: revert to before
the attempt, re-prompt with what you learned.

### Subagent Isolation
Delegate large read-only explorations to subagents. Their intermediate tool calls
(20 file reads, 12 greps, 3 dead ends) stay in child context. Only the final
report pollutes the main session.

### 40% Context Rule
If context utilization passes 60%, start a fresh session. The model measurably
hallucinates and makes malformed tool calls above this threshold.

## AnkiTov-Specific

### Workspace Docs Already Auto-Loaded
Don't duplicate content from:
- `workspace/Strategic_Blueprint.md`
- `workspace/Launch_Runbook.md`
- `workspace/Tooling_AnkiTov.md`
- `project-knowledge/SUMMARY.md`
- `workspace/RDPI_Workflow.md`

These are auto-injected via `.goosehints` `@` references.

### .gooseignore
These paths are excluded from `tree` and `rg`:
- `target/`, `node_modules/`, `.git/`, `.jj/`
- `*.sqlite*`, `.deploy/`
- `AnkiPlayGround/`, `backend/data/`
- `*.anki2`, `*.apkg`, `*.ankiaddon`
- `goose-archive/`
