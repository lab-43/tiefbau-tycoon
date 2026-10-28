#!/bin/bash
# Compiles every GDScript (src/ + test/) with the autoloads registered and prints each error as
# "file:line: message". Exit 1 if anything fails. Takes ~2 s.
# usage: tools/check.sh [res-relative files...]
# After adding a new class_name run "godot --headless --path game --import" once (class cache),
# otherwise other scripts report "Identifier not declared" for the new class.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="${GODOT:-}"
[ -z "$G" ] && { [ -x /opt/godot/godot ] && G=/opt/godot/godot || G=$(command -v godot || true); }
[ -z "$G" ] && { echo "Godot nicht gefunden – erst tools/setup_env.sh ausführen"; exit 2; }
LOG=$(mktemp)
timeout 300 "$G" --headless --path "$ROOT/game" -s res://test/compile_all.gd -- "$@" > "$LOG" 2>&1
RC=$?
awk '
  /SCRIPT ERROR: / {msg=$0; sub(/.*SCRIPT ERROR: /,"",msg); next}
  /at: GDScript::reload/ { if (msg!="") { loc=$0; sub(/.*\(res:\/\//,"",loc); sub(/\)$/,"",loc); print "game/" loc ": " msg; msg="" } }
  /COMPILE FAIL/ {fail=1}
' "$LOG" | sort -u
grep -E "^COMPILE DONE" "$LOG" | sed 's/^COMPILE DONE/check:/'
if [ $RC -ne 0 ]; then
  grep -q "COMPILE DONE" "$LOG" || { echo "check: Godot ist abgebrochen (rc=$RC):"; tail -20 "$LOG"; }
  rm -f "$LOG"; exit 1
fi
rm -f "$LOG"
