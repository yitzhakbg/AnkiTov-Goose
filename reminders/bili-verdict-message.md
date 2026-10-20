# bili vs headroom — the verdict

_Origin: goose session, 2026-10-12 (discussing ranxianglei/billion-context). Scheduled weekly, first delivery 2026-11-12._

**Yes — for the compression job, it's effectively either/or, and bili takes it.** With the shaper off, headroom's entire compression contribution is input compression (~4.6%). bili's entire job is compressing that same payload, at claimed 31–54%. Chained, headroom would be re-squeezing bili's already-folded summaries — near-zero marginal savings, plus a risk of breaking bili's cache-prefix stability. There's no compression work left where headroom earns its keep.

But headroom doesn't retire — it demotes to **plumbing**, and that plumbing is load-bearing:

1. **Key injection** — your auth-free `custom_glm` setup works precisely because headroom pulls `OPENROUTER_API_KEY` from the Keychain and injects it. Moving the key back into goose's own keychain was the thing that failed before (Goose Safe Storage introspection issues). Keep headroom in the path for this.
2. **Observability** — `--log-messages` / `headroom inspect` / `perf` are how you'd actually audit a bili trial.

Trial topology:

```
goose → bili (18787+) → headroom (8787, compression now redundant but harmless) → OpenRouter
```

Headroom's 4.6% riding on top of bili's output won't mask bili's 31–54% signal — no need to fiddle with `HEADROOM_COMPRESSORS` for a clean measurement.

**Watch-item**: bili also rewrites the streaming response (it executes `compress` server-side mid-conversation). That's a different mechanism from the shaper's token-stream reshaping — it manages message ranges, not output tokens — and goose is an explicitly supported bili client. But given that goose streaming is exactly what killed the headroom shaper, **mid-stream stalls are suspect class #1** if anything misbehaves in the trial. If you see `MidStreamFallbackError`-style timeouts under bili, you'll know where to look first.

**This week's nudge**: Have you run the `bili goose` trial yet? (Install: `npm install -g billion-context --prefix=~/.local`, then `bili goose` in a CLI session on AnkiTov-C; check `/acp-cache` after a real session.)