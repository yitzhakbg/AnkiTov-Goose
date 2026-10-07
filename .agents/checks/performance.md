---
name: performance
description: Flags performance anti-patterns — N+1 queries, excessive allocations, O(n²) loops, and DB overhead
severity-default: medium
tools: [Grep, Read]
globs:
  - '**/*.rs'
  - '**/*.py'
---

# Performance Check — AnkiTov

## What to Look For

### 1. Database Access Patterns
- N+1 query patterns in SeaORM (missing `find_related` or eager loading)
- Missing database indexes on foreign keys used in WHERE clauses
- Full table scans on large datasets (libSQL WAL mode helps but isn't a silver bullet)

### 2. Memory & Allocation
- Large allocations in hot paths (review loops, card rendering)
- Unnecessary `clone()` or `to_string()` on owned types
- `Vec` reallocations — prefer `with_capacity()` where size is known

### 3. Algorithmic Complexity
- Nested loops over the same collection (O(n²) → O(n) with HashSet/Map)
- Repeated linear searches through large vectors
- Unbounded recursion without depth limits

### 4. Async & Concurrency
- Blocking calls inside async contexts (use `tokio::task::spawn_blocking`)
- Missing connection pooling for libSQL
- Unbounded task spawning in Axum request handlers

### 5. FSRS & Scheduling Hot Paths
- Card review telemetry dispatch must be non-blocking
- FSRS parameter calculations should be cached, not recomputed per card
- N-Lever adjustments and capsule generation must have rate limits (Budget Gate)