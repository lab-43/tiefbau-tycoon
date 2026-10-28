#!/bin/bash
# Builds the Windows game into OUT (default build/out):
#   BaustellenManager.exe / .console.exe   Godot runtime (only changes with the Godot version)
#   BaustellenManager.pck                  code, UI, shaders (small, changes with every fix)
#   BaustellenManager-Daten.pck            models, barrier set, demo map (big, rebuilt only when
#                                          game/assets/consim, game/assets/barriers or test_fixtures change)
#   portable.txt (shared data folder ../../userdata), LIESMICH.txt
# usage: tools/build.sh [OUT] [--test-build]
#   --test-build  also writes Starten.cmd that runs this pck with the exe in ../main (issue builds)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="${GODOT:-}"
[ -z "$G" ] && { [ -x /opt/godot/godot ] && G=/opt/godot/godot || G=$(command -v godot || true); }
[ -z "$G" ] && { echo "Godot nicht gefunden – erst tools/setup_env.sh ausführen"; exit 1; }
OUT="${1:-$ROOT/build/out}"
TEST=0; [ "$2" = "--test-build" ] && TEST=1
mkdir -p "$OUT" && OUT="$(cd "$OUT" && pwd)"   # absolute: the export runs inside game/
[ -d "$ROOT/game/assets/consim" ] || { echo "Assets fehlen (game/assets/consim) – siehe Skill tycoon-dev, Abschnitt Assets"; exit 1; }

VERSION=$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)
BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "")
DATE=$(date -u +%Y-%m-%dT%H:%MZ)
printf '{"version": "%s", "branch": "%s", "commit": "%s", "date": "%s"}\n' "$VERSION" "$BRANCH" "$COMMIT" "$DATE" > "$ROOT/game/build_info.json"
echo "Build $VERSION ($BRANCH $COMMIT)"

cd "$ROOT/game"
timeout 900 "$G" --headless --path . --import > /tmp/tt_import.log 2>&1 || true
timeout 900 "$G" --headless --path . --export-release "Windows Desktop" "$OUT/BaustellenManager.exe" > /tmp/tt_export.log 2>&1 \
  || { tail -30 /tmp/tt_export.log; exit 1; }

# content hash (not mtimes): a fresh clone must not rebuild/re-transfer the 230 MB pack
HASH=$( (cd "$ROOT/game" && find assets/consim assets/barriers test_fixtures -type f ! -name '*.import' -print0 | sort -z | xargs -0 sha1sum; \
         grep -A40 'name="Windows Daten"' "$ROOT/game/export_presets.cfg") | sha1sum | cut -c1-16)
if [ ! -f "$OUT/BaustellenManager-Daten.pck" ] || [ "$(cat "$OUT/daten.hash" 2>/dev/null)" != "$HASH" ]; then
  echo "Daten-Pack wird neu gebaut …"
  timeout 900 "$G" --headless --path . --export-pack "Windows Daten" "$OUT/BaustellenManager-Daten.pck" > /tmp/tt_export_data.log 2>&1 \
    || { tail -30 /tmp/tt_export_data.log; exit 1; }
  echo "$HASH" > "$OUT/daten.hash"
fi
cp "$ROOT/tools/build/LIESMICH.txt" "$OUT/LIESMICH.txt"
printf 'Portabler Modus: Spielstände, Karten, Meldungen und Protokolle liegen im gemeinsamen Ordner unten.\ndata=../../userdata\n' > "$OUT/portable.txt"
if [ $TEST = 1 ]; then
  printf '@echo off\r\nrem Testversion: startet diesen Stand mit dem Spiel aus build\\main (gleiche Spielstände und Meldungen)\r\nstart "" "%%~dp0..\\main\\BaustellenManager.exe" --main-pack "%%~dp0BaustellenManager.pck"\r\n' > "$OUT/Starten.cmd"
fi
printf 'version=%s\ncommit=%s\nbranch=%s\ndate=%s\ndaten=%s\n' "$VERSION" "$COMMIT" "$BRANCH" "$DATE" "$HASH" > "$OUT/VERSION.txt"
rm -f "$ROOT/game/build_info.json"
ls -la "$OUT" | grep -v total
