#!/usr/bin/env bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.goose.serve.browser.plist"
EXT_DIR="$HOME/.local/share/goose-browser-ext"
SECRET_FILE="$EXT_DIR/.secret"
UID_NUM="$(id -u)"

usage() {
  cat <<USAGE
Usage: goose-browser-bridge <command> [args]

Commands:
  set-origin <ext-id-or-origin>   Set --allowed-origin (accepts bare 32-char ID or chrome-extension://<id>)
  start                           Load/start the LaunchAgent on 127.0.0.1:3285
  stop                            Unload/stop the LaunchAgent
  restart                         Restart the LaunchAgent
  status                          Check launchd job, listening socket :3285, and /status probe
  secret                          Print the shared secret (from $SECRET_FILE)
  test                            Smoke-test /status, /acp auth, and WebSocket initialize + session/list
USAGE
}

cmd="${1:-status}"
shift || true

case "$cmd" in
  set-origin)
    raw="${1:?Provide extension ID or chrome-extension://... origin}"
    if [[ "$raw" != chrome-extension://* ]]; then
      origin="chrome-extension://$raw"
    else
      origin="$raw"
    fi
    /usr/libexec/PlistBuddy -c "Set :ProgramArguments:9 $origin" "$PLIST"
    plutil -lint "$PLIST"
    echo "Updated --allowed-origin to $origin"
    echo "Now run: goose-browser-bridge restart"
    ;;
  start)
    if grep -q "REPLACE_WITH_EXTENSION_ID" "$PLIST"; then
      echo "ERROR: Set your extension ID first: goose-browser-bridge set-origin <EXT_ID>" >&2
      exit 1
    fi
    launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null || launchctl kickstart -k "gui/$UID_NUM/com.goose.serve.browser"
    sleep 1
    lsof -nP -iTCP:3285 -sTCP:LISTEN
    ;;
  stop)
    launchctl bootout "gui/$UID_NUM/com.goose.serve.browser" 2>/dev/null || true
    echo "Stopped com.goose.serve.browser"
    ;;
  restart)
    launchctl bootout "gui/$UID_NUM/com.goose.serve.browser" 2>/dev/null || true
    sleep 0.5
    exec "$0" start
    ;;
  status)
    launchctl print "gui/$UID_NUM/com.goose.serve.browser" 2>/dev/null | grep -E "state =|pid =" || echo "launchd: not loaded"
    lsof -nP -iTCP:3285 -sTCP:LISTEN || echo "port 3285: not listening"
    curl -sS -m 2 http://127.0.0.1:3285/status && echo " (/status ok)" || echo "/status unreachable"
    ;;
  secret)
    cat "$SECRET_FILE"
    ;;
  test)
    python3 - "$SECRET_FILE" "$PLIST" <<'PY'
import json, sys, urllib.request, ssl
secret = open(sys.argv[1]).read().strip()
print("1) /status ->", urllib.request.urlopen("http://127.0.0.1:3285/status", timeout=3).read().decode())
req = urllib.request.Request("http://127.0.0.1:3285/acp", headers={"X-Secret-Key": secret})
try:
    urllib.request.urlopen(req, timeout=3)
except urllib.error.HTTPError as e:
    print("2) /acp auth probe -> HTTP", e.code, "(406/400/426 means auth passed)")
PY
    ;;
  *)
    usage
    exit 2
    ;;
esac
