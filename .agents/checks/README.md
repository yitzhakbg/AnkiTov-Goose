# .agents/checks — AnkiTov Code Review Checks

This directory defines user-defined review criteria (Checks) that Goose
applies during code review. Each check is a Markdown file with YAML
frontmatter specifying the check's scope and severity.

Inspired by AMP's Checks system.

## Anatomy of a Check

```markdown
---
name: unique-check-name
description: Brief description shown in review listings
severity-default: medium       # low | medium | high | critical
tools: [Grep, Read]            # tools the check subagent may use
globs: ['**/*.rs']             # optional: scope to file patterns
---

Check description content...

## What to Look For

- Pattern 1
- Pattern 2
```

## How Checks Run

1. Goose spawns a separate subagent per check
2. Each check subagent receives the diff to review
3. Checks run in parallel for speed
4. Results are collated into the review output

## Current Checks

| File | Severity | Scope | Focus |
|------|----------|-------|-------|
| `security.md` | critical | `**/*.rs`, `**/*.py`, `**/*.sh` | Credential leaks, injection, unsafe code |
| `performance.md` | medium | `**/*.rs` | N+1 queries, allocations, complexity |
| `style-rust.md` | low | `**/*.rs` | Idiomatic Rust, clippy lints |

---

*To add a check: create a `.md` file here with the required frontmatter fields.*