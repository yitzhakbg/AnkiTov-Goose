---
globs:
  - '**/*.sh'
  - '**/bootstrap_*'
  - '**/sidecar_*'
---

# Shell Scripts — AnkiTov Conventions

## Shebang & Safety

- All shell scripts MUST use `#!/usr/bin/env bash` (never `zsh`)
- Always set `set -euo pipefail` at the top of every script
- Shellcheck-compatible syntax required

## Conventions

- Use `bash` exclusively — no `zsh`, `sh`, or other shells
- Scripts in project root should be documented (see `workspace/archived/Launch_Runbook.md` for legacy reference)
- Bootstrap scripts: `scripts/bootstrap.sh` (supersedes `bootstrap_workplace.sh`)
- Sidecar scripts: `sidecar_gate.sh` pattern

## Integration

- Goose can execute shell scripts via the `developer` extension
- The HITL Gate intercept will block destructive shell operations
- All shell scripts are subject to the Budget Gate for resource limits