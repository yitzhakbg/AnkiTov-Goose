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

### 3. Run verification — BOTH harnesses, in order, no exceptions

**This is a hard gate, not a suggestion.** A change that touches the backend
(`backend/`) is NOT "done" until **both** independent harnesses pass. Do not
report a backend change as complete on Harness 1 alone. See `specs/double-harness.md`.

**Harness 1 — Rust, white-box, in-process** (always):
```bash
cd backend && cargo check 2>&1
cargo nextest run 2>&1
cd ../ankitov-budget-gate && cargo check 2>&1
```
If Harness 1 fails, STOP — do not run Harness 2, fix the in-process failures first.

**Harness 2 — Python, black-box over HTTP** (always, right after a green Harness 1):
```bash
scripts/harness2/run_all.sh
```
This starts a real dev server (port 5150), runs the 22 black-box suites against
`/api/v1`, shuts the server down, and writes two reports to `project-knowledge/`:
`YYYY-MM-DD-double-harness-combined.md` and `YYYY-MM-DD-double-harness-results.md`.

**Interpreting Harness 2's exit code:**
- `0` → both harnesses green. Change is **done**.
- `1` → at least one suite FAILED. Change is **NOT done** — triage per the
  "Failure triage" section of `specs/double-harness.md`. A 5xx is a real bug;
  a 4xx means the expectation or the contract is wrong.
- `2` → a prerequisite was missing (server couldn't start / unreachable). This is
  an **environment** problem, not a test failure — report it, fix the env, re-run.
  Do not let exit 2 be waved through as "passed."

**SKIP is not FAIL.** Suites that target not-yet-built features (NL-ops
`/management/act`, AnkiConnect Tier B) report ⏭️ SKIP with a reason. Skips keep
the harness green and are expected — they are never a reason to skip running
Harness 2, and they must be *explained in the report*, not silently passed over.

**When Harness 2 is NOT required:** a change that touches ONLY non-backend
surfaces (e.g. pure marketing-site `specs/launch/site/`, outreach docs, i18n
locale JSONs with no endpoint change) does not change the API contract, so a
black-box run adds no signal. Still run Harness 1. Use judgment, but when in
doubt — especially for any `backend/` change — run both.

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
- **Double-harness gate:** any change touching `backend/` MUST pass BOTH
  `cargo nextest` (Harness 1) AND `scripts/harness2/run_all.sh` (Harness 2,
  black-box over HTTP) before it is reported as done. Never "done" on Harness 1
  alone. Harness 2 exit code 2 = environment problem (report + fix env), 1 =
  real failure, 0 = green. SKIP suites are expected and never a reason to skip
  the run. Full spec: `specs/double-harness.md`.
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
