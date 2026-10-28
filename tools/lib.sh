#!/bin/bash
# Shared helpers for the tools/*.sh scripts (source it: . "$(dirname "$0")/lib.sh").
# find_godot: sets G to the Godot 4.5.1 binary: $GODOT, /opt/godot/godot, ~/.local/bin/godot
# (where setup_env.sh installs without root) or godot on PATH. Empty if none.
find_godot() {
  G=""
  local c
  for c in "${GODOT:-}" /opt/godot/godot "$HOME/.local/bin/godot" "$(command -v godot 2>/dev/null)"; do
    if [ -n "$c" ] && [ -x "$c" ]; then G="$c"; return 0; fi
  done
  return 1
}
