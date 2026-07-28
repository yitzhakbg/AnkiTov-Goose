#!/usr/bin/env bash
# =============================================================================
# AnkiTov Goose Environment Bootstrap
# =============================================================================
# Symlinks all Goose-related files into place for a new machine.
# Usage: ./bootstrap.sh /path/to/ankitov-repo
# =============================================================================
set -euo pipefail

GOOSE_REPO="$(cd "$(dirname "$0")" && pwd)"
ANKITOV_REPO="${1:-}"

if [ -z "$ANKITOV_REPO" ]; then
  echo "Usage: $0 /path/to/ankitov-repo"
  echo ""
  echo "Example:"
  echo "  git clone https://github.com/ankitov/ankitov.git ~/ankitov"
  echo "  $0 ~/ankitov"
  exit 1
fi

ANKITOV_REPO="$(cd "$ANKITOV_REPO" && pwd)"

echo "═══════════════════════════════════════════════════════════"
echo "  AnkiTov Goose Environment Bootstrap"
echo "═══════════════════════════════════════════════════════════"
echo "  Goose repo:   $GOOSE_REPO"
echo "  AnkiTov repo:  $ANKITOV_REPO"
echo "  Home:         $HOME"
echo "  Architecture: $(uname -m)"
echo ""

# ------------------------------------------------------------------
# Detect architecture
# ------------------------------------------------------------------
ARCH="$(uname -m)"
case "$ARCH" in
    arm64|aarch64)  ARCH_LABEL="ARM64 (Apple Silicon)" ;;
    x86_64)         ARCH_LABEL="x86_64 (Intel)" ;;
    *)              ARCH_LABEL="$ARCH" ;;
esac
echo "  ℹ️  Detected architecture: $ARCH_LABEL"

# ------------------------------------------------------------------
# Validate AnkiTov repo
# ------------------------------------------------------------------
if [ ! -f "$ANKITOV_REPO/goose_config.yaml" ]; then
  echo "❌ $ANKITOV_REPO does not look like an AnkiTov repo (missing goose_config.yaml)"
  exit 1
fi

GOOSE_HOME="$HOME/.local/share/goose"
CONFIG_HOME="$HOME/.config/goose"

# ------------------------------------------------------------------
# Resolve headroom binary path
# ------------------------------------------------------------------
resolve_headroom_cmd() {
  # Try mise-managed headroom first (most common for this project)
  local mise_headroom
  mise_headroom=$(mise which headroom 2>/dev/null || true)
  if [ -n "$mise_headroom" ] && [ -x "$mise_headroom" ]; then
    echo "$mise_headroom"
    return
  fi

  # Try PATH
  local path_headroom
  path_headroom=$(which headroom 2>/dev/null || true)
  if [ -n "$path_headroom" ] && [ -x "$path_headroom" ]; then
    echo "$path_headroom"
    return
  fi

  # Try common pip install locations
  for candidate in \
    "$HOME/.local/bin/headroom" \
    "$HOME/.local/share/mise/installs/python/3.12/bin/headroom" \
    "$HOME/.local/share/mise/installs/python/3/bin/headroom" \
    "/usr/local/bin/headroom" \
    "/opt/homebrew/bin/headroom"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done

  # Fallback: just use "headroom" from PATH (will fail gracefully if not installed)
  echo "headroom"
}

HEADROOM_CMD=$(resolve_headroom_cmd)
echo "  ℹ️  Headroom binary: $HEADROOM_CMD"

# ------------------------------------------------------------------
# Resolve goose-sh path
# ------------------------------------------------------------------
resolve_goose_shell() {
  local goose_sh
  goose_sh=$(which goose-sh 2>/dev/null || true)
  if [ -n "$goose_sh" ] && [ -x "$goose_sh" ]; then
    echo "$goose_sh"
    return
  fi
  # Common locations
  for candidate in \
    "$HOME/.local/bin/goose-sh" \
    "/usr/local/bin/goose-sh" \
    "/opt/homebrew/bin/goose-sh"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done
  # Fallback — goose-sh is created by goose install
  echo "$HOME/.local/bin/goose-sh"
}

GOOSE_SHELL_CMD=$(resolve_goose_shell)
echo "  ℹ️  Goose shell: $GOOSE_SHELL_CMD"

# ------------------------------------------------------------------
# Helper: backup existing, then symlink
# ------------------------------------------------------------------
link() {
  local src="$1"
  local dst="$2"
  local label="${3:-}"

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    local backup="${dst}.bak.$(date +%s)"
    echo "  ⚠️  $dst exists → backing up to $backup"
    mv "$dst" "$backup"
  fi

  mkdir -p "$(dirname "$dst")"
  ln -sf "$src" "$dst"
  echo "  ✅ ${label}linked: $dst → $src"
}

# ------------------------------------------------------------------
# Helper: template-substitute a file, then link
# ------------------------------------------------------------------
template_and_link() {
  local src="$1"
  local dst="$2"
  local label="${3:-}"

  local tmpfile
  tmpfile=$(mktemp /tmp/ankitov-template-XXXXXX)

  sed -e "s|{{ANKITOV_REPO}}|$ANKITOV_REPO|g" \
      -e "s|{{HEADROOM_CMD}}|$HEADROOM_CMD|g" \
      -e "s|{{GOOSE_SHELL_CMD}}|$GOOSE_SHELL_CMD|g" \
      -e "s|{{GOOSE_HOME}}|$GOOSE_HOME|g" \
      "$src" > "$tmpfile"

  link "$tmpfile" "$dst" "$label"
}

# ------------------------------------------------------------------
# 1. Global Goose config (with path templating)
# ------------------------------------------------------------------
echo ""
echo "─── 1. Global Goose Config ───"
template_and_link "$GOOSE_REPO/config/global-config.yaml" \
                   "$CONFIG_HOME/config.yaml" \
                   "global config "

# ------------------------------------------------------------------
# 2. Custom providers
# ------------------------------------------------------------------
echo ""
echo "─── 2. Custom Providers ───"
for f in "$GOOSE_REPO/custom_providers"/*.json; do
  [ -f "$f" ] || continue
  link "$f" "$CONFIG_HOME/custom_providers/$(basename "$f")"
done

# ------------------------------------------------------------------
# 3. Global memory
# ------------------------------------------------------------------
echo ""
echo "─── 3. Global Memory ───"
for f in "$GOOSE_REPO/memory/global"/*.txt; do
  [ -f "$f" ] || continue
  link "$f" "$CONFIG_HOME/memory/$(basename "$f")"
done

# ------------------------------------------------------------------
# 4. System-level recipes (non-AnkiTov)
# ------------------------------------------------------------------
echo ""
echo "─── 4. System Recipes ───"
for f in "$GOOSE_REPO/recipes"/*.yaml; do
  [ -f "$f" ] || continue
  link "$f" "$GOOSE_HOME/recipes/$(basename "$f")"
done

# ------------------------------------------------------------------
# 5. Scheduled recipes
# ------------------------------------------------------------------
echo ""
echo "─── 5. Scheduled Recipes ───"
for f in "$GOOSE_REPO/scheduled_recipes"/*.yaml; do
  [ -f "$f" ] || continue
  link "$f" "$GOOSE_HOME/scheduled_recipes/$(basename "$f")"
done

# ------------------------------------------------------------------
# 6. Schedule & projects registry (templated → real paths)
# ------------------------------------------------------------------
echo ""
echo "─── 6. Schedule & Projects ───"

# Generate schedule.json with real paths
echo "  🔧 Substituting paths in schedule.json..."
sed -e "s|{{GOOSE_HOME}}|$GOOSE_HOME|g" \
    -e "s|{{ANKITOV_REPO}}|$ANKITOV_REPO|g" \
    "$GOOSE_REPO/schedule.json" > /tmp/ankitov-schedule.json
link "/tmp/ankitov-schedule.json" \
     "$GOOSE_HOME/schedule.json"

# Generate projects.json with real paths
echo "  🔧 Substituting paths in projects.json..."
sed -e "s|{{ANKITOV_REPO}}|$ANKITOV_REPO|g" \
    "$GOOSE_REPO/projects.json" > /tmp/ankitov-projects.json
link "/tmp/ankitov-projects.json" \
     "$GOOSE_HOME/projects.json"

# ------------------------------------------------------------------
# 7. Goose apps
# ------------------------------------------------------------------
echo ""
echo "─── 7. Goose Apps ───"
for f in "$GOOSE_REPO/apps"/*.html; do
  [ -f "$f" ] || continue
  link "$f" "$GOOSE_HOME/apps/$(basename "$f")"
done

# ------------------------------------------------------------------
# 8. AnkiTov project-level recipes (slash commands + subrecipes)
# ------------------------------------------------------------------
echo ""
echo "─── 8. AnkiTov Project Recipes ───"

# Slash command recipes (ankitov-research, ankitov-design, ankitov-plan)
ANKITOV_RECIPES_DIR="$ANKITOV_REPO/recipes"
if [ -d "$ANKITOV_RECIPES_DIR" ]; then
  for f in "$ANKITOV_RECIPES_DIR"/*.yaml; do
    [ -f "$f" ] || continue
    link "$f" "$GOOSE_HOME/recipes/$(basename "$f")"
  done
  # Subrecipes (ankitov-analyzer, ankitov-locator, ankitov-pattern-finder)
  if [ -d "$ANKITOV_RECIPES_DIR/subrecipes" ]; then
    mkdir -p "$GOOSE_HOME/recipes/subrecipes"
    for f in "$ANKITOV_RECIPES_DIR/subrecipes"/*.yaml; do
      [ -f "$f" ] || continue
      link "$f" "$GOOSE_HOME/recipes/subrecipes/$(basename "$f")"
    done
  fi
fi

# Summon subagents (ankitov-spec-generator, entroly-review, update-playground-profiles)
ANKITOV_GOOSE_RECIPES="$ANKITOV_REPO/.goose/recipes"
if [ -d "$ANKITOV_GOOSE_RECIPES" ]; then
  for f in "$ANKITOV_GOOSE_RECIPES"/*.yaml; do
    [ -f "$f" ] || continue
    link "$f" "$GOOSE_HOME/recipes/$(basename "$f")"
  done
fi

# ------------------------------------------------------------------
# 9. Headroom deploy script
# ------------------------------------------------------------------
echo ""
echo "─── 9. Headroom Deploy Script ───"
if [ -f "$GOOSE_REPO/scripts/deploy-headroom.sh" ]; then
  link "$GOOSE_REPO/scripts/deploy-headroom.sh" \
       "$HOME/.local/bin/deploy-headroom.sh" \
       "headroom deploy "
  echo "  ℹ️  To install Headroom: bash ~/.local/bin/deploy-headroom.sh"
fi

# ------------------------------------------------------------------
# 10. AnkiTov project config notice
# ------------------------------------------------------------------
echo ""
echo "─── 10. AnkiTov Project Config ───"
echo "  ℹ️  Project config at: $ANKITOV_REPO/goose_config.yaml"
echo "  ℹ️  Goose auto-detects it when cd'd into the AnkiTov directory."

# ------------------------------------------------------------------
# Architecture-specific notes
# ------------------------------------------------------------------
echo ""
echo "─── Architecture Portability Notes ───"
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
  echo "  ✅ Running on ARM64 (Apple Silicon)"
  echo "  ℹ️  If you need to run on Intel (x86_64) later:"
  echo "     1. Install Rust x86_64 target: rustup target add x86_64-apple-darwin"
  echo "     2. Install Intel Goose: brew install goose  (homebrew auto-detects arch)"
  echo "     3. Rebuild budget gate: cd $ANKITOV_REPO/ankitov-budget-gate && cargo build --release"
  echo "     4. Download Intel Anki from https://apps.ankiweb.net"
else
  echo "  ✅ Running on x86_64 (Intel)"
  echo "  ℹ️  Architecture-specific actions taken:"
  echo "     - Headroom binary resolved to: $HEADROOM_CMD"
  echo "     - Budget gate may need rebuild: cd $ANKITOV_REPO/ankitov-budget-gate && cargo build --release"
fi
echo "  ℹ️  Homebrew prefix: $(brew --prefix 2>/dev/null || echo 'not found')"

# ------------------------------------------------------------------
# Verify
# ------------------------------------------------------------------
echo ""
echo "─── Verification ───"
echo ""
echo "  Config: $(readlink "$CONFIG_HOME/config.yaml" 2>/dev/null || echo 'NOT LINKED')"
echo "  Memory: $(ls "$CONFIG_HOME/memory/" 2>/dev/null | wc -l | tr -d ' ') files"
echo "  Recipes: $(ls "$GOOSE_HOME/recipes/"*.yaml 2>/dev/null | wc -l | tr -d ' ') files"
echo "  Scheduled: $(ls "$GOOSE_HOME/scheduled_recipes/"*.yaml 2>/dev/null | wc -l | tr -d ' ') files"
echo "  Apps: $(ls "$GOOSE_HOME/apps/"*.html 2>/dev/null | wc -l | tr -d ' ') files"
echo "  AnkiTov config: $(readlink -f "$ANKITOV_REPO/goose_config.yaml" 2>/dev/null || echo 'present')"

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Bootstrap complete!"
echo ""
echo "  Next steps:"
echo "    1. Set your API keys as environment variables:"
echo "       export OPENROUTER_API_KEY=\"sk-...\""
echo "       export CUSTOM_AGNES_API_KEY=\"...\""
echo "       export GOOSE_MODE=smart_approve"
echo "       export GOOSE_TOOLSHIM=true"
echo "    2. See ARCHITECTURE.md for cross-platform portability notes"
echo "    3. cd $ANKITOV_REPO"
echo "    4. goose session -r  (resume last session)"
echo "═══════════════════════════════════════════════════════════"