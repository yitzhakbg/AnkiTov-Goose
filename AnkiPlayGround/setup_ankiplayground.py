#!/usr/bin/env python3
"""
AnkiPlayground Setup — AnkiTov Live Demo

Seeds 10 user profiles in AnkiPlayGround/ with realistic review telemetry
using the Anki demo collection's "ארמית" deck (1729976271885, 884 cards) as
the base. Each user gets a distinct 30-day practice profile.

Usage:
  python3 setup_ankiplayground.py
"""

import sqlite3, shutil, random, sys
from datetime import datetime, timedelta
from pathlib import Path

PLAYGROUND = Path("/Volumes/YBG1TB4Mac/AnkiTov/AnkiPlayGround")
DEMO_PATH  = Path("/Users/ybg/Library/Application Support/Anki2/demo/collection.anki2")
DECK_ID    = 1729976271885
DECK_NAME  = "ארמית"

NOW_TS     = int(datetime(2026, 6, 28, 19, 49).timestamp())
WINDOW_START = NOW_TS - (30 * 86400)

# (ease, ivl, lastIvl, factor, time_ms, queue_type)
GRADE = {
    1: (0,   1,   0,  1300, 3000, 1),
    2: (700, 100, 100, 1700, 4000, 1),
    3: (850, 300, 100, 2100, 5000, 1),
    4: (950, 600, 100, 2500, 6000, 1),
}

USERS = [
    ("Maya Chen",    "maya-chen",    30, {1:.02, 2:.10, 3:.80, 4:.08},  0, "daily"),
    ("Lucas Kim",    "lucas-kim",    10, {1:.15, 2:.25, 3:.55, 4:.05},  3, "daily"),
    ("Priya Sharma", "priya-sharma", 28, {1:.00, 2:.00, 3:.05, 4:.95},  1, "daily"),
    ("Noah Torres",  "noah-torres",  20, {1:.35, 2:.40, 3:.20, 4:.05},  2, "daily"),
    ("Emma Wilson",  "emma-wilson", 100, {1:.03, 2:.12, 3:.80, 4:.05},  0, "weekends"),
    ("Amir Hassan",  "amir-hassan",  18, {1:.05, 2:.18, 3:.72, 4:.05},  0, "daily"),
    ("Sofia Lima",   "sofia-lima",   25, {1:.08, 2:.18, 3:.70, 4:.04},  0, "declining"),
    ("James Park",   "james-park",   30, {1:.05, 2:.10, 3:.75, 4:.10}, 25, "daily"),
    ("Zoe Okafor",   "zoe-okafor",   22, {1:.03, 2:.05, 3:.77, 4:.15},  0, "daily"),
    ("Riku Tanaka",  "riku-tanaka",  25, {1:.05, 2:.10, 3:.80, 4:.05},  0, "lapsed"),
]


def seed(short_id, daily, gw, start_day, pattern, card_ids):
    """Generate revlog entries for one user (30-day window)."""
    random.seed(hash(short_id))
    entries = []

    for day in range(start_day, 30):
        dt = datetime(2026, 5, 29) + timedelta(days=day)

        if pattern == "weekends" and dt.weekday() not in (5, 6):
            continue
        if pattern == "lapsed" and day >= 20:
            break

        # Ease degrades for "declining" after day 15 and day 22
        weights = dict(gw)
        if pattern == "declining" and day > 15:
            weights[2] = weights.get(2, 0) + 0.10
            weights[3] = weights.get(3, 0) - 0.10
        if pattern == "declining" and day > 22:
            weights[2] = weights.get(2, 0) + 0.10
            weights[3] = weights.get(3, 0) - 0.10
        total = sum(weights.values())
        weights = {k: v / total for k, v in weights.items()}

        day_start = int(dt.timestamp()) * 1000
        n = min(daily, len(card_ids))

        for i in range(n):
            cid = card_ids[i % len(card_ids)]
            ts  = day_start + random.randint(0, 86_399_999)
            grade = random.choices(
                list(weights), weights=list(weights.values()), k=1
            )[0]
            _, ivl, last_ivl, factor, time_ms, qtype = GRADE[grade]
            entries.append((ts, cid, -1, grade, ivl, last_ivl, factor, time_ms, qtype))

    return entries


def main():
    print("=" * 60)
    print("AnkiPlayground Setup — AnkiTov Live Demo")
    print("=" * 60)

    if not DEMO_PATH.exists():
        print(f"ERROR: Demo collection not found at {DEMO_PATH}")
        print("  Open Anki → File → Open Backup → Create Demo")
        sys.exit(1)

    # Read card IDs from the target deck (use parameterised query to avoid COLLATE issue)
    conn_d = sqlite3.connect(str(DEMO_PATH))
    card_ids = [r[0] for r in conn_d.execute(
        "SELECT id FROM cards WHERE did = ?", (DECK_ID,)
    ).fetchall()]
    conn_d.close()

    if not card_ids:
        print(f"ERROR: Deck {DECK_NAME!r} (id={DECK_ID}) not in demo collection")
        sys.exit(1)

    print(f"Deck: {DECK_NAME!r}  |  cards: {len(card_ids)}")
    total = 0

    for user_name, short_id, daily, gw, start_day, pattern in USERS:
        user_dir  = PLAYGROUND / user_name
        col_path  = user_dir / "collection.anki2"

        if user_dir.exists():
            print(f"\n-- {user_name} — exists, skipping")
            continue

        print(f"\n-- {user_name} --")
        user_dir.mkdir(parents=True)
        shutil.copy2(DEMO_PATH, col_path)

        conn = sqlite3.connect(str(col_path))
        conn.execute("PRAGMA journal_mode=WAL")

        entries = seed(short_id, daily, gw, start_day, pattern, card_ids)
        total += len(entries)

        conn.executemany(
            "INSERT INTO revlog VALUES (?,?,?,?,?,?,?,?,?)", entries
        )

        if entries:
            latest_ts = max(e[0] for e in entries)
            conn.execute("UPDATE col SET mod = ? WHERE id = 1", (latest_ts // 1000,))
            # Mark all reviewed cards as queue=1, type=1 with final grade state
            seen = {}
            for e in entries:
                cid, grade = e[1], e[3]
                if cid not in seen:
                    seen[cid] = grade
            for cid, grade in seen.items():
                _, ivl, _, factor, _, _ = GRADE[grade]
                conn.execute(
                    "UPDATE cards SET queue=1, type=1, ivl=?, factor=?, "
                    "reps=reps+1, mod=? WHERE id=?",
                    (ivl, factor, latest_ts // 1000, cid)
                )

        conn.commit()
        conn.close()

        target_ret = sum(g * w for g, w in gw.items())
        print(f"  ✓ {len(entries):,} entries | {pattern} | ~{target_ret:.0%} retention")

    print(f"\n{'=' * 60}")
    print(f"Done — {total:,} total revlog rows across {len(USERS)} users")
    print(f"Profiles: {PLAYGROUND}")
    print(f"\nTo activate AnkiConnect (Zone 2) for each user:")
    for u, *_ in USERS:
        print(f"  open -n /Applications/Anki.app --args -p '{u}'")
    print(f"\n  Ensure anki-connect add-on is installed in each profile.")
    print(f"\nFor forensic Zone 1 reads:")
    print(f"  export ANKICOLLECTION_PATH='{PLAYGROUND}/Maya Chen/collection.anki2'")
    print(f"  # then: cargo run")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    random.seed(42)
    main()