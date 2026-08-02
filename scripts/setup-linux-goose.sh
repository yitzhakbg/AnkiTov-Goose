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

# ── 5. Node.js + npm (required for code-graph-mcp) ─────
echo ""
echo "-- Step 5/10: Node.js + npm --"
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
  log "Node.js $(node --version) installed"
else
  log "Node.js already installed: $(node --version)"
fi

# ── 6. xvfb (virtual framebuffer for Goose terminal UI) ──
echo ""
echo "-- Step 6/14: xvfb (virtual framebuffer) --"
if ! command -v xvfb-run &>/dev/null; then
  sudo apt-get update -qq && sudo apt-get install -y -qq xvfb
  log "xvfb installed"
else
  log "xvfb already installed"
fi

# ── 7. TaskLite ────────────────────────────────────────
echo ""
echo "-- Step 6/13: TaskLite --"
if ! command -v tasklite &>/dev/null; then
  cargo install todo-sqlite-cli
  log "TaskLite installed"
else
  log "TaskLite already installed: $(tasklite --version)"
fi

# ── 7. code-graph-mcp (tree-sitter MCP server) ─────────
echo ""
echo "-- Step 8/15: code-graph-mcp --"
if ! command -v code-graph-mcp &>/dev/null; then
  # Avoid EACCES on global installs by using user-local prefix
  mkdir -p "${HOME}/.local"
  npm config set prefix "${HOME}/.local" 2>/dev/null || true
  export PATH="${HOME}/.local/bin:${PATH}"
  npm install -g code-graph-mcp
  log "code-graph-mcp installed"
else
  log "code-graph-mcp already installed"
fi

# ── 8. Headroom (compression proxy, via mise Python) ───
echo ""
echo "-- Step 9/15: Headroom --"
if ! command -v headroom &>/dev/null; then
  # Activate mise shims so python/pip are on PATH
  eval "$(mise activate bash)" 2>/dev/null || true
  mise use python@3.12
  ~/.local/share/mise/shims/pip install headroom || mise exec python -- -m pip install headroom
  log "Headroom installed"
else
  log "Headroom already installed"
fi

# ── 9. Mutagen (file sync engine) ──────────────────────
echo ""
echo "-- Step 10/15: Mutagen --"
if ! command -v mutagen &>/dev/null; then
  MUTAGEN_VER="0.18.1"
  curl -fsSL "https://github.com/mutagen-io/mutagen/releases/download/v${MUTAGEN_VER}/mutagen_linux_amd64_v${MUTAGEN_VER}.tar.gz" | tar xz -C "${HOME}/.local/bin"
  log "Mutagen ${MUTAGEN_VER} installed"
else
  log "Mutagen already installed: $(mutagen version)"
fi

# ── 10. Clone AnkiTov repo ──────────────────────────────
echo ""
echo "-- Step 11/15: Clone AnkiTov --"
ANKITOV_PATH="${HOME}/AnkiTov"
if [ ! -d "$ANKITOV_PATH" ]; then
  jj git clone https://github.com/yitzhakbg/AnkiTov.git "$ANKITOV_PATH"
  log "AnkiTov cloned to $ANKITOV_PATH"
else
  warn "AnkiTov already exists at $ANKITOV_PATH -- skipping"
  warn "Run: cd $ANKITOV_PATH && jj git fetch"
fi

# ── 11. Clone AnkiTov-Goose repo ───────────────────────
echo ""
echo "-- Step 12/15: Clone AnkiTov-Goose --"
GOOSE_PATH="${HOME}/AnkiTov-goose"
if [ ! -d "$GOOSE_PATH" ]; then
  git clone https://github.com/yitzhakbg/AnkiTov-Goose.git "$GOOSE_PATH"
  log "AnkiTov-Goose cloned to $GOOSE_PATH"
else
  warn "AnkiTov-Goose already exists at $GOOSE_PATH -- skipping"
  warn "Run: cd $GOOSE_PATH && git pull"
fi

# ── 12. Run bootstrap.sh (symlinks + config rendering) ──
echo ""
echo "-- Step 13/15: Bootstrap Goose symlinks --"
if [ -f "$GOOSE_PATH/bootstrap.sh" ]; then
  bash "$GOOSE_PATH/bootstrap.sh" "$ANKITOV_PATH"
  log "Goose environment linked — agents, skills, recipes, hints, configs"
else
  warn "bootstrap.sh not found in $GOOSE_PATH — skipping"
  warn "Run manually: bash ~/AnkiTov-goose/bootstrap.sh ~/AnkiTov"
fi

# ── 13. Compile budget gate ────────────────────────────
echo ""
echo "-- Step 14/15: Compile budget gate (x86_64) --"
cd "$ANKITOV_PATH/ankitov-budget-gate"
cargo build --release
log "Budget gate compiled for x86_64-unknown-linux-gnu"

echo ""
echo "================================================="
echo "  Bootstrap complete!"
echo ""
echo "  What was set up:"
echo "    • Toolchain: Goose, jj, Rust, mise, tasklite,"
echo "      code-graph-mcp, headroom, mutagen"
echo "    • Repos:    ~/AnkiTov (product) + ~/AnkiTov-goose (Goose config)"
echo "    • Symlinks: agents, skills, recipes, hints, ignore, configs"
echo "      all point → ~/AnkiTov-goose/"
echo ""
echo "  Next steps:"
echo "    cd ~/AnkiTov && goose session"
echo ""
echo "  Ongoing sync (either machine):"
echo "    cd ~/AnkiTov-goose && git pull   # symlinks auto-resolve"
echo "    cd ~/AnkiTov && jj git fetch      # backend updates"
echo "================================================="