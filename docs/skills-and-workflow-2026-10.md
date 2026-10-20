---
type: note
title: Skills, Workflow Upgrades & Tooling Stack (2026-10)
---

# Skills, Workflow Upgrades & Tooling Stack (2026-10)

Canonical inventory and operating guide for the skills, verification loops, context/retrieval stack, and automation pipelines added to the AnkiTov + Goose + Buzz Hive environment in October 2026.

---

## 1. Installed Agent Skills (`skills/` · `~/.agents/skills/` · `buzz-hive`)

All 5 source-local skills are tracked in `AnkiTov-goose/skills/`, listed in `skillpack.json`, installed into `~/.agents/skills/<name>` (symlinked from `~/.config/goose/skills/<name>`), and mirrored into `buzz-hive/personas/hive-ankitov/skills/` with SHA-256 provenance in `skills-lock.json`.

| Skill | Origin | Files | When to Invoke & What It Enforces |
|---|---|---|---|
| **`grill`** | In-house ([T-109](https://github.com/yitzhakbg/buzz-hive-ankitov/blob/ankitov-hive/specs/tasks.md#L17:~:text=T-109%20@Strategist)), adapted from `mattpocock/skills` `grilling` (MIT) | `SKILL.md` | **Before locking any non-trivial spec or plan.** Maps the plan as a *design tree* worked in *frontier rounds* (`❓ Q1` + `➡️ Recommended` so "yes" accepts the default). Hard rule: **finding facts is the agent's job** (repo / `GLOSSARY.md` / read-only `delegate`); **decisions belong to the Queen Bee**. Closes with an explicit **Grill Ledger** (Settled Decisions, Explicit Assumptions + falsification triggers, Out of Scope). |
| **`diagnosing-bugs`** | `mattpocock/skills` (MIT) | `SKILL.md`, `scripts/hitl-loop.template.sh` | **Hard bugs & performance regressions.** 6-phase discipline: (1) build a *tight, red-capable* feedback loop first (never hypothesize before a single command reproduces the exact symptom), (2) reproduce & minimize until every remaining input is load-bearing, (3) 3–5 ranked falsifiable hypotheses, (4) one-variable-at-a-time instrumentation tagged `[DEBUG-xxxx]`, (5) seam-aware regression test before fix, (6) cleanup. |
| **`wizard`** | `mattpocock/skills` (MIT) | `SKILL.md`, `template.sh` | **Human-only setup / credential / dashboard flows.** Generates a resumable interactive bash wizard from `template.sh` that opens URLs, prompts with `ask` / `ask_secret`, writes idempotently to `.env`, and sets GitHub Actions secrets/variables via `gh`. |
| **`writing-for-agents`** | `mattpocock/skills` (MIT) | `SKILL.md`, `SKILL-MECHANICS.md` | **Authoring/editing skills, `AGENTS.md`, or persona files.** Governs *context load* vs. *cognitive load*, the 3-rung information hierarchy (in-file steps → in-file reference → disclosed reference), *leading words*, positive steering (avoid negation traps), and sentence-by-sentence no-op pruning. |
| **`code-review`** | In-house (`AnkiTov-goose`) | `SKILL.md` | Functional pre-commit review checklist across security, Rust backend idioms, and test coverage. |

### Hive-Specific Skills (`buzz-hive/personas/hive-ankitov/skills/`)
In addition to the 5 skills above, the Hive lanes carry:
- `impeccable` (`pbakaus/impeccable`) — UI/contrast/layout linting
- `security-audit` (`cloudflare/security-audit-skill`) — auth & surface security audit
- `typesafe-ai` (`typesafe-ai/skills`) — System One (`Choice`/`Score`/`Noul`) wire patterns
- `asd-ste100` (`danyuchn/asd-ste100-skill`) — Simplified Technical English for user docs
- `ppt-master` (`hugohe3/ppt-master`) — slide deck generation from guides

---

## 2. Upgraded `verify-loop` Recipe (`.goose/recipes/verify-loop.yaml`)

Tracked in `AnkiTov-goose/.goose/recipes/verify-loop.yaml` and mirrored to `AnkiTov-C/.goose/recipes/verify-loop.yaml`. Combines vertical-slice TDD with a parallel two-axis review before any repair or escalation:

1. **Seams & Vertical-Slice TDD**:
   - Read `GLOSSARY.md` first so domain and test naming stay canonical.
   - Name the public **Seam(s)** under test before writing code (HTTP route, service trait/fn, CLI boundary).
   - Work in vertical slices (one failing test at the seam → minimal implementation → green).
   - **3 banned TDD anti-patterns**:
     1. *Implementation-coupled mocks* of internal collaborators (mock only at system boundaries; prefer real SQLite test DB).
     2. *Tautological assertions* that recompute expected values with the same formula as the code under test.
     3. *Horizontal slicing* (writing all tests in bulk before any implementation).
2. **Hard Gates (in order)**:
   - `cargo check --tests` (workspace)
   - `cargo nextest run -p backend`
   - `python3 tools/validate_i18n.py` (whenever `backend/resources` or `backend/i18n` changes — 13 locales)
   - Public-mirror **Drift Gate** check (`scripts/oss/export-ankitov-core.sh` allowlist awareness)
3. **Parallel Two-Axis Review (via two read-only `delegate` subagents)**:
   - **Axis A — Standards**: checks `jj diff --git` against `AGENTS.md`, `specs/audits/*` invariant checklists, `GLOSSARY.md`, and the Fowler smell baseline (*Mysterious Name, Duplicated Code, Feature Envy, Data Clumps, Primitive Obsession, Shotgun Surgery, Speculative Generality*).
   - **Axis B — Spec**: checks `jj diff --git` against the originating spec/task for missing/partial requirements, unrequested scope creep, and subtle mismatches.
   - Reports are kept strictly separate (never merged or cross-ranked).
4. **Repair (≤2 rounds) → Escalate**:
   - Up to 2 repair rounds on any hard-gate or review-axis failure; if still red, escalates via `delegate` to `z-ai/glm-5.3`.

---

## 3. Ubiquitous Language & Architecture Rules (`GLOSSARY.md` + `@Strategist`)

- **`AnkiTov-C/GLOSSARY.md`** (committed to `AnkiTov-C` `main` and included in `00-overview.md` of the Gemini Notebook export): defines canonical terms (**Student**, **Teacher**, **Admin**, **Class**, **Card**, **Deck**, **Capsule**, **IMP**, **Interference**, **FSRS Scheduler**, **Memory State**, **Revlog**, **Audit Trail**, **School Metrics**, **Session Driver**, **AnkiPlayGround**, **Setup Flow**, **Public Mirror**, **Drift Gate**) and deep-module terms (**Module**, **Interface**, **Seam**, **Depth**) with explicit `_Avoid_` lists.
- **`@Strategist` Persona Additions (`strategist.persona.md`)**:
  - **Design It Twice**: for non-trivial module/interface designs, spawn 2–3 parallel `delegate` subagents with distinct design lenses (*minimal interface / max leverage*, *caller ergonomics*, *ports & adapters*), compare on **depth**, **locality**, and **seam placement**, and recommend an opinionated winner.
  - **3-Part ADR Bar** (`docs/adr/NNNN-slug.md`, 1-paragraph default): offer an ADR *only* when a decision is **(a) hard to reverse**, **(b) surprising without context**, and **(c) the result of a real trade-off**.

---

## 4. Context, Retrieval & Proxy Stack (`custom_providers/` + `config/`)

- **Per-Model Context Limits (`custom_providers/*.json`)**:
  - Replaced the retired global `GOOSE_CONTEXT_LIMIT=800000` env override (which did not work in Goose Desktop and starved `qwen3.8-27b` compaction).
  - `custom_glm.json`: `z-ai/glm-5.3-flash` (`800,000`), `google/gemini-3.8-flash` (`1,048,576`) via local **Headroom** proxy (`http://localhost:8787`, `HEADROOM_OUTPUT_SHAPER=0` to prevent streaming stalls).
  - `custom_gemini_bili.json` & `custom_glm_bili.json`: `204,800` paper-validated window via **billion-context (`bili`)** proxy (`http://127.0.0.1:8790/bili/https://openrouter.ai/api/v1`) for all 7 Buzz Hive lanes (~81–86% prefix-cache hit rate).
  - `custom_qwen_ub3090.json`: `qwen3.8-27b` on `ub3090:18020` (vLLM).
  - Auto-compact threshold: `0.8` in `config-permanent.yaml`, with `GOOSE_AUTO_COMPACT_TOKEN_LIMIT=400000` persisted via LaunchAgent `user.ybg.goose-auto-compact-token-limit.plist` + `~/.bashrc` (gives GLM a 400k trigger while keeping Qwen safe under its server cap).
- **Context Mode (`config/context-mode-routing.md`)**:
  - MCP server (`context-mode`, FTS5/BM25 + subprocess sandbox `ctx_execute` / `ctx_batch_execute` / `ctx_fetch_and_index`) routed via `GOOSE_MOIM_MESSAGE_FILE` so large tool outputs stay out of context.
- **XERJ Search Engine (`xerj` MCP extension)**:
  - Local Rust ES-compatible search node (`user.ybg.xerj-node` on `127.0.0.1:9200`) indexing `ankitov-specs`, `ankitov-code`, and `ankitov-docs` for passage-level retrieval (`xerj_search`, `xerj_map`).

---

## 5. Automation Pipelines & Reminder Recipes (`.goose/notebook-export/` + `reminders/`)

- **Gemini Notebook Auto-Sync (`.goose/notebook-export/`)**:
  - `merge_docs.py` + `ankitov-notebook-export.sh` (LaunchAgent `user.ybg.ankitov-notebook-export`, every 30 min) merges 160+ repo markdown files and core backend sources into 6 citation-tagged files (`00-overview.md` .. `05-code-core.md`) and pushes changes via `rclone` (`--drive-root-folder-id root`) to Google Drive (`Synced AnkiTov Files for Gemini Notebook`), keeping the notebook current within ~35 minutes with zero manual steps.
- **One-Shot & Standing Reminder Recipes (`reminders/`)**:
  - Self-removing date-gated recipes for scheduled evaluations and ops gates (`mattpocock-skills-check.yaml`, `context-mode-ctx-stats.yaml`, `xerj-gain-check.yaml`, `actions-resume-20261101.yaml`, `public-mirror-reexport-20261021.yaml`, `ub3090-health-20261020.yaml`, `extensions-facility-review.yaml`).
  - **Scheduler Rule**: `goose schedule` only injects `prompt` (not `instructions`), and removing a schedule requires **both** `goose schedule remove --schedule-id <id>` **and** `rm ~/.local/share/goose/scheduled_recipes/<id>.yaml` to prevent resurrection.
