#!/bin/bash
# Merges the current branch into main automatically and safely while other sessions do the same.
#   1. working tree must be clean (commit first)
#   2. fetch + rebase onto origin/main      (conflict -> stop, resolve, run again)
#   3. lint + compile check + e2e tests      (first round: smoke issue + --e2e=…; after a later
#                                             rebase: lint, check, smoke, issue)
#   4. push HEAD to main as a fast-forward  (main moved meanwhile -> back to 2, up to 6 rounds)
#   5. pushing to main not allowed here?    -> push the branch with an "Automerge: ja" commit; CI
#                                              (.github/workflows/ci.yml) rebases, tests and merges it
#                                              serially. Then: tools/agent/merge.sh --wait
# usage: tools/agent/merge.sh [--e2e=job,lowbed,save+load] [--no-test] [--dry-run]
#        tools/agent/merge.sh --wait[=MINUTES]    wait until CI has merged this branch (default 9 min)
# Never force-pushes main. Exit: 0 merged, 1 tests failed, 2 conflict, 3 other problem,
#                                5 handed to CI / still waiting for CI.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 3
EXTRA=""; TEST=1; DRY=0; WAIT=""
for a in "$@"; do
  case "$a" in
    --e2e=*) EXTRA="${a#--e2e=}" ;;
    --no-test) TEST=0 ;;
    --dry-run) DRY=1 ;;
    --wait) WAIT=9 ;;
    --wait=*) WAIT="${a#--wait=}" ;;
  esac
done
BR=$(git rev-parse --abbrev-ref HEAD)

merged_by_ci() {  # CI pushes the (rebased) branch tip to main and then sets the branch to it
  git fetch -q origin main "$BR" 2>/dev/null
  git merge-base --is-ancestor "origin/$BR" origin/main 2>/dev/null
}

if [ -n "$WAIT" ]; then
  END=$(( $(date +%s) + WAIT * 60 ))
  while [ "$(date +%s)" -lt "$END" ]; do
    if merged_by_ci; then
      echo "== von CI zusammengeführt: main = $(git rev-parse --short origin/main)"
      git merge -q --ff-only "origin/$BR" 2>/dev/null || true
      exit 0
    fi
    sleep 30
  done
  echo "== CI hat $BR noch nicht zusammengeführt."
  command -v gh >/dev/null && gh run list --branch "$BR" --limit 3 2>/dev/null
  echo "   Später nochmal: tools/agent/merge.sh --wait. Schlägt die CI fehl (Konflikt, Tests),"
  echo "   lokal tools/agent/merge.sh erneut ausführen."
  exit 5
fi

[ "$BR" = "main" ] || [ "$BR" = "HEAD" ] && { echo "Kein eigener Branch (aktuell: $BR). Arbeit gehört auf einen eigenen Branch (Skill parallel-arbeiten)."; exit 3; }
[ -n "$(git status --porcelain --untracked-files=no)" ] && { echo "Nicht committete Änderungen – erst committen."; git status --short; exit 3; }

for attempt in 1 2 3 4 5 6; do
  echo "== Runde $attempt: hole origin/main …"
  git fetch -q origin main || { echo "fetch fehlgeschlagen"; exit 3; }
  REBASED=0
  if ! git merge-base --is-ancestor origin/main HEAD; then
    echo "== rebase $BR auf origin/main …"
    if ! git rebase -q origin/main; then
      echo "!! Konflikt beim Rebase. Dateien:"; git diff --name-only --diff-filter=U | sed 's/^/   /'
      echo "   Beide Absichten erhalten (die andere Session hat ihre Änderung schon getestet),"
      echo "   dann: git add <dateien> && git rebase --continue && tools/agent/merge.sh"
      echo "   Unsicher? git rebase --abort und in der Meldung nachfragen."
      exit 2
    fi
    REBASED=1
  fi
  if [ $TEST = 1 ] && { [ $attempt = 1 ] || [ $REBASED = 1 ]; }; then
    python3 tools/lint.py || exit 1
    tools/agent/test_issues.sh || exit 1
    tools/check.sh || exit 1          # re-imports by itself if the rebase brought new scripts
    SC="smoke issue"; [ $attempt = 1 ] && [ -n "$EXTRA" ] && SC="$SC ${EXTRA//,/ }"
    # shellcheck disable=SC2086
    tools/test.sh $SC || exit 1
  fi
  [ $DRY = 1 ] && { echo "== Trockenlauf: würde $(git rev-parse --short HEAD) nach main schieben"; exit 0; }
  OUT=$(git push origin HEAD:main 2>&1); RC=$?
  if [ $RC = 0 ]; then
    echo "== zusammengeführt: main = $(git rev-parse --short HEAD) ($(git log -1 --format=%s))"
    git push -q --force-with-lease origin "HEAD:$BR" 2>/dev/null || true   # keep the own branch in sync
    exit 0
  fi
  if echo "$OUT" | grep -qE "\((fetch first|non-fast-forward)\)"; then
    W=$(( 5 + RANDOM % 15 ))
    echo "== main hat sich bewegt (andere Session war schneller) – neue Runde in ${W}s"; sleep $W; continue
  fi
  echo "$OUT" | tail -5
  echo "== Direktes Schieben nach main geht hier nicht – übergebe an die CI (Automerge) …"
  if git diff --name-only origin/main...HEAD | grep -q '^\.github/workflows/'; then
    echo "!! Der Branch ändert .github/workflows/. Das darf die CI nicht selbst nach main schieben (GitHub-Regel)."
    echo "   Jonathan muss diesen Branch auf GitHub zusammenführen. In der Meldung Bescheid geben."
  fi
  git commit -q --allow-empty -m "Automerge: $BR" -m "Automerge: ja" || exit 3
  git push -q --force-with-lease origin "HEAD:$BR" || { echo "Branch-Push ging auch nicht – Jonathan Bescheid geben"; exit 3; }
  echo "== Branch $BR gepusht. Die CI testet, rebased bei Bedarf und schiebt nach main."
  echo "   Warten: tools/agent/merge.sh --wait   (prüft alle 30 s, bis zu 9 min pro Aufruf)"
  exit 5
done
echo "main bewegt sich zu schnell – später nochmal versuchen."; exit 3
