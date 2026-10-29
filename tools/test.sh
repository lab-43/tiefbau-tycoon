#!/bin/bash
# Runs end-to-end scenarios headless on the offline Utrecht map and reports pass/fail.
# usage: tools/test.sh [scenario ...]            default: smoke issue
#   scenarios: smoke issue job lowbed save+load pbf ebenen sichtweite fahren debug leuchten verkehrslichter rig schaufel altstand markierungen absperrung gelaende vollsperrung umbau fahrzeuge baeume  (save+load = save mid-dig,
#              then load and finish; rig = excavator linkage/cylinders, see game/test/rig_test.gd;
#              schaufel = soil in the bucket (game/test/bucket_test.gd, stand-in model always, real model if present);
#              ebenen = height order of flat map layers, see game/test/layer_test.gd – also part of pbf;
#              sichtweite = city meshes sit at their chunk (visibility ranges), game/test/range_test.gd – also part of pbf;
#              baeume = no tree on the asphalt, few real trees dropped (#30), game/test/tree_test.gd – also part of pbf;
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
baeume() {  # trees stand beside the road, not on the asphalt (#30)
  local log=/tmp/tt_e2e_baeume.log
  if timeout 400 "$G" --headless --path "$ROOT/game" -s res://test/tree_test.gd -- "$ROOT/testdata/utrecht.osm.pbf" > "$log" 2>&1 \
     && grep -q "BAEUME OK" "$log"; then echo "OK    baeume $(grep -o 'BAEUME OK.*' "$log") – $(grep -o 'BAEUME [0-9].*' "$log" | cut -c8-110)"; else FAIL=1; echo "FAIL  baeume – $log"; grep -E "BAEUME|SCRIPT ERROR" "$log" | tail -8 | sed 's/^/      /'; fi
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
    altstand)  # save from an older map build: jobs with lane keys of another road numbering are found again (#23)
      run altstand_save "E2E OK altstand_save" --e2e=altstand_save && AUTO=0 run altstand_load "E2E OK altstand" --e2e=altstand_load
      if grep -q "SCRIPT ERROR" /tmp/tt_e2e_altstand_load.log; then FAIL=1; echo "FAIL  altstand: Skriptfehler im Log (Release-Versionen stürzen daran ab)"; grep -A3 "SCRIPT ERROR" /tmp/tt_e2e_altstand_load.log | head -8 | sed 's/^/      /'; fi ;;
    pbf)
      log=/tmp/tt_e2e_pbf.log
      if timeout 300 "$G" --headless --path "$ROOT/game" -s res://test/pbf_test.gd -- "$ROOT/testdata/utrecht.osm.pbf" > "$log" 2>&1 \
         && grep -q "PBF OK" "$log"; then echo "OK    pbf $(grep -o 'PBF OK.*' "$log")"; else FAIL=1; echo "FAIL  pbf – $log"; tail -8 "$log" | sed 's/^/      /'; fi
      ebenen; sichtweite; baeume ;;
    ebenen) ebenen ;;
    baeume) baeume ;;
    sichtweite) sichtweite ;;
    fahren) fahren ;;
    rig)  # excavator linkage + cylinders over all poses, A 918 and R 938 (needs the private models, skips without)
      for mdl in excavator_a918 excavator_r938; do
        log=/tmp/tt_e2e_rig_$mdl.log
        if timeout 300 "$G" --headless --path "$ROOT/game" -s res://test/rig_test.gd -- --model=$mdl > "$log" 2>&1 \
           && grep -qE "RIG (OK|SKIP)" "$log"; then echo "OK    rig $(grep -oE 'RIG (OK|SKIP).*' "$log")"; else FAIL=1; echo "FAIL  rig $mdl – $log"; grep -E "FEHLER|FAIL|SCRIPT ERROR" "$log" | tail -8 | sed 's/^/      /'; fi
      done ;;
    schaufel)  # soil in the excavator bucket sits in the cavity, faces up when carried, pours out (#11)
      log=/tmp/tt_e2e_schaufel.log
      if timeout 300 "$G" --headless --path "$ROOT/game" -s res://test/bucket_test.gd > "$log" 2>&1 \
         && grep -q "SCHAUFEL OK" "$log"; then echo "OK    schaufel $(grep -o 'SCHAUFEL OK.*' "$log")"; else FAIL=1; echo "FAIL  schaufel – $log"; grep -E "FEHLER|NICHT ERKANNT|FAIL|SCRIPT ERROR" "$log" | tail -8 | sed 's/^/      /'; fi ;;
    markierungen)  # screen markers (#7); also fails on any script error, the checks would not notice one in _draw
      run markierungen "E2E OK markierungen" --e2e=markierungen
      if grep -q "SCRIPT ERROR" /tmp/tt_e2e_markierungen.log; then FAIL=1; echo "FAIL  markierungen: Skriptfehler im Log"; grep -A3 "SCRIPT ERROR" /tmp/tt_e2e_markierungen.log | head -8 | sed 's/^/      /'; fi ;;
    absperrung)  # closure designer (#9); like markierungen it also fails on a script error (in _draw)
      run absperrung "E2E OK absperrung" --e2e=absperrung
      if grep -q "SCRIPT ERROR" /tmp/tt_e2e_absperrung.log; then FAIL=1; echo "FAIL  absperrung: Skriptfehler im Log"; grep -A3 "SCRIPT ERROR" /tmp/tt_e2e_absperrung.log | head -8 | sed 's/^/      /'; fi ;;
    gelaende) DEVMAP="$HOME/.local/share/godot/app_userdata/Baustellen Manager/maps/dev_utrecht"
      rm -f "$DEVMAP"/baked_v*_syn.bin   # a map saved by older code of the same BAKE_VERSION would hide bake changes
      run gelaende "E2E OK gelaende" --e2e=gelaende --terrain=synthetic
      # download path: tiles from a local Terrarium server (PNG and lossless WebP)
      python3 "$ROOT/game/test/mock_terrain.py" 8766 & MT=$!
      sleep 1
      rm -rf "$DEVMAP/terrain_test" "$DEVMAP"/baked_v*_test*.bin
      # a server answering with web pages instead of tiles: the map stays flat and is kept as the flat one,
      # the next start (png) downloads again and replaces it
      run gelaende-html "E2E OK smoke" --e2e=smoke --terrain-url=http://127.0.0.1:8766/html/{z}/{x}/{y}.png
      if grep -q "Keine Geländehöhen verfügbar" /tmp/tt_e2e_gelaende-html.log && ls "$DEVMAP"/baked_v*_test_flach.bin >/dev/null 2>&1 \
         && ! ls "$DEVMAP"/terrain_test/*.png >/dev/null 2>&1; then echo "OK    gelaende-html: Webseiten nicht als Kacheln gespeichert, Karte flach zwischengespeichert"
      else FAIL=1; echo "FAIL  gelaende-html: Webseite als Kachel gespeichert oder flache Karte fehlt"; fi
      run gelaende-png "E2E OK gelaende" --e2e=gelaende --terrain-url=http://127.0.0.1:8766/ok/{z}/{x}/{y}.png
      if ls "$DEVMAP"/baked_v*_test_flach.bin >/dev/null 2>&1; then FAIL=1; echo "FAIL  gelaende-png: flache Karte nicht ersetzt"; fi
      rm -rf "$DEVMAP/terrain_test" "$DEVMAP"/baked_v*_test*.bin
      run gelaende-webp "E2E OK gelaende" --e2e=gelaende --terrain-url=http://127.0.0.1:8766/webp/{z}/{x}/{y}.webp
      kill $MT 2>/dev/null ;;
    vollsperrung)  # full road closure (#20): designer, traffic stays off the road, site vehicles get in
      run vollsperrung "E2E OK vollsperrung" --e2e=vollsperrung
      if grep -q "SCRIPT ERROR" /tmp/tt_e2e_vollsperrung.log; then FAIL=1; echo "FAIL  vollsperrung: Skriptfehler im Log"; grep -A3 "SCRIPT ERROR" /tmp/tt_e2e_vollsperrung.log | head -8 | sed 's/^/      /'; fi ;;
    umbau)  # closure changed while the excavator digs (#21): work pauses, crew rebuilds, work goes on
      run umbau "E2E OK umbau" --e2e=umbau
      if grep -q "SCRIPT ERROR" /tmp/tt_e2e_umbau.log; then FAIL=1; echo "FAIL  umbau: Skriptfehler im Log"; grep -A3 "SCRIPT ERROR" /tmp/tt_e2e_umbau.log | head -8 | sed 's/^/      /'; fi ;;
    fahrzeuge)  # new machines (#24): HQ, ground/lights/joints, low-loader round trips, R 938 digging
      run fahrzeuge "E2E OK fahrzeuge" --e2e=fahrzeuge ;;
    *) echo "unbekanntes Szenario: $s"; FAIL=1 ;;
  esac
done
exit $FAIL
