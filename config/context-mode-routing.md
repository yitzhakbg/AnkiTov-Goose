## Context Mode — sandbox-first routing
- When deriving an answer FROM large data (reading big files/logs, batch analysis across many files, web fetches, log aggregation), prefer the context-mode sandbox tools (shown as `context_mode__ctx_*`): `context_mode__ctx_execute` (one script), `context_mode__ctx_batch_execute` (several commands), `context_mode__ctx_fetch_and_index` (web pages). Print only the summary you need — raw output stays out of context; pull specifics back later with `context_mode__ctx_search`.
- Aggregations (counts, metrics, greps across a tree): write ONE `ctx_execute` script instead of many Read/shell calls — think in code, not in data.
- Do NOT route through the sandbox: file edits (write/edit), small outputs needed verbatim, interactive or long-running processes, anything needing live streaming stdout.
- `context_mode__ctx_stats` = session savings; `context_mode__ctx_doctor` = diagnostics.
