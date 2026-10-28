#!/bin/bash
# Runs end-to-end scenarios headless on the offline Utrecht map and reports pass/fail.
# usage: tools/test.sh [scenario ...]            default: smoke issue
#   scenarios: smoke issue job lowbed save+load pbf  (save+load = save mid-dig, then load and finish)
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
for s in "${SCEN[@]}"; do
  case "$s" in
    smoke)  run smoke  "E2E OK" --e2e=smoke ;;
    issue)  run issue  "E2E OK issue" --e2e=issue ;;
    job)    run job    "E2E OK money" --e2e=job ;;
    lowbed) run lowbed "E2E OK lowbed" --e2e=lowbed ;;
    save+load) run save "E2E OK save" --e2e=save && AUTO=0 run load "E2E OK money" --e2e=load ;;
    pbf)
      log=/tmp/tt_e2e_pbf.log
      if timeout 300 "$G" --headless --path "$ROOT/game" -s res://test/pbf_test.gd -- "$ROOT/testdata/utrecht.osm.pbf" > "$log" 2>&1 \
         && grep -q "PBF OK" "$log"; then echo "OK    pbf $(grep -o 'PBF OK.*' "$log")"; else FAIL=1; echo "FAIL  pbf – $log"; tail -8 "$log" | sed 's/^/      /'; fi ;;
    *) echo "unbekanntes Szenario: $s"; FAIL=1 ;;
  esac
done
exit $FAIL
