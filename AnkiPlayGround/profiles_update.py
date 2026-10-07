#!/usr/bin/env python3
"""
AnkiTov AnkiPlayGround — Classroom Profile Updater v2
======================================================
Transforms 28 student profiles into a realistic classroom testing environment.
Uses ALL cards (not just those with due dates in range) for review generation.

Archetypes:
  - Star Students (5)     — daily practice, high retention
  - Consistent (7)        — practice most days, occasional miss
  - Weekend Skippers (4)  — skip weekends, solid weekday practice
  - Inconsistent (5)      — sporadic, binge sessions, catch-up mode
  - Struggling (4)        — low retention, many lapses, falling behind
  - New Joiners (2)       — recently started, lower total reviews
  - Drop-offs (1)         — stopped entirely
"""

import sqlite3
import datetime
import random
import os
import shutil

BASE = "/Volumes/YBG1TB4Mac/AnkiTov/AnkiPlayGround"
TODAY = datetime.date(2026, 7, 14)

def unix_ms(dt):
    return int(dt.timestamp() * 1000)

# ── Archetype Definitions ──────────────────────────────────────────────────

ARCHETYPES = {
    "star": {
        "label": "Star Student",
        "profiles": ["Aisha Patel", "Hana Yoshida", "Maya Chen", "Nia Jackson", "Jasmine Nguyen"],
        "daily_prob": 0.97,
        "reviews_per_day": (280, 340),
        "lapse_prob": 0.04,
        "avg_time_ms": 7500,
        "skip_days": set(),
        "new_cards_per_day": 15,
    },
    "consistent": {
        "label": "Consistent Practicer",
        "profiles": ["Ella Johansson", "James Park", "Priya Sharma", "Noah Torres",
                      "Zoe Okafor", "Carla Mendez", "Layla Haddad"],
        "daily_prob": 0.82,
        "reviews_per_day": (220, 290),
        "lapse_prob": 0.07,
        "avg_time_ms": 9000,
        "skip_days": {datetime.date(2026, 7, 11)},  # skipped Saturday
        "new_cards_per_day": 10,
    },
    "weekend_skipper": {
        "label": "Weekend Skipper",
        "profiles": ["Lucas Kim", "Sofia Lima", "Oscar Lindqvist", "Quinn Sanders"],
        "daily_prob": 0.95,
        "reviews_per_day": (200, 270),
        "lapse_prob": 0.09,
        "avg_time_ms": 10000,
        "skip_days": {datetime.date(2026, 7, 11), datetime.date(2026, 7, 12)},
        "new_cards_per_day": 8,
    },
    "inconsistent": {
        "label": "Inconsistent/Binge",
        "profiles": ["Diego Ramirez", "Amir Hassan", "Ibrahim Sow", "Riku Tanaka", "George Thompson"],
        "daily_prob": 0.50,
        "reviews_per_day": (150, 220),
        "lapse_prob": 0.14,
        "avg_time_ms": 12000,
        "skip_days": {datetime.date(2026, 7, 10), datetime.date(2026, 7, 12), datetime.date(2026, 7, 13)},
        "new_cards_per_day": 5,
    },
    "struggling": {
        "label": "Struggling/At-Risk",
        "profiles": ["Fatima Al-Rashid", "Marcus Webb", "Petra Novak", "Ben Carter"],
        "daily_prob": 0.35,
        "reviews_per_day": (80, 170),
        "lapse_prob": 0.28,
        "avg_time_ms": 16000,
        "skip_days": {datetime.date(2026, 7, 10), datetime.date(2026, 7, 11), datetime.date(2026, 7, 13)},
        "new_cards_per_day": 3,
    },
    "new_joiner": {
        "label": "New Joiner",
        "profiles": ["Emma Wilson", "Kevin O'Brien"],
        "daily_prob": 0.65,
        "reviews_per_day": (60, 140),
        "lapse_prob": 0.17,
        "avg_time_ms": 14000,
        "skip_days": {datetime.date(2026, 7, 12)},
        "new_cards_per_day": 10,
    },
    "dropoff": {
        "label": "Drop-off",
        "profiles": ["User 1"],
        "daily_prob": 0.0,
        "reviews_per_day": (0, 0),
        "lapse_prob": 0.0,
        "avg_time_ms": 0,
        "skip_days": set(),
        "new_cards_per_day": 0,
    },
}

RECENT_START = datetime.date(2026, 7, 10)
RECENT_END = TODAY

def update_profile(profile_name, archetype):
    db_path = os.path.join(BASE, profile_name, "collection.anki2")
    if not os.path.exists(db_path):
        print(f"  ⚠️  Database not found: {db_path}")
        return False

    # Backup
    backup_path = db_path + ".bak"
    if not os.path.exists(backup_path):
        shutil.copy2(db_path, backup_path)

    conn = sqlite3.connect(db_path)
    conn.isolation_level = None  # autocommit mode
    conn.execute("PRAGMA journal_mode=DELETE")
    conn.execute("PRAGMA synchronous=OFF")
    cur = conn.cursor()

    # Get collection epoch
    cur.execute("SELECT crt FROM col")
    crt = cur.fetchone()[0]
    col_epoch = datetime.datetime.fromtimestamp(crt)

    # ── Step 1: Remove future reviews (from RECENT_START onwards) ──
    cutoff_ms = unix_ms(datetime.datetime(RECENT_START.year, RECENT_START.month, RECENT_START.day))
    cur.execute("SELECT COUNT(*) FROM revlog WHERE id >= ?", (cutoff_ms,))
    removed_count = cur.fetchone()[0]
    cur.execute("DELETE FROM revlog WHERE id >= ?", (cutoff_ms,))

    # ── Step 2: Load all cards ──
    cur.execute("SELECT id, nid, did, type, queue, due, ivl, factor, reps, lapses, left FROM cards ORDER BY id")
    all_cards = cur.fetchall()
    
    review_pool = [c for c in all_cards if c[3] == 2]  # review cards (type at idx 3 in SELECT)
    new_pool = [c for c in all_cards if c[3] == 0]      # new cards
    new_pool_idx = 0  # pointer for doling out new cards
    
    print(f"  📊 Removed {removed_count} future reviews, {len(review_pool)} review cards, {len(new_pool)} new cards")

    # ── Step 3: Generate reviews day by day ──
    total_generated = 0
    reviewed_this_period = set()
    current_day = RECENT_START
    # We'll generate review IDs from the day timestamp + offset
    # to ensure they fall on the correct date
    
    card_state = {}
    for c in all_cards:
        card_state[c[0]] = {
            'type': c[3], 'queue': c[4], 'due': c[5], 'ivl': c[6],
            'factor': c[7], 'reps': c[8], 'lapses': c[9], 'left': c[10]
        }
    
    while current_day <= RECENT_END:
        is_skip = current_day in archetype["skip_days"]
        practices = (random.random() < archetype["daily_prob"]) and not is_skip
        
        day_epoch = datetime.datetime(current_day.year, current_day.month, current_day.day)
        day_due_base = int((day_epoch - col_epoch).total_seconds() / 86400)
        
        # For dropoff, skip all days
        if archetype["daily_prob"] == 0.0:
            practices = False
        
        if not practices:
            date_str = current_day.strftime("%a %m/%d")
            print(f"    📅 {date_str}: ❌ skipped")
            current_day += datetime.timedelta(days=1)
            continue
        
        # Begin transaction for this day's processing
        cur.execute("BEGIN")
        
        # Generate a unique ID base for this day from the day timestamp
        day_rid_base = unix_ms(day_epoch.replace(hour=0, minute=0, second=0)) + 1
        day_rid_offset = 0
        
        target = random.randint(*archetype["reviews_per_day"])
        new_this_day = min(archetype["new_cards_per_day"], max(0, len(new_pool) - new_pool_idx))
        
        generated = 0
        new_used = 0
        
        # Pick cards from the pool that haven't been reviewed today
        available = [cid for cid in card_state if cid not in reviewed_this_period]
        random.shuffle(available)
        
        # First, prioritize new cards
        for _ in range(new_this_day):
            if new_pool_idx >= len(new_pool):
                break
            c = new_pool[new_pool_idx]
            cid = c[0]
            new_pool_idx += 1
            new_used += 1
            
            # New card review: ease=3 (good), interval=1 day
            hour = random.randint(8, 22)
            rt = day_epoch.replace(hour=hour, minute=random.randint(0, 59), second=random.randint(0, 59))
            
            time_spent = int(random.gauss(12000, 4000))
            time_spent = max(2000, min(60000, time_spent))
            
            cur.execute("""INSERT INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type)
                           VALUES (?, ?, -1, 3, 1, 0, 2500, ?, 0)""",
                        (day_rid_base + day_rid_offset, cid, time_spent))
            day_rid_offset += 1
            
            # Update card state
            new_due = day_due_base + 1
            cur.execute("""UPDATE cards SET type=2, queue=2, due=?, ivl=1, factor=2500,
                           reps=1, lapses=0, left=0, mod=?, usn=-1 WHERE id=?""",
                        (new_due, int(rt.timestamp()), cid))
            
            card_state[cid] = {'type': 2, 'queue': 2, 'due': new_due, 'ivl': 1,
                               'factor': 2500, 'reps': 1, 'lapses': 0, 'left': 0}
            reviewed_this_period.add(cid)
            generated += 1
        
        # Review remaining cards from pool
        needed = target - generated
        selected = [cid for cid in available if cid not in reviewed_this_period][:needed]
        
        for cid in selected:
            state = card_state.get(cid)
            if not state:
                continue
            
            # Determine if lapse
            is_lapse = random.random() < archetype["lapse_prob"]
            
            # Determine ease
            if is_lapse:
                ease = 1
            else:
                r = random.random()
                if r < 0.50:
                    ease = 3  # Good
                elif r < 0.65:
                    ease = 2  # Hard
                elif r < 0.85:
                    ease = 4  # Easy
                else:
                    ease = 1  # Again
            
            hour = random.randint(8, 22)
            rt = day_epoch.replace(hour=hour, minute=random.randint(0, 59), second=random.randint(0, 59))
            
            time_spent = int(random.gauss(archetype["avg_time_ms"], archetype["avg_time_ms"] * 0.3))
            time_spent = max(1000, min(60000, time_spent))
            
            ivl = state['ivl']
            factor = state['factor']
            reps = state['reps']
            lapses = state['lapses']
            
            if ease == 1:  # Again
                new_ivl = max(1, int(ivl * 0.2))
                new_factor = max(1300, factor - 200)
                new_lapses = lapses + 1
                revlog_type = 2  # relearn
            elif ease == 2:  # Hard
                new_ivl = max(1, int(ivl * 1.3))
                new_factor = max(1300, factor - 50)
                new_lapses = lapses
                revlog_type = 1  # review
            elif ease == 3:  # Good
                new_ivl = max(1, int(ivl * factor / 1000))
                new_factor = max(1300, factor)
                new_lapses = lapses
                revlog_type = 1  # review
            else:  # Easy
                new_ivl = max(1, int(ivl * factor / 1000 * 1.3))
                new_factor = max(1300, min(5000, int(factor * 1.05)))
                new_lapses = lapses
                revlog_type = 1  # review
            
            new_due = day_due_base + new_ivl
            new_reps = reps + 1
            
            cur.execute("""INSERT INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type)
                           VALUES (?, ?, -1, ?, ?, ?, ?, ?, ?)""",
                        (day_rid_base + day_rid_offset, cid, ease, new_ivl, ivl, new_factor, time_spent, revlog_type))
            day_rid_offset += 1
            
            cur.execute("""UPDATE cards SET type=2, queue=2, due=?, ivl=?, factor=?,
                           reps=?, lapses=?, left=0, mod=?, usn=-1 WHERE id=?""",
                        (new_due, new_ivl, new_factor, new_reps, new_lapses,
                         int(rt.timestamp()), cid))
            
            card_state[cid] = {'type': 2, 'queue': 2, 'due': new_due, 'ivl': new_ivl,
                               'factor': new_factor, 'reps': new_reps, 'lapses': new_lapses, 'left': 0}
            reviewed_this_period.add(cid)
            generated += 1
        
        total_generated += generated
        date_str = current_day.strftime("%a %m/%d")
        print(f"    📅 {date_str}: {generated} reviews ({new_used} new cards)")
        cur.execute("COMMIT")
        current_day += datetime.timedelta(days=1)
    
    # ── Step 4: Update col mod time ──
    now_ts = int(datetime.datetime.now().timestamp())
    cur.execute("BEGIN")
    cur.execute("UPDATE col SET mod=?", (now_ts,))
    cur.execute("COMMIT")
    conn.close()
    print(f"  ✅ Total: {total_generated} reviews generated across period")
    return True


def main():
    random.seed(42)
    
    print("=" * 70)
    print("  AnkiTov AnkiPlayGround — Classroom Profile Updater v2")
    print(f"  Today: {TODAY}")
    print("=" * 70)
    
    profile_archetype = {}
    for aname, aconfig in ARCHETYPES.items():
        for p in aconfig["profiles"]:
            profile_archetype[p] = aconfig
    
    all_profiles = sorted(profile_archetype.keys(), key=lambda x: x.lower())
    print(f"  Profiles: {len(all_profiles)}")
    print()
    
    for profile in all_profiles:
        archetype = profile_archetype[profile]
        print(f"\n{'─' * 60}")
        print(f"  📋 {profile} — {archetype['label']}")
        print(f"{'─' * 60}")
        update_profile(profile, archetype)
    
    print(f"\n{'=' * 70}")
    print("  ✅ All profiles updated!")
    print(f"  🗂️  Backups saved as collection.anki2.bak")
    print(f"{'=' * 70}")


if __name__ == "__main__":
    main()