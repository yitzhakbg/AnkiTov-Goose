# .agents/guidance — Scoped Project Conventions

This directory provides file-scoped, glob-patterned guidance for Goose,
inspired by AMP's AGENTS.md + YAML frontmatter approach.

Each file in this directory is a Markdown file with YAML frontmatter
containing a `globs:` key. The file is loaded by Goose only when it
works on a file matching one of the globs.

## How It Works

```markdown
---
globs:
  - '**/*.rs'
  - '**/Cargo.toml'
---

# Rust Backend Conventions

- Use `cargo check` not `cargo build` for compilation verification
- ...
```

## File Precedence

1. `.agents/guidance/*.md` — project-level guidance (this directory)
2. `AGENTS.md` in workspace root — general guidance
3. `AGENTS.md` in parent directories — inherited guidance
4. `AGENTS.md` in file subtrees — file-specific guidance

## Current Files

| File | Globs | Purpose |
|------|-------|---------|
| `rust-backend.md` | `**/*.rs`, `**/Cargo.toml` | Rust/Loco.rs conventions |
| `python-scripts.md` | `**/*.py` | Python conventions |
| `shell-scripts.md` | `**/*.sh` | Shell scripting conventions |

---

*To add new guidance: create a `.md` file here with `globs:` frontmatter.*