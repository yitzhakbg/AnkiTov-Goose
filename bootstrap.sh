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
echo ""

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
# 1. Global Goose config
# ------------------------------------------------------------------
echo ""
echo "─── 1. Global Goose Config ───"
link "$GOOSE_REPO/config/global-config.yaml" \
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
# 8. Headroom deploy script
# ------------------------------------------------------------------
echo ""
echo "─── 8. Headroom Deploy Script ───"
if [ -f "$GOOSE_REPO/scripts/deploy-headroom.sh" ]; then
  link "$GOOSE_REPO/scripts/deploy-headroom.sh" \
       "$HOME/.local/bin/deploy-headroom.sh" \
       "headroom deploy "
  echo "  ℹ️  To install Headroom: bash ~/.local/bin/deploy-headroom.sh"
fi

# ------------------------------------------------------------------
# 9. AnkiTov project config notice
# ------------------------------------------------------------------
echo ""
echo "─── 9. AnkiTov Project Config ───"
echo "  ℹ️  Project config at: $ANKITOV_REPO/goose_config.yaml"
echo "  ℹ️  Goose auto-detects it when cd'd into the AnkiTov directory."

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
echo "    2. cd $ANKITOV_REPO"
echo "    3. goose session -r  (resume last session)"
echo "═══════════════════════════════════════════════════════════"