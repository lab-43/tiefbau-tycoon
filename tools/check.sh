#!/bin/bash
# Compiles every GDScript (src/ + test/) with the autoloads registered and prints each error as
# "file:line: message". Exit 1 if anything fails. Takes ~2 s.
# usage: tools/check.sh [res-relative files...]
# If a script is newer than Godot's class cache (new class_name, rebase onto other sessions' work),
# it re-imports first (~8 s), otherwise new classes would show up as "Identifier not declared".
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tools/lib.sh"
find_godot
[ -z "$G" ] && { echo "Godot nicht gefunden – erst tools/setup_env.sh ausführen"; exit 2; }
CACHE="$ROOT/game/.godot/global_script_class_cache.cfg"
if [ ! -f "$CACHE" ] || [ -n "$(find "$ROOT/game/src" "$ROOT/game/test" -name '*.gd' -newer "$CACHE" -print -quit)" ]; then
  echo "check: Klassen-Cache veraltet – importiere …"
  timeout 1800 "$G" --headless --path "$ROOT/game" --import > /tmp/tt_check_import.log 2>&1
  touch "$CACHE" 2>/dev/null   # Godot leaves it untouched when nothing changed
fi
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
