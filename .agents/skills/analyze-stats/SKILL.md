---
name: analyze-stats
description: Analyze retention statistics and deck health via the Management Console
status: aspirational
---

> ⚠️ **MCP backend not wired.** This skill references `anki-mcp-read` at `mcp.ankimcp.com/sse`
> but that SSE endpoint is not enabled as a Goose extension. To activate this skill,
> add the MCP server to `goose_config.yaml` as an SSE-type extension.
> Currently serves as documentation only.

# Analyze Retention Statistics Skill

Analyzes whole-class retention metrics, deck health, and learning exceptions
using the Management Console's analytics pipeline.

## Steps

1. **Identify scope** — Determine which class/group/student to analyze
2. **Query retention data** — Pull retention stats from the Management Console API
3. **Run deck health check** — Use `deck_health` tool on target decks
4. **Detect anomalies** — Find retention outliers, failing cards, stalled progress
5. **Generate report** — Output findings to `specs/research/<date>-retention-analysis.md`

## MCP Server Bundle

The `mcp.json` in this skill directory provides tools for:
- `retention_stats` — query retention data for a class or student
- `deck_health` — run health check on specific decks
- `find_problems` — identify issues in the collection

## Constraints

- **No card creation** — `create_flashcard` and note-editing tools are explicitly disabled
- **Read-only analysis** — This skill only queries data; no modifications
- **Budget Gate** — API calls are subject to rate limits configured in the Budget Gate sidecar