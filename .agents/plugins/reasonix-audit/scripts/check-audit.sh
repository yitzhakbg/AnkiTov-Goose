#!/usr/bin/env bash
# PostToolUse hook: after goose runs a jj commit touching backend/src,
# remind that a Reasonix audit is available.
set -euo pipefail
payload="$(cat)"
tool_name="$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null || echo '')"
tool_input="$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input","{}"))' 2>/dev/null || echo '{}')"
command_run="$(printf '%s' "$tool_input" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("command",""))' 2>/dev/null || echo '')"

# Only trigger on jj commit commands
if echo "$tool_name" | grep -q 'developer__shell'; then
  if echo "$command_run" | grep -q 'jj commit'; then
    # Check if backend sources changed
    wd="$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("working_dir","."))' 2>/dev/null || echo '.')"
    cd "$wd" 2>/dev/null || cd /Volumes/YBG1TB4Mac/AnkiTov
    if jj diff -r @- --summary 2>/dev/null | grep -q 'backend/src'; then
      echo "reasonix-audit: Backend sources committed. Run /audit-reasonix to verify invariants." >&2
    fi
  fi
fi
exit 0