#!/bin/bash
# Junction bench ("Kreuzungs-Prüfstand"): bakes the fixed junctions in testdata/kreuzungen with the
# current road code, measures them and draws pictures (see tools/kreuzungen.py for the measures).
# usage: tools/kreuzungen.sh [out-dir] [--only=a,b] [--compare=<dir with exported JSONs>[,label]]
#   default out-dir: /tmp/kreuzungen   pictures: <out>/bilder/<fixture>.png and <fixture>_nah.png
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tools/lib.sh"
find_godot
[ -z "$G" ] && { echo "Godot nicht gefunden – erst tools/setup_env.sh ausführen"; exit 2; }
OUT=/tmp/kreuzungen; ONLY=""; CMP=""; CMPLAB=""
for a in "$@"; do
  case "$a" in
    --only=*) ONLY="${a#--only=}" ;;
    --compare=*) v="${a#--compare=}"; CMP="${v%%,*}"; [ "$v" != "$CMP" ] && CMPLAB="${v#*,}" ;;
    -*) echo "unbekannte Option: $a (erlaubt: --only=, --compare=)"; exit 2 ;;
    *) OUT="$a" ;;
  esac
done
mkdir -p "$OUT/export"
ARGS=(--fixtures="$ROOT/testdata/kreuzungen" --out="$OUT/export"); [ -n "$ONLY" ] && ARGS+=(--only="$ONLY")
timeout 600 "$G" --headless --path "$ROOT/game" -s res://test/junction_bench.gd -- "${ARGS[@]}" > "$OUT/bench.log" 2>&1
grep -q "BENCH OK" "$OUT/bench.log" || { echo "FAIL  Kreuzungs-Export – $OUT/bench.log"; grep -E "BENCH|SCRIPT ERROR|at: " "$OUT/bench.log" | tail -8; exit 1; }
PY=(python3 "$ROOT/tools/kreuzungen.py" "$OUT/export"); LAB="heute"
[ -n "$CMP" ] && { PY+=("$CMP"); LAB="heute,${CMPLAB:-vergleich}"; }
[ -n "$ONLY" ] && PY+=(--only "$ONLY")
"${PY[@]}" --labels "$LAB" --out "$OUT/bilder"
