#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────
# AnkiTov Linux Laptop Bootstrap (ybgxps — Pop!_OS, Intel)
# Run once after powering up the laptop.
# ──────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

echo "================================================="
echo "  AnkiTov Linux Laptop Bootstrap"
echo "  Target: ybgxps (Pop!_OS, Intel i7-4790)"
echo "================================================="

# ── 1. Goose 1.38.0 ────────────────────────────────────
echo ""
echo "-- Step 1/9: Goose CLI --"
if ! command -v goose &>/dev/null; then
  curl -fsSL https://goose.ai/install.sh | bash
  log "Goose installed"
else
  log "Goose already installed: $(goose --version)"
fi

# ── 2. Jujutsu 0.43.0 ──────────────────────────────────
echo ""
echo "-- Step 2/9: Jujutsu (jj) --"
if ! command -v jj &>/dev/null; then
  JJ_VERSION="0.43.0"
  JJ_TARBALL="jj-v${JJ_VERSION}-x86_64-unknown-linux-musl.tar.gz"
  mkdir -p "${HOME}/.local/bin"
  curl -fsSL "https://github.com/jj-vcs/jj/releases/download/v${JJ_VERSION}/${JJ_TARBALL}" | tar xz -C "${HOME}/.local/bin"
  export PATH="${HOME}/.local/bin:${PATH}"
  log "jj ${JJ_VERSION} installed"
else
  log "jj already installed: $(jj --version)"
fi

# ── 3. Rust (stable, x86_64-unknown-linux-gnu) ────────
echo ""
echo "-- Step 3/9: Rust toolchain --"
if ! command -v rustup &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain stable -y
  source "${HOME}/.cargo/env"
  log "Rust installed"
else
  log "Rust already installed: $(rustc --version)"
fi

# ── 4. Mise (for headroom Python) ──────────────────────
echo ""
echo "-- Step 4/9: Mise --"
if ! command -v mise &>/dev/null; then
  curl https://mise.run | sh
  export PATH="${HOME}/.local/bin:${PATH}"
  log "Mise installed"
else
  log "Mise already installed: $(mise --version)"
fi

# ── 5. TaskLite ────────────────────────────────────────
echo ""
echo "-- Step 5/9: TaskLite --"
if ! command -v tasklite &>/dev/null; then
  cargo install tasklite
  log "TaskLite installed"
else
  log "TaskLite already installed: $(tasklite --version)"
fi

# ── 6. code-graph-mcp (tree-sitter MCP server) ─────────
echo ""
echo "-- Step 6/9: code-graph-mcp --"
if ! command -v code-graph-mcp &>/dev/null; then
  npm install -g code-graph-mcp
  log "code-graph-mcp installed"
else
  log "code-graph-mcp already installed"
fi

# ── 7. Headroom (compression proxy, via mise Python) ───
echo ""
echo "-- Step 7/9: Headroom --"
if ! command -v headroom &>/dev/null; then
  mise use python@3.12
  pip install headroom
  log "Headroom installed"
else
  log "Headroom already installed"
fi

# ── 8. Mutagen (file sync engine) ──────────────────────
echo ""
echo "-- Step 8/9: Mutagen --"
if ! command -v mutagen &>/dev/null; then
  curl -fsSL https://mutagen.io/install.sh | bash
  log "Mutagen installed"
else
  log "Mutagen already installed: $(mutagen version)"
fi

# ── 9. Clone AnkiTov repo ──────────────────────────────
echo ""
echo "-- Step 9/9: Clone AnkiTov --"
REPO_PATH="${HOME}/AnkiTov"
if [ ! -d "$REPO_PATH" ]; then
  jj git clone https://github.com/yitzhakbg/AnkiTov.git "$REPO_PATH"
  log "Repo cloned to $REPO_PATH"
else
  warn "Repo already exists at $REPO_PATH -- skipping clone"
  warn "Run: cd $REPO_PATH && jj git fetch"
fi

# ── Path Patching ──────────────────────────────────────
echo ""
echo "-- Patching config paths for Linux --"
CONFIG="$REPO_PATH/goose_config.yaml"
if [ -f "$CONFIG" ]; then
  sed -i 's|/Volumes/YBG1TB4Mac/AnkiTov|'${HOME}'/AnkiTov|g' "$CONFIG"
  sed -i 's|/Users/ybg/|'${HOME}'/|g' "$CONFIG"
  log "Config paths patched"
fi

# ── Compile budget gate ────────────────────────────────
echo ""
echo "-- Compiling budget gate (x86_64) --"
cd "$REPO_PATH/ankitov-budget-gate"
cargo build --release
log "Budget gate compiled for x86_64-unknown-linux-gnu"

echo ""
echo "================================================="
echo "  Bootstrap complete!"
echo ""
echo "  Next steps on the laptop:"
echo "  1. cd ~/AnkiTov"
echo "  2. cargo check   (verify backend compiles)"
echo "  3. goose session (test Goose connectivity)"
echo ""
echo "  Then come back to Mac Mini for Mutagen sync."
echo "================================================="
