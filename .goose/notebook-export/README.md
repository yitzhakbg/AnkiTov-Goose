# AnkiTov-C → Gemini Notebook sync pipeline

REBUILT 2026-10-19 after the `.goose/` wipe discovered that day (original
README + merge_docs.py lost; reconstructed from session memory + the wrapper
script, which survived at `~/bin/ankitov-notebook-export.sh`). Source lists
were verified against the Oct-15 recorded counts (2+45+36+35+43 = 161 sources)
and drift naturally as the repo grows.

## Architecture

```
repo edit → launchd user.ybg.ankitov-notebook-export (every 30 min, RunAtLoad)
          → ~/bin/ankitov-notebook-export.sh
          → .goose/notebook-export/merge_docs.py   (always runs, ~seconds)
          → sha256 gate vs ~/Library/Logs/ankitov-notebook-export.pushed.sha
          → rclone push (6 files) → gdrive:Synced AnkiTov Files for Gemini Notebook
             (--drive-root-folder-id root — the gdrive: remote's default root is
              scoped to "Goose Backup Bundles", NOT the real Drive root)
          → Gemini Notebook Drive sources auto-sync every few minutes
Total lag: repo edit → notebook ≈ 35 min. Zero manual steps.
```

## Components

| Component | Path | Notes |
|---|---|---|
| Merger | `.goose/notebook-export/merge_docs.py` | disk-only (.goose/ gitignored) |
| Wrapper | `~/bin/ankitov-notebook-export.sh` | change-aware gate + non-blocking NotebookLM 05-code refresh (T-161) |
| LaunchAgent | `user.ybg.ankitov-notebook-export` | RunAtLoad + StartInterval 1800 |
| Log | `~/Library/Logs/ankitov-notebook-export.log` | DIFF lines + push results |
| Push state | `~/Library/Logs/ankitov-notebook-export.pushed.sha` | concatenated sha256 of the 6 outputs |
| 05-code state | `~/Library/Logs/ankitov-notebook-export.pushed.05-code.sha` | gates the static NotebookLM source refresh |
| Drive target | `gdrive:Synced AnkiTov Files for Gemini Notebook` | ID 1Wu8sidOvFmu6DOujpt6ajpX6ZnznQjPp, real My Drive root |
| Notebook | ID 7bfd98e6-3511-4e40-b223-64d0e0ca9716 | 5 Drive sources + 1 static (05-code-core) |

## The 6 sources (what merge_docs.py writes)

| File | Contents | Rule |
|---|---|---|
| 00-overview.md | README.md + CHANGELOG.md | |
| 01-specs-core.md | specs/** md | minus specs/{outreach,launch,media,marketing}/ |
| 02-project-knowledge.md | project-knowledge/** md | |
| 03-docs.md | docs/ + docs-repository/ md/mdx | mdBook build HTML excluded |
| 04-launch-marketing.md | blog + content + specs/{launch,media,marketing} md | site* generated HTML/CSS/SVG excluded (~24MB noise) |
| 05-code-core.md | backend/{Cargo.toml,config,i18n,resources,src,tests} + ankitov-budget-gate/{Cargo.toml,src} + addons/ankitov_session_driver + AnkiPlayGround/{addons21,profiles_update.py,setup_ankiplayground.py,setup_stage_decks.py} + root Cargo.toml | wide text-suffix net; ~2.5MB |

Every section is headed `# FILE: <repo path>` for citations. Doc outputs take
markdown-family files only; the code output takes the wide text net.

## Gotchas (carried from the original README + rebuild)

1. **gdrive: root scoping** — the remote's `root_folder_id` points at "Goose
   Backup Bundles"; every notebook push MUST pass `--drive-root-folder-id root`.
2. **Update-in-place** — rclone copy preserves file IDs, so notebook Drive
   sources stay connected; never delete+re-add the 5 Drive sources (destroys
   citation history).
3. **05-code-core.md is a STATIC NotebookLM source** (Drive-linked .md is not
   supported by `notebooklm source add-drive`) — the wrapper delete+re-adds it
   via the notebooklm CLI when its sha256 changes (non-blocking).
4. **MANIFEST.json is local-only** (embeds generated_at; excluded from the push
   list and the gate).
5. **Failed push auto-retries** — state updates only after a successful push.
6. **merge_docs.py failure aborts the run** (Drive left as-is) — watch the log
   for `merge_docs.py FAILED`.
7. **.goose/ is gitignored** — this whole directory is disk-only. The recipe
   mirrors live in AnkiTov-goose/.goose/recipes/ (tracked); THIS script does not
   live there. If you wipe .goose/, this pipeline breaks silently every 30 min —
   check `~/Library/Logs/ankitov-notebook-export.log`.
8. **Word-cap discipline** — keep every output under ~450K words (the notebook
   per-source cap); the md-only rule for doc outputs is what keeps 04 small.

## Ops

```bash
# run now
~/bin/ankitov-notebook-export.sh            # or: launchctl kickstart gui/$(id -u)/user.ybg.ankitov-notebook-export
# force push (ignore gate)
rm ~/Library/Logs/ankitov-notebook-export.pushed.sha && ~/bin/ankitov-notebook-export.sh
# health
tail -20 ~/Library/Logs/ankitov-notebook-export.log
launchctl list | grep notebook-export
```

## History

- 2026-10-15: pipeline created (5 doc sources, weekly Monday cadence).
- 2026-10-17: bash syntax bug fixed (runs were dying before push); cadence → 30 min, change-aware gate.
- 2026-10-17: retargeted to "Synced AnkiTov Files for Gemini Notebook" at real Drive root (root override).
- 2026-10-18: 05-code-core.md added (code-as-md pivot after NotebookLM refused folder uploads); T-161 static-source refresh.
- 2026-10-19: .goose/ wipe destroyed merge_docs.py + this README; both rebuilt from documented spec; source lists re-derived and verified against recorded counts.
