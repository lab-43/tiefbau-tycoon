#!/bin/bash
# Runs end-to-end scenarios headless on the offline Utrecht map and reports pass/fail.
# usage: tools/test.sh [scenario ...]            default: smoke issue
#   scenarios: smoke issue job lowbed save+load pbf ebenen sichtweite fahren debug leuchten verkehrslichter rig markierungen absperrung  (save+load = save mid-dig,
#              then load and finish; rig = excavator linkage/cylinders, see game/test/rig_test.gd;
#              ebenen = height order of flat map layers, see game/test/layer_test.gd – also part of pbf;
#              sichtweite = city meshes sit at their chunk (visibility ranges), game/test/range_test.gd – also part of pbf;
#              fahren = calm driving: no twitching cars, no racing through bends, game/test/drive_test.gd on testdata/kreuzungen)
#   env: E2E_SPEED (default 10), E2E_TIMEOUT seconds per scenario (default 1500), E2E_SHOTS=<dir>
# Logs: /tmp/tt_e2e_<scenario>.log. Exit 1 if any scenario fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tools/lib.sh"
find_godot
[ -z "$G" ] && { echo "Godot nicht gefunden – erst tools/setup_env.sh ausführen"; exit 2; }
SPEED="${E2E_SPEED:-10}"; TMO="${E2E_TIMEOUT:-1500}"
SCEN=("$@"); [ ${#SCEN[@]} -eq 0 ] && SCEN=(smoke issue)
FAIL=0
run() {  # name, expected-ok-regex, extra args...
  local name="$1" ok="$2"; shift 2
  local log="/tmp/tt_e2e_${name}.log" t0=$(date +%s)
  local shots=(); [ -n "$E2E_SHOTS" ] && { mkdir -p "$E2E_SHOTS/$name"; shots=("--shots=$E2E_SHOTS/$name"); }
  local start=(--autostart --fixture=utrecht)
  [ "${AUTO:-1}" = 0 ] && start=()   # "load" continues the saved game; --autostart would found a new company
  timeout $((TMO + 60)) "$G" --headless --path "$ROOT/game" -- "${start[@]}" \
    --speed="$SPEED" --timeout="$TMO" "${shots[@]}" "$@" > "$log" 2>&1
  local rc=$? dt=$(( $(date +%s) - t0 ))
  if [ $rc -eq 0 ] && grep -qE "$ok" "$log"; then
    echo "OK    $name (${dt}s) $(grep -oE "$ok.*" "$log" | tail -1 | cut -c1-90)"
  else
    FAIL=1
    echo "FAIL  $name (rc=$rc, ${dt}s) – $log:"
    grep -E "E2E|SCRIPT ERROR|ERROR:|at: " "$log" | grep -v -E "ALSA|audio" | tail -12 | sed 's/^/      /'
  fi
}
ebenen() {  # flat map layers: water above the base ground and the landuse areas, below paths and roads (#4)
  local log=/tmp/tt_e2e_ebenen.log
  if timeout 300 "$G" --headless --path "$ROOT/game" -s res://test/layer_test.gd -- "$ROOT/testdata/utrecht.osm.pbf" > "$log" 2>&1 \
     && grep -q "EBENEN OK" "$log"; then echo "OK    ebenen $(grep -o 'EBENEN OK.*' "$log")"; else FAIL=1; echo "FAIL  ebenen – $log"; grep -E "EBENEN|SCRIPT ERROR" "$log" | tail -8 | sed 's/^/      /'; fi
}
sichtweite() {  # city meshes sit where their geometry is (visibility ranges count from the node origin, #5)
  local log=/tmp/tt_e2e_sichtweite.log
  if timeout 300 "$G" --headless --path "$ROOT/game" -s res://test/range_test.gd -- "$ROOT/testdata/utrecht.osm.pbf" > "$log" 2>&1 \
     && grep -q "RANGE OK" "$log"; then echo "OK    sichtweite $(grep -o 'RANGE OK.*' "$log")"; else FAIL=1; echo "FAIL  sichtweite – $log"; grep -E "RANGE|SCRIPT ERROR" "$log" | tail -8 | sed 's/^/      /'; fi
}
fahren() {  # traffic on the junction fixtures: twitches and too fast bends per km (#5)
  local log=/tmp/tt_e2e_fahren.log
  if timeout 600 "$G" --headless --path "$ROOT/game" res://test/drive_test.tscn -- --fixtures="$ROOT/testdata/kreuzungen" > "$log" 2>&1 \
     && grep -q "FAHREN OK" "$log"; then echo "OK    fahren $(grep -o 'FAHREN OK.*' "$log")"; else FAIL=1; echo "FAIL  fahren – $log"; grep -E "FAHREN|SCRIPT ERROR|^  " "$log" | tail -10 | sed 's/^/      /'; fi
}
for s in "${SCEN[@]}"; do
  case "$s" in
    smoke)  run smoke  "E2E OK" --e2e=smoke ;;
    issue)  run issue  "E2E OK issue" --e2e=issue ;;
    job)    run job    "E2E OK money" --e2e=job ;;
    lowbed) run lowbed "E2E OK lowbed" --e2e=lowbed ;;
    debug)  run debug  "E2E OK debug" --e2e=debug ;;
    leuchten) run leuchten "E2E OK leuchten" --e2e=leuchten ;;
    verkehrslichter) run verkehrslichter "E2E OK verkehrslichter" --e2e=verkehrslichter ;;
    save+load) run save "E2E OK save" --e2e=save && AUTO=0 run load "E2E OK money" --e2e=load ;;
    pbf)
      log=/tmp/tt_e2e_pbf.log
      if timeout 300 "$G" --headless --path "$ROOT/game" -s res://test/pbf_test.gd -- "$ROOT/testdata/utrecht.osm.pbf" > "$log" 2>&1 \
         && grep -q "PBF OK" "$log"; then echo "OK    pbf $(grep -o 'PBF OK.*' "$log")"; else FAIL=1; echo "FAIL  pbf – $log"; tail -8 "$log" | sed 's/^/      /'; fi
      ebenen; sichtweite ;;
    ebenen) ebenen ;;
    sichtweite) sichtweite ;;
    fahren) fahren ;;
    rig)  # excavator linkage + cylinders over all poses (needs the private model, skips without it)
      log=/tmp/tt_e2e_rig.log
      if timeout 300 "$G" --headless --path "$ROOT/game" -s res://test/rig_test.gd > "$log" 2>&1 \
         && grep -qE "RIG (OK|SKIP)" "$log"; then echo "OK    rig $(grep -oE 'RIG (OK|SKIP).*' "$log")"; else FAIL=1; echo "FAIL  rig – $log"; grep -E "FEHLER|FAIL|SCRIPT ERROR" "$log" | tail -8 | sed 's/^/      /'; fi ;;
    markierungen)  # screen markers (#7); also fails on any script error, the checks would not notice one in _draw
      run markierungen "E2E OK markierungen" --e2e=markierungen
      if grep -q "SCRIPT ERROR" /tmp/tt_e2e_markierungen.log; then FAIL=1; echo "FAIL  markierungen: Skriptfehler im Log"; grep -A3 "SCRIPT ERROR" /tmp/tt_e2e_markierungen.log | head -8 | sed 's/^/      /'; fi ;;
    absperrung)  # closure designer (#9); like markierungen it also fails on a script error (in _draw)
      run absperrung "E2E OK absperrung" --e2e=absperrung
      if grep -q "SCRIPT ERROR" /tmp/tt_e2e_absperrung.log; then FAIL=1; echo "FAIL  absperrung: Skriptfehler im Log"; grep -A3 "SCRIPT ERROR" /tmp/tt_e2e_absperrung.log | head -8 | sed 's/^/      /'; fi ;;
    *) echo "unbekanntes Szenario: $s"; FAIL=1 ;;
  esac
done
exit $FAIL
