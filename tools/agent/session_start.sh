#!/bin/bash
# SessionStart hook (.claude/settings.json): a short situation report for a new agent session.
# Must stay fast (<15 s) and never fail the session.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" 2>/dev/null || exit 0
echo "# Tiefbau Tycoon – Sitzungsstart"
echo "Andere Claude-Sessions arbeiten womöglich gleichzeitig an diesem Repo. Vor Änderungen: Skill parallel-arbeiten."
if git rev-parse --git-dir >/dev/null 2>&1; then
  timeout 12 git fetch -q origin 2>/dev/null
  BR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  echo "Branch: $BR ($(git log -1 --format='%h %s' 2>/dev/null))"
  if git rev-parse -q --verify origin/main >/dev/null; then
    B=$(git rev-list --count HEAD..origin/main 2>/dev/null); A=$(git rev-list --count origin/main..HEAD 2>/dev/null)
    echo "Gegenüber origin/main: $A eigene, $B neue auf main."
    echo "Zuletzt auf main:"; git log -5 --format='  %h %ad %s' --date=format:'%d.%m. %H:%M' origin/main
    ACT=$(git for-each-ref --sort=-committerdate --format='%(refname:short)|%(committerdate:relative)|%(contents:subject)' refs/remotes/origin \
          | grep -v -E '^origin(/(main|HEAD))?\|' | head -8)
    if [ -n "$ACT" ]; then
      echo "Andere Branches (mögliche parallele Arbeit):"
      echo "$ACT" | awk -F'|' '{printf "  %s (%s): %s\n", $1, $2, $3}'
    fi
  fi
fi
G="${GODOT:-}"; [ -z "$G" ] && { [ -x /opt/godot/godot ] && G=/opt/godot/godot || G=$(command -v godot 2>/dev/null); }
MISS=""
[ -z "$G" ] && MISS="$MISS Godot"
[ -d game/assets/consim ] || MISS="$MISS Assets"
[ -d game/.godot ] || MISS="$MISS Import"
[ -n "$MISS" ] && echo "Umgebung unvollständig (fehlt:$MISS) → tools/setup_env.sh (Skill tycoon-dev)."
echo "Meldungen/Übernahmen liegen auf Jonathans PC: python3 tools/agent/issues.py next (per Geräte-Shell, Skill issue-ablauf)."
if [ -d docs/lessons ]; then
  echo "Lektionen (docs/lessons, vor Änderungen im Bereich lesen):"
  for f in docs/lessons/*.md; do
    [ "$(basename "$f")" = README.md ] && continue
    b=$(sed -n 's/^bereich: *//p' "$f" | head -1); t=$(sed -n 's/^titel: *//p' "$f" | head -1)
    echo "$b|$t|$(basename "$f" .md)"
  done | sort | awk -F'|' '{ if ($1 != last) { printf "  [%s]\n", $1; last = $1 } printf "    %s (%s)\n", $2, $3 }'
fi
exit 0
