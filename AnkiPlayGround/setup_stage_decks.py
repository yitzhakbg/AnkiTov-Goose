#!/usr/bin/env python3
"""
AnkiTov AnkiPlayground — 10-User Distribution with Stage 1/2/3 Decks

Merges 3 .apkg-extracted collections into one base, creates 10 user profiles,
and seeds unique practice data (revlog) per user per deck.

Each user gets all 3 decks with distinct practice patterns over 30 days.

Usage:
    python3 setup_stage_decks.py
"""

import sqlite3
import shutil
import os
import random
from datetime import datetime, timedelta

# ─── Paths ───────────────────────────────────────────────────────────────────

BASE_DIR = "/Volumes/YBG1TB4Mac/AnkiTov/AnkiPlayGround"
STAGE_DBS = {
    "Stage 1": "/tmp/apkg_stage1/collection_decrypted.anki2",
    "Stage 2": "/tmp/apkg_stage2/collection_decrypted.anki2",
    "Stage 3": "/tmp/apkg_stage3/collection_decrypted.anki2",
}
BASE_COLLECTION = "/tmp/ankitov_base_collection.anki2"

# ─── 10 User Profiles ────────────────────────────────────────────────────────
# grade_weights: (again%, hard%, good%, easy%)

USERS = [
    {"name": "Maya Chen",    "daily_per_deck": 25, "weights": (0.05, 0.10, 0.75, 0.10), "start_offset": 0, "weekend_only": False},
    {"name": "Lucas Kim",    "daily_per_deck": 12, "weights": (0.15, 0.25, 0.50, 0.10), "start_offset": 0, "weekend_only": False},
    {"name": "Priya Sharma", "daily_per_deck": 22, "weights": (0.02, 0.03, 0.30, 0.65), "start_offset": 0, "weekend_only": False},
    {"name": "Noah Torres",  "daily_per_deck": 18, "weights": (0.35, 0.40, 0.20, 0.05), "start_offset": 0, "weekend_only": False},
    {"name": "Emma Wilson",   "daily_per_deck": 30, "weights": (0.08, 0.12, 0.70, 0.10), "start_offset": 0, "weekend_only": True},
    {"name": "Amir Hassan",   "daily_per_deck": 16, "weights": (0.08, 0.15, 0.65, 0.12), "start_offset": 0, "weekend_only": False},
    {"name": "Sofia Lima",    "daily_per_deck": 20, "weights": (0.12, 0.20, 0.55, 0.13), "start_offset": 0, "weekend_only": False, "decline_after_day": 15},
    {"name": "James Park",    "daily_per_deck": 24, "weights": (0.04, 0.08, 0.68, 0.20), "start_offset": 5, "weekend_only": False},
    {"name": "Zoe Okafor",    "daily_per_deck": 19, "weights": (0.06, 0.10, 0.72, 0.12), "start_offset": 0, "weekend_only": False},
    {"name": "Riku Tanaka",   "daily_per_deck": 21, "weights": (0.10, 0.18, 0.60, 0.12), "start_offset": 0, "weekend_only": False, "stop_after_day": 20},
]

WINDOW_DAYS = 30
GRADE_RETENTION = {1: 0.30, 2: 0.70, 3: 0.85, 4: 0.95}
GRADE_FACTOR = {1: 1300, 2: 1500, 3: 2300, 4: 2500}


# ─── unicase workaround ──────────────────────────────────────────────────────
# Python's bundled SQLite lacks the `unicase` collation that Anki's schema
# uses. We register a no-op collation (case-insensitive comparison) so that
# INSERT/SELECT/CREATE INDEX operations on unicase columns don't crash.

def _unicase_cmp(a, b):
    a_low = a.lower() if isinstance(a, str) else a
    b_low = b.lower() if isinstance(b, str) else b
    if a_low == b_low:
        return 0
    return -1 if a_low < b_low else 1

def open_db(path):
    """Open an Anki SQLite DB with the unicase collation registered."""
    conn = sqlite3.connect(path)
    conn.create_collation("unicase", _unicase_cmp)
    return conn


# ─── Helpers ────────────────────────────────────────────────────────────────

def weighted_choice(weights):
    r = random.random()
    cumulative = 0.0
    for i, w in enumerate(weights):
        cumulative += w
        if r < cumulative:
            return i + 1
    return len(weights)


# ─── Merge 3 stage collections into one base ────────────────────────────────

def merge_collections():
    print("─── Merging 3 stage databases ───")

    shutil.copy2(STAGE_DBS["Stage 1"], BASE_COLLECTION)
    conn = open_db(BASE_COLLECTION)
    c = conn.cursor()

    stage1_decks = c.execute("SELECT id, name FROM decks").fetchall()
    print(f"  Base (Stage 1): {len(stage1_decks)} deck(s): {[d[1] for d in stage1_decks]}")
    s1_cards = c.execute("SELECT COUNT(*) FROM cards").fetchone()[0]
    s1_notes = c.execute("SELECT COUNT(*) FROM notes").fetchone()[0]
    print(f"  Stage 1: {s1_notes} notes, {s1_cards} cards")

    for stage_name in ["Stage 2", "Stage 3"]:
        src = open_db(STAGE_DBS[stage_name])
        sc = src.cursor()

        deck_rows = sc.execute(
            "SELECT id, name, mtime_secs, usn, common, kind FROM decks WHERE id != 1"
        ).fetchall()

        for deck_row in deck_rows:
            deck_id = deck_row[0]
            deck_name = deck_row[1]
            print(f"  Merging {stage_name}: deck '{deck_name}' (id={deck_id})")

            c.execute(
                "INSERT OR REPLACE INTO decks (id, name, mtime_secs, usn, common, kind) VALUES (?, ?, ?, ?, ?, ?)",
                deck_row,
            )

            # Copy notes for this deck's cards
            src_notes = sc.execute(
                "SELECT DISTINCT n.id, n.guid, n.mid, n.mod, n.usn, n.tags, n.flds, n.sfld, n.csum, n.flags, n.data "
                "FROM notes n JOIN cards c ON c.nid = n.id WHERE c.did = ?",
                [deck_id],
            ).fetchall()
            for n in src_notes:
                c.execute(
                    "INSERT OR REPLACE INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) "
                    "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    n,
                )

            # Copy cards for this deck
            src_cards = sc.execute(
                "SELECT id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data "
                "FROM cards WHERE did = ?",
                [deck_id],
            ).fetchall()
            for card in src_cards:
                c.execute(
                    "INSERT OR REPLACE INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data) "
                    "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    card,
                )

        # Copy notetypes
        for nt in sc.execute("SELECT id, name, mtime_secs, usn, config FROM notetypes").fetchall():
            if c.execute("SELECT COUNT(*) FROM notetypes WHERE id = ?", [nt[0]]).fetchone()[0] == 0:
                c.execute("INSERT INTO notetypes (id, name, mtime_secs, usn, config) VALUES (?,?,?,?,?)", nt)

        # Copy templates
        for tpl in sc.execute("SELECT ntid, ord, name, mtime_secs, usn, config FROM templates").fetchall():
            if c.execute("SELECT COUNT(*) FROM templates WHERE ntid = ? AND ord = ?", [tpl[0], tpl[1]]).fetchone()[0] == 0:
                c.execute("INSERT INTO templates (ntid, ord, name, mtime_secs, usn, config) VALUES (?,?,?,?,?,?)", tpl)

        src.close()

    conn.commit()

    all_decks = c.execute("SELECT id, name FROM decks").fetchall()
    total_notes = c.execute("SELECT COUNT(*) FROM notes").fetchone()[0]
    total_cards = c.execute("SELECT COUNT(*) FROM cards").fetchone()[0]
    total_revlog = c.execute("SELECT COUNT(*) FROM revlog").fetchone()[0]
    print(f"\n  ✅ Merged base collection:")
    print(f"     Decks: {[(d[0], d[1]) for d in all_decks]}")
    print(f"     Notes: {total_notes}, Cards: {total_cards}, Revlog: {total_revlog}")
    conn.close()
    return all_decks


# ─── Seed one user's collection with unique practice data ────────────────────

def seed_user_collection(user, base_decks):
    name = user["name"]
    user_dir = os.path.join(BASE_DIR, name)
    os.makedirs(user_dir, exist_ok=True)
    user_col = os.path.join(user_dir, "collection.anki2")

    shutil.copy2(BASE_COLLECTION, user_col)
    conn = open_db(user_col)
    c = conn.cursor()

    random.seed(hash(name) & 0xFFFFFFFF)

    # Monotonic counter to ensure revlog IDs are unique even if two reviews
    # land in the same millisecond.
    rev_id_counter = 0

    now = datetime(2026, 6, 28, 12, 0, 0)
    start_offset = user.get("start_offset", 0)
    stop_after = user.get("stop_after_day", WINDOW_DAYS)
    decline_after = user.get("decline_after_day", None)
    weekend_only = user.get("weekend_only", False)
    weights = user["weights"]
    daily = user["daily_per_deck"]

    total_revlog = 0

    for deck_id, deck_name in base_decks:
        if deck_name == "Default":
            continue

        card_ids = [r[0] for r in c.execute("SELECT id FROM cards WHERE did = ?", [deck_id]).fetchall()]
        if not card_ids:
            continue

        for day in range(start_offset, stop_after):
            date = now - timedelta(days=WINDOW_DAYS - day)

            if weekend_only and date.weekday() < 5:
                continue

            day_weights = weights
            if decline_after and day >= decline_after:
                day_weights = (
                    min(weights[0] + 0.10, 0.50),
                    min(weights[1] + 0.05, 0.40),
                    max(weights[2] - 0.10, 0.10),
                    max(weights[3] - 0.05, 0.02),
                )

            n_reviews = max(1, int(daily * random.uniform(0.8, 1.2)))

            for _ in range(n_reviews):
                card_id = random.choice(card_ids)
                grade = weighted_choice(day_weights)

                review_time = date + timedelta(
                    hours=random.randint(7, 22),
                    minutes=random.randint(0, 59),
                    seconds=random.randint(0, 59),
                )
                # Ensure unique revlog ID: base timestamp + monotonic counter
                review_ts_ms = int(review_time.timestamp() * 1000) + rev_id_counter
                rev_id_counter += 1

                last_ivl = 0
                prev = c.execute(
                    "SELECT ivl FROM revlog WHERE cid = ? ORDER BY id DESC LIMIT 1", [card_id]
                ).fetchone()
                if prev:
                    last_ivl = prev[0]

                if grade == 1:
                    new_ivl = 0
                elif grade == 2:
                    new_ivl = max(1, int(last_ivl * 1.2) + 1)
                elif grade == 3:
                    new_ivl = max(1, int(last_ivl * 2.0) + 1) if last_ivl > 0 else 1
                else:
                    new_ivl = max(1, int(last_ivl * 2.5) + 1) if last_ivl > 0 else 2
                new_ivl = min(new_ivl, 365)

                factor = GRADE_FACTOR[grade]
                time_spent = random.randint(3000, 60000)
                rev_type = 1 if last_ivl == 0 else 2

                c.execute(
                    "INSERT INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type) "
                    "VALUES (?, ?, -1, ?, ?, ?, ?, ?, ?)",
                    (review_ts_ms, card_id, grade, new_ivl, last_ivl, factor, time_spent, rev_type),
                )

                reps = 1 if last_ivl == 0 else c.execute(
                    "SELECT reps FROM cards WHERE id = ?", [card_id]
                ).fetchone()[0] + 1

                lapses = c.execute("SELECT lapses FROM cards WHERE id = ?", [card_id]).fetchone()[0]
                if grade == 1:
                    lapses += 1

                queue = 0 if (grade == 1 and reps == 1) else (1 if grade == 1 else 2)
                due = int(date.timestamp() // 86400) + new_ivl if new_ivl > 0 else int(date.timestamp() // 86400)

                c.execute(
                    "UPDATE cards SET type=?, queue=?, due=?, ivl=?, factor=?, reps=?, lapses=? WHERE id=?",
                    (2 if last_ivl > 0 else 0, queue, due, new_ivl, factor, reps, lapses, card_id),
                )
                total_revlog += 1

    conn.commit()

    final_revlog = c.execute("SELECT COUNT(*) FROM revlog").fetchone()[0]
    final_cards = c.execute("SELECT COUNT(*) FROM cards").fetchone()[0]
    grades = c.execute("SELECT ease, COUNT(*) FROM revlog GROUP BY ease ORDER BY ease").fetchall()
    total_reviews = sum(g[1] for g in grades)
    retention = sum(GRADE_RETENTION.get(g[0], 0.85) * g[1] for g in grades) / max(total_reviews, 1)

    conn.close()
    print(f"  ✅ {name}: {final_revlog} revlog entries, {final_cards} cards, retention ~{retention:.0%}")
    print(f"     Grades: {dict(grades)}")
    return total_revlog


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    print("╔══════════════════════════════════════════════════════════╗")
    print("║  AnkiTov — 10-User Distribution with Stage 1/2/3 Decks  ║")
    print("╚══════════════════════════════════════════════════════════╝\n")

    base_decks = merge_collections()
    print()

    print("─── Creating 10 user profiles with unique practice data ───\n")
    grand_total = 0
    for user in USERS:
        grand_total += seed_user_collection(user, base_decks)
        print()

    print(f"═══════════════════════════════════════════════════════════")
    print(f"  ✅ Done! 10 users, {grand_total:,} total revlog entries")
    print(f"  Each user has 3 decks: Stage 1 (800 cards), Stage 2 (600), Stage 3 (762)")
    print(f"  Base collection: {BASE_COLLECTION}")
    print(f"═══════════════════════════════════════════════════════════")


if __name__ == "__main__":
    main()