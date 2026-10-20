#!/usr/bin/env python3
"""merge_docs.py — regenerate merged Gemini Notebook sources for AnkiTov-C.

REBUILT 2026-10-19 after the .goose/ wipe discovered that day (original script
lost; reconstructed from the documented pipeline spec — source lists verified
against the Oct-15 file counts recorded in session memory: 2+45+36+35+43=161
sources, plus 05-code-core.md added 2026-10-18). Counts drift as the repo grows;
the lists below are directory-walk based so they track the repo automatically.

Contract (consumed by ~/bin/ankitov-notebook-export.sh):
  - runs with NO arguments, from any cwd
  - writes 00-overview.md .. 05-code-core.md + MANIFEST.json into this dir
  - every section is headed "# FILE: <repo path>" so the notebook can cite paths
  - MANIFEST.json records per-output sha256; changed outputs log a DIFF line to
    STDERR (the wrapper sends stderr to the launchd log, stdout to /dev/null)
  - the wrapper pushes only the 6 .md files (MANIFEST stays local-only) and
    gates the push on the concatenated sha256 of the 6 outputs

Exclusions (by design): specs/outreach/ (campaign material, never synced),
buzz-hive/ (separate project), target/, node_modules/, binaries.
"""

import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent  # .goose/notebook-export/ -> repo root

TEXT_SUFFIXES = {
    ".md", ".mdx", ".txt", ".toml", ".yaml", ".yml", ".json", ".rs", ".py",
    ".js", ".ts", ".css", ".html", ".svg", ".sh", ".sql", ".ftl", ".properties",
}


DOC_SUFFIXES = {".md", ".mdx", ".txt"}


def walk(rel_dir, extra_excludes=(), suffixes=None):
    """Text files under rel_dir (recursive), sorted, as repo-relative paths.
    suffixes=None -> wide TEXT_SUFFIXES net (code); doc outputs pass DOC_SUFFIXES
    so generated site HTML/CSS/SVG noise (specs/launch/site*, docs/ mdBook build)
    never inflates a source past the notebook's ~450K-word cap."""
    want = suffixes or TEXT_SUFFIXES
    base = ROOT / rel_dir
    if not base.exists():
        return []
    out = []
    for p in sorted(base.rglob("*")):
        if not p.is_file():
            continue
        if p.suffix.lower() not in want:
            continue
        rel = p.relative_to(ROOT).as_posix()
        if any(x in rel for x in extra_excludes):
            continue
        out.append(rel)
    return out


def spec_core():
    """specs/** minus outreach (campaigns), launch, media, marketing (those go to 04)."""
    return walk("specs", extra_excludes=("specs/outreach/", "specs/launch/", "specs/media/", "specs/marketing/"), suffixes=DOC_SUFFIXES)


def docs_all():
    """docs/ markdown + docs-repository markdown/mdx (mdBook build HTML excluded)."""
    return walk("docs", suffixes=DOC_SUFFIXES) + [p for p in walk("docs-repository", suffixes=DOC_SUFFIXES) if p.endswith((".md", ".mdx"))]


def launch_marketing():
    """blog + content + specs/{launch,media,marketing} — md-family only
    (specs/launch/site* generated HTML/CSS/SVG is noise, ~24MB if included)."""
    return (walk("blog", suffixes=DOC_SUFFIXES) + walk("content", suffixes=DOC_SUFFIXES)
            + walk("specs/launch", suffixes=DOC_SUFFIXES) + walk("specs/media", suffixes=DOC_SUFFIXES)
            + walk("specs/marketing", suffixes=DOC_SUFFIXES))


def code_core():
    """Live backend code snapshot (T-161 / 2026-10-18 pivot: code as a 6th
    Drive-synced md file instead of a static Import Code unit)."""
    files = ["Cargo.toml", "backend/Cargo.toml", "ankitov-budget-gate/Cargo.toml"]
    files += walk("backend/config")
    files += walk("backend/i18n")
    files += walk("backend/resources")
    files += walk("backend/src")
    files += walk("backend/tests")
    files += walk("ankitov-budget-gate/src")
    files += walk("addons/ankitov_session_driver")
    files += walk("AnkiPlayGround/addons21")
    files += [
        "AnkiPlayGround/profiles_update.py",
        "AnkiPlayGround/setup_ankiplayground.py",
        "AnkiPlayGround/setup_stage_decks.py",
    ]
    seen, out = set(), []
    for f in files:
        if f not in seen and (ROOT / f).is_file():
            seen.add(f)
            out.append(f)
    return sorted(out)


OUTPUTS = [
    ("00-overview.md", ["README.md", "CHANGELOG.md", "GLOSSARY.md"]),
    ("01-specs-core.md", spec_core),
    ("02-project-knowledge.md", lambda: walk("project-knowledge", suffixes=DOC_SUFFIXES)),
    ("03-docs.md", docs_all),
    ("04-launch-marketing.md", launch_marketing),
    ("05-code-core.md", code_core),
]


def merge(name, sources):
    parts = [f"# AnkiTov-C merged source: {name}\n",
             f"# Regenerated {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')} "
             f"by merge_docs.py — {len(sources)} files.\n"]
    missing = 0
    for rel in sources:
        p = ROOT / rel
        parts.append(f"\n\n# FILE: {rel}\n\n")
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            text = f"[unreadable: {e}]"
            missing += 1
        parts.append(text)
    if missing:
        print(f"DIFF-WARN {name}: {missing} unreadable files", file=sys.stderr)
    return "".join(parts)


def main():
    manifest_path = HERE / "MANIFEST.json"
    prev = {}
    if manifest_path.exists():
        try:
            prev = json.loads(manifest_path.read_text()).get("outputs", {})
        except Exception:
            prev = {}

    outputs = {}
    for name, src in OUTPUTS:
        files = src() if callable(src) else src
        if not files:
            print(f"DIFF-WARN {name}: EMPTY source list — check repo layout", file=sys.stderr)
        outputs[name] = merge(name, files)

    new_manifest = {"generated_at": datetime.now(timezone.utc).isoformat(), "outputs": {}}
    for name, content in outputs.items():
        (HERE / name).write_text(content, encoding="utf-8")
        sha = hashlib.sha256(content.encode("utf-8")).hexdigest()
        new_manifest["outputs"][name] = {"sha256": sha, "bytes": len(content.encode("utf-8"))}
        old = prev.get(name, {}).get("sha256")
        if old and old != sha:
            print(f"DIFF {name}: {old[:12]} -> {sha[:12]}", file=sys.stderr)
        elif old is None:
            print(f"DIFF {name}: new output (no previous hash)", file=sys.stderr)

    manifest_path.write_text(json.dumps(new_manifest, indent=2) + "\n", encoding="utf-8")
    total = sum(v["bytes"] for v in new_manifest["outputs"].values())
    print(f"merge_docs: 6 outputs, {total} bytes total", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
