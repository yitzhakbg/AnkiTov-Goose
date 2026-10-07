# .agents — AnkiTov Agent Infrastructure

This directory houses the AnkiTov Agent Infrastructure — a set of additive,
zero-disruption systems that give Goose (the Execution Foreman) structured,
scoped, and persistent context across sessions.

All four systems are inspired by upstream patterns (primarily AMP's AGENTS.md,
Checks, Orbs, and Skill packaging) and adapted for AnkiTov's specific stack:
Goose + Rig Core + jj + tasklite + Terax.

## Directory Layout

```
.agents/
├── README.md          ← This file
├── guidance/          ← Scoped project conventions (AGENTS.md pattern)
│   ├── README.md
│   ├── rust-backend.md
│   ├── python-scripts.md
│   └── shell-scripts.md
├── checks/            ← Code review criteria (Checks system)
│   ├── README.md
│   ├── security.md
│   ├── performance.md
│   └── style-rust.md
├── skills/            ← Reusable skill packages (Skill Packaging pattern)
│   ├── README.md
│   ├── deploy-docs/
│   │   ├── SKILL.md
│   │   └── mcp.json
│   └── analyze-stats/
│       ├── SKILL.md
│       └── mcp.json
└── threads/           ← Cross-session thread persistence (jj + SQLite)
    ├── README.md
    ├── thread.db      ← SQLite database (auto-created)
    └── thread-persist.sh  ← CLI tool for save/restore/list
```

## How Goose Consumes These

| Directory | Mechanism | When Loaded |
|-----------|-----------|-------------|
| `guidance/` | Loaded by Goose on workspace open; glob-matching via YAML frontmatter | Every session |
| `checks/`  | Called via `amp review` equivalent or explicit "run checks on this PR" | On request |
| `skills/`  | SKILL.md loaded on-demand when the skill name is invoked | On demand |
| `threads/` | `thread-persist.sh` CLI tool + SQLite; manual or recipe-triggered | On demand |

## Design Principles

1. **Purely additive** — No existing file is ever modified by these systems.
2. **Self-documenting** — Every directory has a README explaining its purpose.
3. **Goose-native** — All patterns integrate with Goose's existing extension system
   (developer, skills, analyze, summon) and smart_approve mode.
4. **jj-native** — Thread context records jj change hashes, not git SHAs.
5. **Budget-aware** — Skill execution and thread persistence respect the
   Budget Gate sidecar's rate limits.

---

*See `specs/design/2026-07-06-agent-memory-and-guidance.md` for the full spec.*