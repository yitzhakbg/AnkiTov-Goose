---
name: code-review
description: Review code for correctness, security, maintainability, and performance.
  Use when committing changes, before pushing, or when asked to review Rust, Python,
  or shell code in the AnkiTov project. Applies to backend/src/, ankitov-budget-gate/src/,
  scripts/, and recipes/.
compatibility: Requires cargo check, cargo nextest, shell access
---

# Code Review Skill

Review code changes with structured, priority-tagged feedback. Every comment
must teach something, not just criticize.

## Trigger Conditions

Activate when:
- User says "review", "check my code", "look at this change"
- Before committing or pushing
- After completing an implementation phase
- When running `cargo check` or `cargo nextest` reveals issues

## Review Process

### 1. Determine scope
Run `jj status` and `jj log --limit 3` to identify what changed.
For focused review, use `jj diff` on the current change.

### 2. Analyze each changed file
Use `analyze` extension for structure, `codegraph` for call graphs.
Check each file against the checklist below.

### 3. Run verification
```bash
cd backend && cargo check 2>&1
cargo nextest run 2>&1
cd ../ankitov-budget-gate && cargo check 2>&1
```

### 4. Produce the review
Group findings by priority. Each finding must include:
- Priority marker (🔴🟡💭)
- Category (Security, Correctness, Maintainability, Performance, Testing)
- Specific location (file:line)
- **Why** this matters
- Suggested fix

## Review Checklist

### 🔴 Blockers (Must Fix)
- Security: SQL injection, missing auth, exposed secrets, unsafe blocks
- Correctness: data loss, race conditions, broken API contracts, unwrap() on untrusted input
- Testing: missing tests for critical paths that change behavior

### 🟡 Suggestions (Should Fix)
- Missing input validation at system boundaries
- Unclear variable/function names
- Missing error handling for fallible operations
- N+1 queries or unnecessary allocations
- Missing `#[utoipa::path]` on new controller routes

### 💭 Nits (Nice to Have)
- Style inconsistencies (if clippy doesn't catch them)
- Missing doc comments on public APIs
- Alternative approaches worth considering

## AnkiTov-Specific Rules

- `cargo nextest run` — NEVER use `cargo test`
- `jj` — NEVER use `git` commands
- `bash` — NEVER use `zsh` in shell scripts
- `set -euo pipefail` — required in all shell scripts
- `NoOpMigrator` pattern — required for all schema changes
- No bare excepts in Python: always specify exception type
- Schema changes must be reversible

## Communication Style

- Start with a 1-sentence overall assessment
- Be specific: "Line 42: user input interpolated into SQL query" not "security issue"
- Explain WHY, not just WHAT: "Consider using X because Y"
- Suggest, don't demand: "Consider" not "Change this to"
- Praise good patterns when you see them
- End with next steps
