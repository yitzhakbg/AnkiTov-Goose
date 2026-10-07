# Scheduled: Rust Agent Memory Landscape Review

**Trigger:** July 2026 evaluation of AMP identified Cognee as overkill but noted MenteDB
as the only Rust-native agent memory project worth watching.

**Schedule:** Three-month check — due **October 6, 2026**.

**Recipe:** `rust-memory-landscape-review` (`.goosehq/recipes/rust-memory-landscape-review.yaml`)

## Run Command

```bash
goose run recipe rust-memory-landscape-review
```

## What to Check

| Project | License | Baseline (Jul 2026) | Threshold for "Viable" |
|---------|---------|---------------------|------------------------|
| MenteDB | Apache-2.0 | 102 stars | >1K stars, published crate, active maintenance |
| YantrikDB | AGPL-3.0 | 37 stars | License change OR compelling enough to justify separate infra |
| Cuba Memorys | None | 26 stars | >200 stars, license declared, crate published |
| rUvOS | None | 29 stars | Name stable, >200 stars |

## Current Recommendation (Jul 2026)

**Stay the course.** Our LanceDB + jj commit graph indexing + `.agents/threads/` SQLite
persistence is more mature, more integrated, and more jj-native than any of these
upstarts. Re-evaluate at this check-in.

## Background

See `specs/design/2026-07-06-agent-memory-and-guidance.md` and
`workspace/Tooling_AnkiTov.md` for the full architectural context.