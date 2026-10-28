#!/bin/bash
# Merges the current branch into main automatically and safely while other sessions do the same.
#   1. working tree must be clean (commit first)
#   2. fetch + rebase onto origin/main      (conflict -> stop, resolve, run again)
#   3. lint + compile check + e2e tests      (default: smoke issue; add more with --e2e=job,lowbed)
#   4. push HEAD to main as a fast-forward  (main moved meanwhile -> back to 2, up to 4 times)
#   5. pushing to main not allowed here?    -> push the branch with an "Automerge: ja" commit;
#                                              CI (.github/workflows/ci.yml) merges it after green tests
# usage: tools/agent/merge.sh [--e2e=job,lowbed] [--no-test] [--dry-run]
# Never force-pushes main. Exit: 0 merged (or handed to CI), 1 tests failed, 2 conflict, 3 other problem.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 3
EXTRA=""; TEST=1; DRY=0
for a in "$@"; do
  case "$a" in
    --e2e=*) EXTRA="${a#--e2e=}" ;;
    --no-test) TEST=0 ;;
    --dry-run) DRY=1 ;;
  esac
done
BR=$(git rev-parse --abbrev-ref HEAD)
[ "$BR" = "main" ] && { echo "Du bist auf main. Arbeit gehört auf einen eigenen Branch (Skill parallel-arbeiten)."; exit 3; }
[ -n "$(git status --porcelain --untracked-files=no)" ] && { echo "Nicht committete Änderungen – erst committen."; git status --short; exit 3; }

for attempt in 1 2 3 4; do
  echo "== Versuch $attempt: hole origin/main …"
  git fetch -q origin main || { echo "fetch fehlgeschlagen"; exit 3; }
  if ! git merge-base --is-ancestor origin/main HEAD; then
    echo "== rebase $BR auf origin/main …"
    if ! git rebase -q origin/main; then
      echo "!! Konflikt beim Rebase. Dateien:"; git diff --name-only --diff-filter=U | sed 's/^/   /'
      echo "   Beide Absichten erhalten (die andere Session hat ihre Änderung schon getestet),"
      echo "   dann: git add <dateien> && git rebase --continue && tools/agent/merge.sh"
      echo "   Unsicher? git rebase --abort und in der Meldung nachfragen."
      exit 2
    fi
  fi
  if [ $TEST = 1 ]; then
    python3 tools/lint.py || exit 1
    tools/check.sh || exit 1
    SC="smoke issue"; [ -n "$EXTRA" ] && SC="$SC ${EXTRA//,/ }"
    # shellcheck disable=SC2086
    tools/test.sh $SC || exit 1
  fi
  [ $DRY = 1 ] && { echo "== Trockenlauf: würde $(git rev-parse --short HEAD) nach main schieben"; exit 0; }
  OUT=$(git push origin HEAD:main 2>&1); RC=$?
  if [ $RC = 0 ]; then
    echo "== zusammengeführt: main = $(git rev-parse --short HEAD) ($(git log -1 --format=%s))"
    git push -q --force-with-lease origin "HEAD:$BR" 2>/dev/null || true   # keep the branch in sync (own branch only)
    exit 0
  fi
  if echo "$OUT" | grep -qE "\((fetch first|non-fast-forward)\)"; then
    echo "== main hat sich bewegt (andere Session war schneller) – nochmal"; sleep $((attempt * 3)); continue
  fi
  echo "$OUT" | tail -5
  echo "== Direktes Schieben nach main geht hier nicht – übergebe an CI (Automerge) …"
  git commit -q --allow-empty -m "Automerge: $BR" -m "Automerge: ja" || exit 3
  git push -q --force-with-lease origin "HEAD:$BR" || { echo "Branch-Push ging auch nicht – Jonathan Bescheid geben"; exit 3; }
  echo "== Branch $BR gepusht. CI testet und schiebt nach main, wenn grün und main nicht weitergelaufen ist."
  echo "   Prüfen: gh run list --branch $BR  (oder später: git fetch && git branch -r --contains HEAD | grep main)"
  exit 0
done
echo "main bewegt sich zu schnell – später nochmal versuchen."; exit 3
