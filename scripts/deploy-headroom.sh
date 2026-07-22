#!/usr/bin/env bash
# =============================================================================
# AnkiTov + Headroom Deploy Script
# =============================================================================
# Installs/configures Headroom proxy for OpenRouter cost optimization.
# Compatible with macOS (Apple Silicon & Intel) and Linux (x86_64 & aarch64).
#
# Usage:
#   bash deploy-headroom.sh                    # interactive install
#   bash deploy-headroom.sh --uninstall        # remove Headroom
#
# The proxy runs on port 8787 with:
#   - --mode cache          Freeze prior turns for provider prefix caching
#   - --backend openrouter  Explicit OpenRouter routing (not auto-detected)
#   - --code-aware          AST-based code compression
#   - --memory              Persistent memory for cross-session context
#   - --port 8787           Default proxy port
#
# Environment variables required at runtime:
#   OPENROUTER_API_KEY      Your OpenRouter API key
# =============================================================================
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
HEADROOM_VERSION="0.32.1"
HEADROOM_PORT="${HEADROOM_PORT:-8787}"
HEADROOM_HOST="${HEADROOM_HOST:-127.0.0.1}"
HEADROOM_MODE="${HEADROOM_MODE:-cache}"
HEADROOM_BACKEND="${HEADROOM_BACKEND:-openrouter}"

# ── Detect OS ───────────────────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
    Darwin)  OS_NAME="macOS"   ;;
    Linux)   OS_NAME="Linux"   ;;
    *)       echo "❌ Unsupported OS: $OS"; exit 1 ;;
esac

# ── Uninstall ───────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
    echo "━━━ Uninstalling Headroom ━━━"

    # Kill proxy if running
    PROXY_PID=$(lsof -ti :$HEADROOM_PORT 2>/dev/null || true)
    if [[ -n "$PROXY_PID" ]]; then
        kill "$PROXY_PID" 2>/dev/null && echo "  ✅ Proxy stopped (PID $PROXY_PID)" || true
    fi

    # Remove files
    rm -f "$HOME/.local/bin/headroom-proxy-start.sh"
    rm -rf "$HOME/.config/headroom"
    rm -rf "$HOME/.headroom"

    echo "  ✅ Headroom files removed"
    echo "  ℹ️  To remove the Headroom MCP extension from Goose, edit ~/.config/goose/config.yaml"
    echo "     and remove the headroom-mcp entry from extensions."
    echo "  ℹ️  To remove the pip package: pip3 uninstall headroom-ai"
    exit 0
fi

# ── Install ─────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Headroom Proxy — Deploy ($OS_NAME $ARCH)                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ──────────────────────────────────────────────────────────────
# 1. Install Python + Headroom via pip
# ──────────────────────────────────────────────────────────────
echo "━━━ [1/4] Install Headroom Package ━━━"

if command -v headroom &>/dev/null; then
    INSTALLED_VER=$(headroom --version 2>/dev/null | head -1 || echo "?")
    echo "  ✅ headroom already installed ($INSTALLED_VER)"
else
    echo "  Installing headroom-ai via pip..."
    if [[ "$OS_NAME" == "macOS" ]]; then
        # macOS: ensure Python 3 is available
        if ! command -v python3 &>/dev/null; then
            echo "  Installing Python 3 via Homebrew..."
            brew install python
        fi
    elif [[ "$OS_NAME" == "Linux" ]]; then
        if ! command -v python3 &>/dev/null; then
            if command -v apt &>/dev/null; then
                sudo apt update -qq && sudo apt install -y -qq python3 python3-pip
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y -q python3 python3-pip
            fi
        fi
    fi
    pip3 install headroom-ai[code] 2>&1 | tail -3
    echo "  ✅ headroom installed ($(headroom --version 2>/dev/null | head -1))"
fi

# ──────────────────────────────────────────────────────────────
# 2. Create Headroom config
# ──────────────────────────────────────────────────────────────
echo ""
echo "━━━ [2/4] Create Headroom Config ━━━"

mkdir -p "$HOME/.config/headroom"

if [[ -f "$HOME/.config/headroom/headroom.json" ]]; then
    echo "  ✅ Config already exists at ~/.config/headroom/headroom.json"
else
    cat > "$HOME/.config/headroom/headroom.json" << 'CONFEOF'
{
  "server": {
    "port": 8740,
    "host": "127.0.0.1",
    "debug": false
  },
  "compression": {
    "algorithm": "smart_crusher",
    "aggressive_mode": true,
    "threshold_tokens": 1024
  },
  "upstream": {
    "provider": "openai",
    "base_url": "https://openrouter.ai/api/v1",
    "default_model": "deepseek/deepseek-v4-pro"
  }
}
CONFEOF
    echo "  ✅ Created ~/.config/headroom/headroom.json"
fi

# ──────────────────────────────────────────────────────────────
# 3. Create proxy launch script
# ──────────────────────────────────────────────────────────────
echo ""
echo "━━━ [3/4] Create Proxy Launch Script ━━━"

mkdir -p "$HOME/.local/bin"

LAUNCH_SCRIPT="$HOME/.local/bin/headroom-proxy-start.sh"

if [[ -f "$LAUNCH_SCRIPT" ]]; then
    echo "  ✅ Launch script already exists at $LAUNCH_SCRIPT"
else
    cat > "$LAUNCH_SCRIPT" << SCRIPTEOF
#!/bin/bash
# Headroom proxy launcher — started by deploy-headroom.sh
# Retrieves API key from environment and starts the proxy.

export OPENAI_TARGET_API_URL="https://openrouter.ai/api/v1"
export HEADROOM_OUTPUT_SHAPER=1

# Set your API key before running:
#   export OPENROUTER_API_KEY="sk-or-v1-..."
#   export OPENAI_API_KEY="\$OPENROUTER_API_KEY"

exec headroom proxy \\
    --code-aware \\
    --port ${HEADROOM_PORT} \\
    --memory \\
    --mode ${HEADROOM_MODE} \\
    --backend ${HEADROOM_BACKEND}
SCRIPTEOF
    chmod +x "$LAUNCH_SCRIPT"
    echo "  ✅ Created $LAUNCH_SCRIPT"
fi

# ──────────────────────────────────────────────────────────────
# 4. macOS: Create launchd plist for auto-start
# ──────────────────────────────────────────────────────────────
echo ""
echo "━━━ [4/4] Auto-Start (optional) ━━━"

if [[ "$OS_NAME" == "macOS" ]]; then
    PLIST_PATH="$HOME/Library/LaunchAgents/com.headroom.proxy.plist"
    if [[ -f "$PLIST_PATH" ]]; then
        echo "  ✅ launchd plist already exists at $PLIST_PATH"
    else
        echo "  Creating launchd plist for auto-start on login..."
        mkdir -p "$HOME/Library/LaunchAgents"
        cat > "$PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.headroom.proxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>source $HOME/.local/bin/headroom-proxy-start.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/headroom-proxy.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/headroom-proxy.err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OPENAI_TARGET_API_URL</key>
        <string>https://openrouter.ai/api/v1</string>
        <key>HEADROOM_OUTPUT_SHAPER</key>
        <string>1</string>
    </dict>
</dict>
</plist>
PLISTEOF
        echo "  ℹ️  To enable auto-start:"
        echo "     launchctl load $PLIST_PATH"
        echo "     (Set OPENROUTER_API_KEY in your shell profile first)"
    fi
elif [[ "$OS_NAME" == "Linux" ]]; then
    # systemd user service
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"
    SERVICE_PATH="$SYSTEMD_DIR/headroom-proxy.service"
    if [[ -f "$SERVICE_PATH" ]]; then
        echo "  ✅ systemd service already exists"
    else
        cat > "$SERVICE_PATH" << SERVICEEOF
[Unit]
Description=Headroom Proxy for OpenRouter
After=network.target

[Service]
Type=simple
ExecStart=%h/.local/bin/headroom-proxy-start.sh
Restart=on-failure
RestartSec=5
Environment=OPENAI_TARGET_API_URL=https://openrouter.ai/api/v1
Environment=HEADROOM_OUTPUT_SHAPER=1

[Install]
WantedBy=default.target
SERVICEEOF
        echo "  ℹ️  To enable auto-start:"
        echo "     systemctl --user daemon-reload"
        echo "     systemctl --user enable --now headroom-proxy"
        echo "     (Set OPENROUTER_API_KEY in your shell profile first)"
    fi
fi

# ──────────────────────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅ Headroom Deploy Complete                                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  To start the proxy:"
echo "    export OPENROUTER_API_KEY=\"sk-or-v1-...\""
echo "    export OPENAI_API_KEY=\"\$OPENROUTER_API_KEY\""
echo "    bash $HOME/.local/bin/headroom-proxy-start.sh"
echo ""
echo "  Verify: curl http://$HEADROOM_HOST:$HEADROOM_PORT/health"
echo ""
echo "  Goose integration:"
echo "    The global Goose config already includes the headroom-mcp extension."
echo "    Just restart Goose and it will connect via the proxy."
echo "    OPENAI_BASE_URL=http://$HEADROOM_HOST:$HEADROOM_PORT/v1"
echo ""