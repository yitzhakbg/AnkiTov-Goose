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
if [ ! -f "$ANKITOV_REPO/rust-toolchain.toml" ]; then
  echo "❌ $ANKITOV_REPO does not look like an AnkiTov repo (missing rust-toolchain.toml)"
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
# Global config is machine-specific (LLM/model routing differs per host).
# Preserve an existing config — never clobber the laptop's setup.
if [ -e "$CONFIG_HOME/config.yaml" ] || [ -L "$CONFIG_HOME/config.yaml" ]; then
  echo "  ℹ️  $CONFIG_HOME/config.yaml exists — preserving machine-specific LLM/model config"
else
  template_and_link "$GOOSE_REPO/config/global-config.yaml" \
                     "$CONFIG_HOME/config.yaml" \
                     "global config "
fi

# ------------------------------------------------------------------
# 2. Custom providers
# ------------------------------------------------------------------
echo ""
echo "─── 2. Custom Providers ───"
for f in "$GOOSE_REPO/custom_providers"/*.json; do
  [ -f "$f" ] || continue
  dst="$CONFIG_HOME/custom_providers/$(basename "$f")"
  # Provider configs are machine-specific — preserve the host's own.
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    echo "  ℹ️  $dst exists — preserving machine-specific provider config"
    continue
  fi
  link "$f" "$dst"
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
# 8. AnkiTov project recipes → symlinked INTO AnkiTov repo
# ------------------------------------------------------------------
echo ""
echo "─── 8. AnkiTov Project Recipes ───"
# Source: AnkiTov-Goose/recipes/ → Target: $ANKITOV_REPO/recipes/
# Goose auto-discovers project recipes from the project directory,
# and slash commands reference them via recipe_path in goose_config.yaml.
mkdir -p "$ANKITOV_REPO/recipes"
for f in "$GOOSE_REPO/recipes"/*.yaml; do
  [ -f "$f" ] || continue
  link "$f" "$ANKITOV_REPO/recipes/$(basename "$f")" "project recipe "
done
# Subrecipes (if any)
if [ -d "$GOOSE_REPO/recipes/subrecipes" ]; then
  mkdir -p "$ANKITOV_REPO/recipes/subrecipes"
  for f in "$GOOSE_REPO/recipes/subrecipes"/*.yaml; do
    [ -f "$f" ] || continue
    link "$f" "$ANKITOV_REPO/recipes/subrecipes/$(basename "$f")" "subrecipe "
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
# 10. AnkiTov project config (templated → rendered into AnkiTov repo)
# ------------------------------------------------------------------
echo ""
echo "─── 10. AnkiTov Project Config ───"
# Project config is machine-specific (provider/model routing differs per host).
# Preserve an existing config — never clobber the laptop's setup.
if [ -e "$ANKITOV_REPO/goose_config.yaml" ] || [ -L "$ANKITOV_REPO/goose_config.yaml" ]; then
  echo "  ℹ️  $ANKITOV_REPO/goose_config.yaml exists — preserving machine-specific project config"
else
  template_and_link "$GOOSE_REPO/config/project-config.yaml" \
                     "$ANKITOV_REPO/goose_config.yaml" \
                     "project config "
fi

# ------------------------------------------------------------------
# 11. AnkiTov agents (.goose/agents/)
# ------------------------------------------------------------------
echo ""
echo "─── 11. AnkiTov Agents ───"
if [ -d "$GOOSE_REPO/agents" ]; then
  for f in "$GOOSE_REPO/agents"/*.md; do
    [ -f "$f" ] || continue
    link "$f" "$ANKITOV_REPO/.goose/agents/$(basename "$f")" "agent "
  done
else
  echo "  ℹ️  No agents directory — skipping"
fi

# ------------------------------------------------------------------
# 12. AnkiTov skills (.agents/skills/)
# ------------------------------------------------------------------
echo ""
echo "─── 12. AnkiTov Skills ───"
if [ -d "$GOOSE_REPO/skills" ]; then
  # Symlink the entire skills tree (code-review/, etc.)
  for dir in "$GOOSE_REPO/skills"/*/; do
    [ -d "$dir" ] || continue
    skill_name=$(basename "$dir")
    mkdir -p "$ANKITOV_REPO/.agents/skills/$skill_name"
    for f in "$dir"*; do
      [ -f "$f" ] || continue
      link "$f" "$ANKITOV_REPO/.agents/skills/$skill_name/$(basename "$f")" "skill "
    done
  done
else
  echo "  ℹ️  No skills directory — skipping"
fi

# ------------------------------------------------------------------
# 13. AnkiTov hints (.goosehints)
# ------------------------------------------------------------------
echo ""
echo "─── 13. AnkiTov Hints ───"
if [ -f "$GOOSE_REPO/config/goosehints.template" ]; then
  link "$GOOSE_REPO/config/goosehints.template" \
       "$ANKITOV_REPO/.goosehints" \
       "hints "
else
  echo "  ℹ️  No hints template — skipping"
fi

# ------------------------------------------------------------------
# 14. AnkiTov ignore (.gooseignore)
# ------------------------------------------------------------------
echo ""
echo "─── 14. AnkiTov Ignore ───"
if [ -f "$GOOSE_REPO/config/gooseignore.template" ]; then
  link "$GOOSE_REPO/config/gooseignore.template" \
       "$ANKITOV_REPO/.gooseignore" \
       "ignore "
else
  echo "  ℹ️  No ignore template — skipping"
fi

# ------------------------------------------------------------------
# Architecture-specific notes
# ------------------------------------------------------------------
echo ""
echo "─── Architecture Portability Notes ───"

# Detect OS
OS="$(uname -s)"
case "$OS" in
  Darwin)  OS_LABEL="macOS" ;;
  Linux)   OS_LABEL="Linux" ;;
  *)       OS_LABEL="$OS" ;;
esac

if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
  echo "  ✅ $OS_LABEL on ARM64 (Apple Silicon)"
  echo "  ℹ️  If deploying to Intel Linux (Pop!_OS):"
  echo "     1. Install Rust x86_64 target: rustup target add x86_64-unknown-linux-gnu"
  echo "     2. Install Goose: curl -fsSL https://goose.ai/install.sh | bash"
  echo "     3. Rebuild budget gate: cd $ANKITOV_REPO/ankitov-budget-gate && cargo build --release"
elif [ "$ARCH" = "x86_64" ]; then
  echo "  ✅ $OS_LABEL on x86_64 (Intel)"
  echo "  ℹ️  Architecture-specific actions:"
  echo "     - Headroom binary resolved to: $HEADROOM_CMD"
  echo "     - Budget gate may need rebuild: cd $ANKITOV_REPO/ankitov-budget-gate && cargo build --release"
else
  echo "  ℹ️  Unknown architecture: $ARCH"
fi

if [ "$OS" = "Darwin" ]; then
  echo "  ℹ️  Homebrew prefix: $(brew --prefix 2>/dev/null || echo 'not found')"
elif [ "$OS" = "Linux" ]; then
  echo "  ℹ️  Package manager: $(which apt 2>/dev/null && echo 'apt' || which dnf 2>/dev/null && echo 'dnf' || echo 'unknown')"
fi

# ------------------------------------------------------------------
# Verify
# ------------------------------------------------------------------
echo ""
echo "─── Verification ───"
echo ""
echo "  Global config:   $(readlink "$CONFIG_HOME/config.yaml" 2>/dev/null || echo 'NOT LINKED')"
echo "  Project config:  $(readlink "$ANKITOV_REPO/goose_config.yaml" 2>/dev/null || echo 'NOT LINKED')"
echo "  Memory:          $(ls "$CONFIG_HOME/memory/" 2>/dev/null | wc -l | tr -d ' ') files"
echo "  Recipes:         $(ls "$ANKITOV_REPO/recipes/"*.yaml 2>/dev/null | wc -l | tr -d ' ') project | $(ls "$GOOSE_HOME/recipes/"*.yaml 2>/dev/null | wc -l | tr -d ' ') global"
echo "  Scheduled:       $(ls "$GOOSE_HOME/scheduled_recipes/"*.yaml 2>/dev/null | wc -l | tr -d ' ') files"
echo "  Agents:          $(ls "$ANKITOV_REPO/.goose/agents/"*.md 2>/dev/null | wc -l | tr -d ' ') files"
echo "  Skills:          $(find "$ANKITOV_REPO/.agents/skills/" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ') files"
echo "  Hints:           $([ -L "$ANKITOV_REPO/.goosehints" ] && echo 'LINKED' || echo 'NOT LINKED')"
echo "  Ignore:          $([ -L "$ANKITOV_REPO/.gooseignore" ] && echo 'LINKED' || echo 'NOT LINKED')"
echo "  Apps:            $(ls "$GOOSE_HOME/apps/"*.html 2>/dev/null | wc -l | tr -d ' ') files"

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Bootstrap complete!"
echo ""
echo "  What was linked:"
echo "    • Global config       → ~/.config/goose/config.yaml"
echo "    • Project config      → \$ANKITOV_REPO/goose_config.yaml (templated)"
echo "    • Goose hints         → \$ANKITOV_REPO/.goosehints"
echo "    • Goose ignore        → \$ANKITOV_REPO/.gooseignore"
echo "    • Agents (4)          → \$ANKITOV_REPO/.goose/agents/"
echo "    • Skills (1)          → \$ANKITOV_REPO/.agents/skills/"
echo "    • Project recipes (5) → \$ANKITOV_REPO/recipes/"
echo "    • System recipes      → ~/.local/share/goose/recipes/"
echo "    • Scheduled jobs      → ~/.local/share/goose/scheduled_recipes/"
echo ""
echo "  Next steps:"
echo "    1. Set your API keys as environment variables:"
echo "       export OPENROUTER_API_KEY=\"sk-...\""
echo "       export CUSTOM_AGNES_API_KEY=\"...\""
echo "       export GOOSE_MODE=smart_approve"
echo "       export GOOSE_TOOLSHIM=true"
echo "    2. cd $ANKITOV_REPO && cargo check  (verify build)"
echo "    3. goose session  (start working)"
echo ""
echo "  To update after pulling either repo: re-run this script."
echo "  Symlinks auto-resolve — no copy step needed."
echo "═══════════════════════════════════════════════════════════"