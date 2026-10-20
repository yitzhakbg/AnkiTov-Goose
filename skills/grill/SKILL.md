---
name: grill
description: Relentless design-tree interview to stress-test a plan, spec, or decision and produce an explicit assumptions & decisions log. Use when the user says "grill me", "grill this", "stress-test this plan", or before locking a high-stakes spec.
---

# Grill — Design-Tree Stress Test

Interview the user (or author) relentlessly until every branch of the design tree is settled and nothing is silently assumed.

 Adapted for goose + Buzz Hive from the frontier-round pattern (`mattpocock/skills` MIT) plus AnkiTov's explicit assumptions-ledger discipline (T-109).

## 1. Facts vs. Decisions (Hard Rule)

- **Finding facts is YOUR job, never the user's.** Before asking anything, check the repo, `GLOSSARY.md`, `specs/`, `project-knowledge/key-decisions.md`, or dispatch a read-only `delegate` subagent to inspect code/configs. Never ask the user what a file says, what routes exist, or how a module currently works.
- **Decisions belong to the user (the Queen Bee).** Where genuine trade-offs or product choices exist, put them on the frontier and wait.
- If a subagent exploration is still running, only the questions downstream of that fact wait; ask the rest of the current frontier immediately.

## 2. Work the Design Tree by Frontier Rounds

Map the plan/spec as a **design tree**: every decision branches into the downstream decisions that depend on it.

- The **frontier** is the set of unsettled decisions whose prerequisites are already settled.
- **Never ask a downstream question in the same round as its prerequisite.** Ask the frontier, wait for answers, then recompute the new frontier for the next round.
- **Word every question so "yes" (or the number + "ok") accepts your recommended answer.** Give a concrete recommendation (`➡️`) grounded in repo conventions and doctrine — never a neutral menu when you have enough signal to recommend.

### Round format

❓ **Q1 — <short decision title>**: <1–3 tight sentences stating the tension, options, and blast radius. Cite `file:line` or spec section if relevant.>

➡️ **Recommended**: <your concrete default and the one-line reason>

---

❓ **Q2 — <short decision title>**: <...>

➡️ **Recommended**: <...>

Keep rounds to the true current frontier (typically 2–5 questions).

## 3. Challenge Modes (Run Every Round)

While computing the frontier, actively hunt for:

1. **Silent assumptions** — what must be true for this plan to work that nobody has stated or verified?
2. **Seam & invariant collisions** — does this cross an existing invariant checklist (`specs/audits/*`), export allowlist (`export-ankitov-core.sh`), locale contract (13 locales in `backend/i18n/`), or privacy/doctrine rule?
3. **Scope creep / speculative generality** — what can be deleted or deferred to Phase 2 without breaking the core outcome?
4. **Glossary drift** — if a term conflicts with `GLOSSARY.md` (or overloads an existing concept), call it out in the round.

## 4. Closing the Grill — Assumptions & Decisions Log

The grill ends when the frontier is empty and the user confirms shared understanding. Always close by emitting (or appending to the target spec) a compact **Grill Ledger**:

```markdown
## Grill Ledger (<YYYY-MM-DD>)

### Settled Decisions
- **D1 (<topic>)**: <decision> — *Rationale*: <1 line>

### Explicit Assumptions (must hold; falsification trigger noted)
- **A1**: <assumption> — *Verified by / breaks if*: <check or trigger>

### Explicitly Out of Scope
- <item deferred or rejected, and why>
```

Do not begin implementation until the user confirms the ledger.
