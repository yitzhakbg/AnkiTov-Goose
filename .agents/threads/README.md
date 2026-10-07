# .agents/threads — Cross-Session Thread Persistence

This directory provides persistent, cross-session agent conversation context
using jj (Jujutsu) change hashes + a lightweight SQLite database.

Inspired by AMP's Thread system (version control for agent conversations).

## Problem

Goose sessions are ephemeral. When a session ends:
- Context about decisions, failed attempts, and partial work is lost
- The next session starts with zero memory of what was discussed
- Long-running development tasks span multiple sessions but context resets

## Solution: jj-Keyed Thread Persistence

Every agent conversation "thread" is indexed by:
1. The **jj change hash** of the repository at the time of creation
2. A **thread ID** (UUID) for the conversation within that change
3. A **human-readable label** for recall

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  thread-persist.sh  ← CLI tool (save/restore/list)  │
├─────────────────────────────────────────────────────┤
│  thread.db  ← SQLite database                       │
├─────────────────────────────────────────────────────┤
│  jj log --limit 1  ← source of truth for "now"      │
└─────────────────────────────────────────────────────┘
```

## Database Schema

```sql
CREATE TABLE threads (
    id TEXT PRIMARY KEY,            -- UUID
    label TEXT NOT NULL,            -- Human-readable name
    jj_change_hash TEXT NOT NULL,   -- jj change the thread belongs to
    jj_change_description TEXT,     -- Description of that jj change
    created_at TEXT NOT NULL,       -- ISO 8601
    updated_at TEXT NOT NULL,       -- ISO 8601
    summary TEXT,                   -- LLM-generated summary of the thread
    context TEXT,                   -- JSON blob: file paths, decisions, TODO items
    tags TEXT                       -- Comma-separated tags for filtering
);

CREATE INDEX idx_threads_jj_hash ON threads(jj_change_hash);
CREATE INDEX idx_threads_tags ON threads(tags);
CREATE INDEX idx_threads_label ON threads(label);
```

## CLI Usage

```bash
# Save current thread context
./.agents/threads/thread-persist.sh save \
  --label "IMP-7 capsule slicing implementation" \
  --summary "Decided on N=3 default, spill-to-next strategy" \
  --context '{"files":["backend/src/services/capsule.rs"],"decisions":["N=3 default"],"todos":["IMP-8"]}' \
  --tags "imp,capsule"

# List all threads
./.agents/threads/thread-persist.sh list

# Restore context for a thread (outputs as JSON for Goose to consume)
./.agents/threads/thread-persist.sh restore --id <thread-uuid>

# Search threads by tag
./.agents/threads/thread-persist.sh list --tag imp

# Search threads by jj change hash
./.agents/threads/thread-persist.sh list --change <jj-hash>

# Show recent threads
./.agents/threads/thread-persist.sh list --limit 10
```