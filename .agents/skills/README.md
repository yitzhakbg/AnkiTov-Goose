# .agents/skills — Skill Packaging for AnkiTov

Skills are reusable packages of instructions and resources that teach Goose
how to perform specific tasks. Each skill is a directory containing:

- `SKILL.md` — The skill definition and instructions (invoked by name)
- `mcp.json` — Optional MCP server configuration bundled with the skill
- Additional resource files (templates, scripts, etc.)

Inspired by AMP's Skill system and integrated with Goose's existing recipe
infrastructure.

## Anatomy of a Skill

```
my-skill/
├── SKILL.md         ← Skill definition with YAML frontmatter
├── mcp.json         ← Optional MCP server config (tools hidden until skill loaded)
├── template.md      ← Optional resource file
└── script.sh        ← Optional helper script
```

## SKILL.md Format

```markdown
---
name: my-skill
description: What this skill does
globs: ['**/*.rs']   # optional: auto-invoke when working with these files
---

## Instructions

Detailed instructions for Goose when this skill is invoked.
```

## MCP Server Bundling

When a skill bundles an MCP server (via `mcp.json`), the server's tools remain
**hidden** until the skill is loaded. This keeps Goose's tool list clean and
reduces context bloat.

### Local (stdio) MCP Server

```json
{
  "my-server": {
    "command": "npx",
    "args": ["-y", "some-mcp-server"],
    "includeTools": ["tool_a", "tool_b"]
  }
}
```

### Remote (HTTP/SSE) MCP Server

```json
{
  "my-server": {
    "url": "https://mcp.example.com/sse",
    "includeTools": ["tool_a", "tool_b"]
  }
}
```

## Skill Resolution Order (first wins)

1. `.agents/skills/` — project-specific skills (this directory)
2. `~/.config/agents/skills/` — user-wide skills
3. `~/.agents/skills/` — user-wide skills (alt path)
4. Built-in Goose skills

## Current Skills

| Directory | Location | Purpose |
|-----------|----------|---------|
| `grill/` | `skills/grill/` (`~/.agents/skills/grill`) | Relentless design-tree frontier interview + explicit Grill Ledger (`T-109`) |
| `diagnosing-bugs/` | `skills/diagnosing-bugs/` (`~/.agents/skills/diagnosing-bugs`) | 6-phase tight red-capable feedback-loop debugging discipline + HITL bash template |
| `wizard/` | `skills/wizard/` (`~/.agents/skills/wizard`) | Interactive resumable bash wizard generator for human-only browser/credential steps |
| `writing-for-agents/` | `skills/writing-for-agents/` (`~/.agents/skills/writing-for-agents`) | Reference guide for authoring skills, `AGENTS.md`, and persona files (context vs. cognitive load) |
| `code-review/` | `skills/code-review/` | Pre-commit functional, security, and Rust backend review checklist |
| `deploy-docs/` | `.agents/skills/deploy-docs/` | Deploy Mintlify docs and Scalar API reference |
| `analyze-stats/` | `.agents/skills/analyze-stats/` | Analyze retention statistics via the Management Console |

See [`docs/skills-and-workflow-2026-10.md`](../../docs/skills-and-workflow-2026-10.md) for the full operating guide.

---

*To add a skill: create a subdirectory here with `SKILL.md` and optional `mcp.json`.*