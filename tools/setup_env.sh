#!/bin/bash
# Prepares a fresh session (cloud container or CI) for working on the game. Idempotent, safe to re-run.
#   1. Godot 4.5.1 (headless editor binary)          -> /opt/godot/godot or ~/.local/bin/godot
#   2. Windows export templates (only ~97 MB)        -> ~/.local/share/godot/export_templates/4.5.1.stable
#   3. xvfb + Mesa Vulkan for screenshots (apt, if available)
#   4. private assets from the PC (if staged)        -> game/assets/consim, game/assets/barriers
#   5. git identity for agent commits (repo-local), pre-commit hook (lint)
#   6. Godot import (class cache, imported models)
# usage: tools/setup_env.sh [--ci] [--no-templates] [--no-apt] [--assets=<assets.tar>]
#   --ci  only Godot + import (GitHub Actions)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER=4.5.1
CI=0; TEMPLATES=1; APT=1; ASSETS=""
for a in "$@"; do
  case "$a" in
    --ci) CI=1; TEMPLATES=0; APT=0 ;;
    --no-templates) TEMPLATES=0 ;;
    --no-apt) APT=0 ;;
    --assets=*) ASSETS="${a#--assets=}" ;;
  esac
done
say() { echo "== $*"; }

# --- 1. Godot ---------------------------------------------------------------------------------
G="${GODOT:-}"
if [ -z "$G" ]; then
  for c in /opt/godot/godot "$HOME/.local/bin/godot" "$(command -v godot 2>/dev/null || true)"; do
    if [ -n "$c" ] && [ -x "$c" ] && "$c" --version 2>/dev/null | grep -q "^$VER.stable"; then G="$c"; break; fi
  done
fi
if [ -z "$G" ]; then
  say "Godot $VER wird geladen …"
  TMP=$(mktemp -d)
  curl -sSfL -o "$TMP/godot.zip" "https://github.com/godotengine/godot/releases/download/$VER-stable/Godot_v$VER-stable_linux.x86_64.zip"
  python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$TMP/godot.zip" "$TMP"
  if [ -w /opt ] || [ "$(id -u)" = 0 ]; then mkdir -p /opt/godot; G=/opt/godot/godot; else mkdir -p "$HOME/.local/bin"; G="$HOME/.local/bin/godot"; fi
  mv "$TMP/Godot_v$VER-stable_linux.x86_64" "$G"; chmod +x "$G"; rm -rf "$TMP"
fi
say "Godot: $G ($("$G" --version 2>/dev/null | head -1))"
[ -n "$GITHUB_ENV" ] && echo "GODOT=$G" >> "$GITHUB_ENV"

# --- 2. export templates ----------------------------------------------------------------------
if [ $TEMPLATES = 1 ]; then
  python3 "$ROOT/tools/agent/fetch_templates.py" "$VER" || echo "!! Export-Vorlagen fehlen – Bauen geht erst nach erneutem Versuch"
fi

# --- 3. screenshots (xvfb + vulkan software renderer) -----------------------------------------
if [ $APT = 1 ] && ! command -v xvfb-run >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    say "xvfb + mesa-vulkan-drivers werden installiert …"
    (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xvfb mesa-vulkan-drivers libvulkan1 >/dev/null) \
      || echo "!! apt ging nicht – Screenshots gehen dann nicht (headless Tests schon)"
  fi
fi

# --- 4. private assets ------------------------------------------------------------------------
if [ $CI = 0 ]; then
  if [ -z "$ASSETS" ]; then
    for c in "/mnt/user-data/uploads/Tiefbau Tycoon/private/assets.tar" /mnt/user-data/uploads/*/private/assets.tar \
             "$ROOT/private/assets.tar" "$HOME/mnt/Tiefbau Tycoon/private/assets.tar"; do
      [ -f "$c" ] && { ASSETS="$c"; break; }
    done
  fi
  if [ -d "$ROOT/game/assets/consim" ] && [ -d "$ROOT/game/assets/barriers" ]; then
    say "Assets: vorhanden"
  elif [ -n "$ASSETS" ]; then
    say "Assets werden entpackt aus $ASSETS …"
    tar -xf "$ASSETS" -C "$ROOT"
  else
    echo "!! Private Assets fehlen (game/assets/consim, game/assets/barriers)."
    echo "   Das Spiel läuft trotzdem (Ersatzmodelle), aber Builds für Jonathan brauchen sie:"
    echo "   device_stage_files mit '<PC>/Tiefbau Tycoon/private/assets.tar', dann tools/setup_env.sh erneut (Skill tycoon-dev)."
  fi
fi

# --- 5. git -----------------------------------------------------------------------------------
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT" config user.name >/dev/null || git -C "$ROOT" config user.name "Claude (Tiefbau Tycoon)"
  git -C "$ROOT" config user.email >/dev/null || git -C "$ROOT" config user.email "noreply@anthropic.com"
  HOOK="$(git -C "$ROOT" rev-parse --git-path hooks)/pre-commit"
  if [ ! -f "$HOOK" ]; then
    mkdir -p "$(dirname "$HOOK")"
    printf '#!/bin/sh\n# installed by tools/setup_env.sh: project rules before every commit\nexec python3 "$(git rev-parse --show-toplevel)/tools/lint.py" --staged\n' > "$HOOK"
    chmod +x "$HOOK"
  fi
fi

# --- 6. import --------------------------------------------------------------------------------
say "Godot-Import (Klassen-Cache, Modelle) …"
timeout 1800 "$G" --headless --path "$ROOT/game" --import > /tmp/tt_setup_import.log 2>&1 || true
grep -E "SCRIPT ERROR|Parse Error" /tmp/tt_setup_import.log | head -10 || true
say "fertig. Prüfen: python3 tools/lint.py && tools/check.sh"
