#!/usr/bin/env bash
# install.sh — one-shot installer for the Goose Browser Bridge (published or unpacked).
#
# Usage:
#   ./install.sh [--ext-id <ID>] [--port <PORT>]
#
# What it does:
#   1. Copies extension/ to ~/.local/share/goose-browser-ext (stable path).
#   2. Generates a fresh 64-hex-char secret (openssl rand -hex 32) if none exists.
#   3. Renders com.goose.serve.browser.plist with that secret + the extension ID.
#   4. Installs the CLI helper to ~/bin/goose-browser-bridge.
#   5. Loads the LaunchAgent (goose serve on 127.0.0.1:3285).
#   6. Prints the secret and next steps.
#
# The extension ID is either passed via --ext-id, or read from the manifest's
# "key" field (published builds), or prompted for (unpacked builds).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXT_DIR="$HOME/.local/share/goose-browser-ext"
BIN_DIR="$HOME/bin"
PLIST_SRC="$SCRIPT_DIR/com.goose.serve.browser.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.goose.serve.browser.plist"
PORT=3285

EXT_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ext-id) EXT_ID="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# 1. Copy extension
mkdir -p "$EXT_DIR"
rsync -a --exclude='.secret' --exclude='.DS_Store' "$SCRIPT_DIR/extension/" "$EXT_DIR/"
echo "[1/5] Extension copied to $EXT_DIR"

# 2. Generate or reuse secret
SECRET_FILE="$EXT_DIR/.secret"
if [[ -f "$SECRET_FILE" ]]; then
  SECRET=$(cat "$SECRET_FILE")
  echo "[2/5] Reusing existing secret from $SECRET_FILE"
else
  SECRET=$(openssl rand -hex 32)
  printf '%s\n' "$SECRET" > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
  echo "[2/5] Generated new secret -> $SECRET_FILE"
fi

# 3. Resolve extension ID
if [[ -z "$EXT_ID" ]]; then
  # Try to derive from manifest "key" (published builds)
  if command -v python3 >/dev/null 2>&1; then
    EXT_ID=$(python3 - "$EXT_DIR/manifest.json" <<'PY'
import json, hashlib, sys, base64
m = json.load(open(sys.argv[1]))
key = m.get("key")
if not key:
    sys.exit(0)
der = base64.b64decode(key)
print(hashlib.sha256(der).hexdigest()[:32].translate(str.maketrans("0123456789abcdef", "abcdefghijklmnop")))
PY
)
  fi
fi
if [[ -z "$EXT_ID" ]]; then
  read -r -p "Enter your 32-char Extension ID (from brave://extensions after Load unpacked): " EXT_ID
fi
[[ "$EXT_ID" =~ ^[a-p]{32}$ ]] || { echo "ERROR: '$EXT_ID' is not a valid 32-char a-p extension ID" >&2; exit 1; }
echo "[3/5] Extension ID: $EXT_ID"

# 4. Render + install plist
mkdir -p "$(dirname "$PLIST_DST")"
sed "s|REPLACE_WITH_HEX_SECRET|$SECRET|g; s|REPLACE_WITH_EXTENSION_ID|chrome-extension://$EXT_ID|g; s|3285|$PORT|g" \
  "$PLIST_SRC" > "$PLIST_DST"
chmod 600 "$PLIST_DST"
plutil -lint "$PLIST_DST" >/dev/null
echo "[4/5] LaunchAgent installed at $PLIST_DST (port $PORT)"

# 5. Install CLI helper + load agent
mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/goose-browser-bridge.sh" "$BIN_DIR/goose-browser-bridge"
chmod +x "$BIN_DIR/goose-browser-bridge"
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" 2>/dev/null || launchctl kickstart -k "gui/$(id -u)/com.goose.serve.browser"
sleep 1
echo "[5/5] LaunchAgent loaded"

echo
echo "=== Done ==="
echo "Shared secret (paste into the Side Panel's Connection settings):"
echo "  $SECRET"
echo
echo "Next steps:"
echo "  1. Load the extension unpacked from $EXT_DIR (if not already published/installed)."
echo "  2. Click the Goose Bridge toolbar icon -> Connection -> paste the secret + your default cwd -> Save & Connect."
echo "  3. Verify: $BIN_DIR/goose-browser-bridge status && $BIN_DIR/goose-browser-bridge test"
