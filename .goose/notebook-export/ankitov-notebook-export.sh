#!/bin/bash
# ankitov-notebook-export.sh — regenerate merged Gemini Notebook sources for AnkiTov-C
# and push them to Google Drive so the Drive-synced notebook sources pick up changes
# automatically.
#
# Target: "Synced AnkiTov Files for Gemini Notebook" at the REAL My Drive root
# (folder ID 1Wu8sidOvFmu6DOujpt6ajpX6ZnznQjPp). The gdrive remote's config scopes
# its root to the "Goose Backup Bundles" folder (root_folder_id), so this push
# overrides with --drive-root-folder-id root. Other gdrive: users (backup scripts)
# are unaffected — the override is per-command, here only.
#
# Change-aware: merge_docs.py always runs (cheap, ~1s), but the rclone push only fires
# when the 5 merged outputs differ from the last successful push. Safe to run on any
# cadence (launchd: every 30 min under user.ybg.ankitov-notebook-export).
#
# T-161 (2026-10-18): non-blocking NotebookLM stale-check + 05-code-core.md refresh.
#   - The 5 Drive-linked sources (00-overview..04-launch-marketing) auto-sync from
#     Drive in ~5-7 min after rclone copy — NEVER delete/re-add them (destroys
#     citation history, burns rate limits).
#   - 05-code-core.md is a static type=markdown source (Drive-linked .md is NOT
#     supported by `notebooklm source add-drive` — only Docs/Slides/Sheets/PDF).
#     When its sha256 changed, refresh it by delete + re-add via the notebooklm CLI.
#     This is NON-BLOCKING: any notebooklm failure logs a warning and the script
#     still exits 0 — the Drive export gate is never broken by NotebookLM.
set -u
LOG="$HOME/Library/Logs/ankitov-notebook-export.log"
OUT="/Volumes/YBG1TB4Mac/AnkiTov-C/.goose/notebook-export"
STATE="$HOME/Library/Logs/ankitov-notebook-export.pushed.sha"
CODE_STATE="$HOME/Library/Logs/ankitov-notebook-export.pushed.05-code.sha"
NOTEBOOK_ID="7bfd98e6-3511-4e40-b223-64d0e0ca9716"
CODE_SOURCE_ID="87f2e82b-88ef-4579-84d0-75e4e20811d0"
NLM="$HOME/.local/bin/notebooklm"
DEST="gdrive:Synced AnkiTov Files for Gemini Notebook"
stamp() { date '+%Y-%m-%d %H:%M:%S'; }
echo "$(stamp) === notebook-export run start ===" >> "$LOG"

if ! python3 "$OUT/merge_docs.py" >/dev/null 2>>"$LOG"; then
  echo "$(stamp) merge_docs.py FAILED — aborting (Drive left as-is)" >> "$LOG"
  exit 1
fi

FILES=(00-overview.md 01-specs-core.md 02-project-knowledge.md 03-docs.md 04-launch-marketing.md 05-code-core.md)
hash_now=""
for f in "${FILES[@]}"; do
  hash_now+="$(shasum -a 256 "$OUT/$f" | cut -d' ' -f1)"
done

# T-161: track 05-code-core.md's sha256 separately so we know when the static
# NotebookLM source needs a refresh (Drive-linked sources self-sync; this one doesn't).
code_hash_now="$(shasum -a 256 "$OUT/05-code-core.md" | cut -d' ' -f1)"
code_hash_pushed="$(cat "$CODE_STATE" 2>/dev/null || true)"

if [ -f "$STATE" ] && [ "$(cat "$STATE" 2>/dev/null)" = "$hash_now" ]; then
  echo "$(stamp) outputs unchanged since last push — skip" >> "$LOG"
  exit 0
fi

RCLONE=/opt/homebrew/bin/rclone
if [ ! -x "$RCLONE" ]; then
  echo "$(stamp) rclone not found — push skipped, will retry next run" >> "$LOG"
  exit 1
fi

if printf "%s\n" "${FILES[@]}" \
    | "$RCLONE" copy "$OUT" "$DEST" --drive-root-folder-id root --files-from - >> "$LOG" 2>&1; then
  printf "%s" "$hash_now" > "$STATE"
  echo "$(stamp) rclone push to $DEST OK" >> "$LOG"
else
  echo "$(stamp) rclone push FAILED (see rclone output above) — will retry next run" >> "$LOG"
  exit 1
fi

# --- T-161: non-blocking 05-code-core.md refresh (only when its content changed) ---
if [ -x "$NLM" ] && [ "$code_hash_now" != "$code_hash_pushed" ]; then
  echo "$(stamp) 05-code-core.md changed (sha256 ${code_hash_now:0:12}...) — refreshing static NotebookLM source (non-blocking)" >> "$LOG"
  if "$NLM" source delete "$CODE_SOURCE_ID" -n "$NOTEBOOK_ID" --yes >> "$LOG" 2>&1 \
     && "$NLM" source add --type file --title 05-code-core.md "$OUT/05-code-core.md" -n "$NOTEBOOK_ID" >> "$LOG" 2>&1; then
    printf "%s" "$code_hash_now" > "$CODE_STATE"
    echo "$(stamp) 05-code-core.md NotebookLM source refreshed OK" >> "$LOG"
  else
    echo "$(stamp) WARNING: notebooklm refresh of 05-code-core.md FAILED — Drive export unaffected, will retry next changed push" >> "$LOG"
  fi
elif [ ! -x "$NLM" ]; then
  echo "$(stamp) WARNING: notebooklm CLI not found at $NLM — 05-code-core.md refresh skipped" >> "$LOG"
fi

# --- T-161: post-push source health line (visibility in the log) ---
if [ -x "$NLM" ]; then
  echo "$(stamp) notebook source health: $("$NLM" source list -n "$NOTEBOOK_ID" --json 2>>"$LOG" \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    srcs=d.get("sources",[])
    ready=sum(1 for s in srcs if s.get("status")=="ready")
    degraded=sum(1 for s in srcs if s.get("is_drive_degraded"))
    print(f"{len(srcs)} sources, {ready} ready, {degraded} drive-degraded")
except Exception as e:
    print(f"health parse error: {e}")')" >> "$LOG"
fi

echo "$(stamp) === run end ===" >> "$LOG"
