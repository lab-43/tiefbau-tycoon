#!/bin/bash
# Godot helpers.
#   tools/gd.sh import                                  re-import (class cache, assets)
#   tools/gd.sh script res://test/x.gd [args]           run a SceneTree script headless
#   tools/gd.sh run [game args]                         run the game rendered (xvfb + Vulkan/Mesa), e.g.
#       tools/gd.sh run -- --autostart --fixture=utrecht --e2e=smoke --shots=/tmp/shots
#   tools/gd.sh shot res://scene.tscn out.png [frames] [WxH]   render a single scene to a PNG
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tools/lib.sh"
find_godot
P="$ROOT/game"
case "$1" in
  check) "$ROOT/tools/check.sh" ;;
  import) timeout 900 $G --headless --path $P --import 2>&1 | grep -E "ERROR|SCRIPT ERROR|Parse Error" | grep -v "audio" | head -40 ;;
  script) shift; S=$1; shift; timeout ${TMO:-900} $G --headless --path $P -s $S -- "$@" 2>&1 | grep -v -E "^$|ALSA|audio driver|init_output_device|falling back to the dummy" ;;
  run) shift; timeout ${TMO:-900} xvfb-run -a -s "-screen 0 1920x1080x24" $G --path $P --rendering-driver vulkan "$@" 2>&1 | grep -v -E "^$|ALSA|audio driver|init_output_device|falling back to the dummy" ;;
  shot) timeout ${TMO:-600} xvfb-run -a -s "-screen 0 1920x1080x24" $G --path $P --rendering-driver vulkan -s res://test/shot.gd -- --scene=$2 --out=$3 --frames=${4:-30} --size=${5:-1280x720} 2>&1 | grep -v -E "^$|ALSA|audio driver|init_output_device|falling back to the dummy" ;;
esac
