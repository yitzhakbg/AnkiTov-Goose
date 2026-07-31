# AnkiTov RDPI Workflow — Research → Design → Plan → Implement

Adapted from Goose's [RPI](https://goose-docs.ai/docs/tutorials/rpi) pattern
and refined with [QRSPI](https://alexlavaee.me/blog/from-rpi-to-qrspi/) insights.

---

## The 40% Context Rule

LLMs degrade as their context window fills. Research from Chroma and
HumanLayer shows: **below 40% utilization, the model performs well. Above
60%, it starts hallucinating, making malformed tool calls, and losing track
of the task.** Bigger context windows don't fix this — they just hold more
noise.

**Practical rule**: If you're past 60% context, start a fresh session. Load
only what's needed for the current phase from disk (research docs, plan
files). Persist progress to disk between sessions. This is why each phase
is a separate Goose session — not just for cleanliness, but because the
model is measurably worse when context is bloated.

**Rewind > correct**: If a fix fails during implementation, revert to before
the attempt. Do NOT leave failed code + corrections in context — it degrades
subsequent reasoning. Re-prompt with what you learned.

---

## Meta-Process: Start From Real Expertise

**Before creating any new skill, agent, or recipe**: complete at least 3
real tasks in that domain with Goose first. Note:
- What steps worked
- What corrections you made (where you steered the agent)
- What context you had to provide
- What the agent got wrong

THEN extract the reusable pattern into a skill/agent/recipe. Never synthesize
from general knowledge — the most effective skills are grounded in real
AnkiTov task traces, not generic programming advice.

---

## The Whole Flow (Simple Version)

```
1. Research    /research_codebase "topic"
   → 3 parallel subagents map the codebase
   → outputs specs/research/<date>-<topic>.md

2. Design      /design_discussion specs/research/<file>.md
   → agent brain-dumps ~200 lines: "here's what I think we should do"
   → YOU review it and correct architectural direction
   → (NEW) agent asks 3-5 clarifying questions to surface assumptions
   → outputs specs/design/<date>-<topic>.md

3. Plan        /create_plan specs/design/<file>.md
   → agent reads research + design, produces phased plan
   → vertical-slice phases with checkboxes, file paths, test gates
   → outputs specs/plans/<date>-<description>.md

4. Implement   (manual — new session)
   → "Read specs/plans/<file>.md and implement phase by phase.
      Run cargo check after each phase. Update checkboxes as you go."
   → Use appropriate agent: Rust Engineer for large refactors,
     Minimal Change for surgical fixes, Code Reviewer before commit.
```

**Why Design exists (step 2)**: Without it, the agent goes straight from
research to planning. If the agent picked the wrong architectural pattern
during research, the entire plan is built on a wrong assumption. The
design discussion catches this — you see the agent's mental model and
correct it before any planning effort is wasted. This is called "brain
surgery" in QRSPI terminology.

**Why the interview step (step 2, NEW)**: After you correct the architectural
direction, the agent asks 3-5 clarifying questions before committing to a
plan. This surfaces hidden assumptions about scope, constraints, and
tradeoffs. If the answers change the design, iterate before planning.

**Why vertical slices**: Each plan phase must be end-to-end (model +
controller + test + utoipa annotation). Not "all models first, then all
controllers." Vertical slices give you a testable checkpoint after each
phase. If something's wrong, you find out at phase 1, not after 3 phases
of accumulated work.

**Why fresh sessions**: The 40% rule. Each phase loads only what it needs.
Research session doesn't carry planning context. Planning session loads
research output from disk but doesn't carry research tool-call noise.
Implementation session loads the plan but doesn't carry planning
conversation.

---

## Agent Selection for Implementation

| Task Type | Agent | Model |
|-----------|-------|-------|
| Bug fix, small tweak | AnkiTov Minimal Change Engineer | deepseek/deepseek-chat |
| Large refactor, new feature | AnkiTov Rust Engineer | qwen/qwen-3-coder-235b-a22b |
| Codebase exploration | AnkiTov Spec Researcher | deepseek/deepseek-chat |
| Pre-commit review | AnkiTov Code Reviewer | deepseek/deepseek-chat |

---

## What Was Set Up

### Files

```
recipes/
├── ankitov-research.yaml           ← /research_codebase (step 1)
├── ankitov-design.yaml             ← /design_discussion (step 2)
├── ankitov-plan.yaml               ← /create_plan (step 3)
├── ankitov-simplify.yaml           ← 4 parallel review agents (post-implementation)
└── subrecipes/
    ├── ankitov-locator.yaml        ← finds WHERE files live
    ├── ankitov-analyzer.yaml       ← documents HOW code works
    └── ankitov-pattern-finder.yaml ← finds existing patterns

.goose/agents/
├── ankitov-code-reviewer.md        ← pre-commit review with 🔴🟡💭 checklist
├── ankitov-rust-engineer.md        ← large refactors, 10 critical rules
├── ankitov-minimal-change.md       ← surgical fixes, scope discipline
└── ankitov-spec-researcher.md      ← read-only exploration, model: cheapest

.agents/skills/
├── code-review/                    ← functional review skill
├── analyze-stats/                  ← aspirational (MCP backend pending)
└── deploy-docs/                    ← aspirational (MCP backend pending)

workspace/
└── Gotchas.md                      ← accumulated AI failure patterns

specs/
├── research/                       ← research docs output
├── design/                         ← design docs output
├── plans/                          ← plan docs output
└── templates/
    ├── plan-template.md            ← plan template (vertical slices enforced)
    └── design-template.md          ← design discussion template

goose_config.yaml
└── slash_commands:
    ├── /research_codebase
    ├── /design_discussion
    └── /create_plan
```

---

## When to Use

- Multi-file refactors across controllers, models, services, tests
- New features touching multiple AnkiTov layers
- Cross-prong work
- Anything where "just start coding" would likely drift

Skip it for single-file changes, obvious bug fixes, quick config tweaks.
