#!/bin/bash
# Tests tools/agent/issues.py: parallel claims, parallel creates, owner checks, locks, stale takeover.
# Runs in a temp folder (never touches real issues). Used by CI. Exit 1 on the first failure.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P="python3 $ROOT/tools/agent/issues.py --dir $T/issues"
fail() { echo "FAIL issues: $*"; exit 1; }
mkdir -p "$T/issues"
$P create --session s0 --title "Rennen" >/dev/null 2>&1 || fail "create"

# 1. eight sessions claim the same issue at once: exactly one wins
for i in 1 2 3 4 5 6 7 8; do ( $P claim 1 --session s$i --areas verkehr >/dev/null 2>&1; echo $? > "$T/rc$i" ) & done; wait
WIN=$(grep -l '^0$' "$T"/rc* | wc -l)
[ "$WIN" = 1 ] || fail "$WIN Gewinner bei parallelen Übernahmen"
OWNER=s$(grep -l '^0$' "$T"/rc* | sed 's/.*rc//')

# 2. ten parallel creates with different titles: unique ids
for i in $(seq 1 10); do ( $P create --session c$i --title "Titel $i" >/dev/null 2>&1 ) & done; wait
[ "$(ls "$T/issues" | grep -c '^[0-9]')" = 11 ] || fail "nicht 11 Meldungen"
[ -z "$(ls "$T/issues" | grep '^[0-9]' | cut -d- -f1 | sort | uniq -d)" ] || fail "doppelte Nummern"

# 3. only the owner may ask/plan/fix/release; anyone may comment
OTHER=s9; [ "$OWNER" = s9 ] && OTHER=s8
$P ask 1 --session $OTHER --text x >/dev/null 2>&1; [ $? = 2 ] || fail "fremde Rückfrage erlaubt"
$P release 1 --session $OTHER >/dev/null 2>&1; [ $? = 2 ] || fail "fremde Freigabe erlaubt"
$P comment 1 --session $OTHER --text ok >/dev/null 2>&1 || fail "Kommentar verboten"
$P ask 1 --session $OWNER --text "Frage?" >/dev/null 2>&1 || fail "eigene Rückfrage"
[ "$($P show 1 --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')" = rueckfrage ] || fail "Status nicht rueckfrage"
$P release 1 --session $OWNER >/dev/null 2>&1 || fail "eigene Freigabe"
$P claim 1 --session $OTHER >/dev/null 2>&1 || fail "nach Freigabe nicht übernehmbar"

# 4. stale claim (7 h without heartbeat) can be taken over
D="$T/issues/$(ls "$T/issues" | grep '^0001')/claims"; G=$(ls "$D" | sort -n | tail -1)
python3 - "$D/$G" <<'EOF'
import json, os, sys, time
d = sys.argv[1]; old = time.time() - 7 * 3600
o = json.load(open(d + "/owner.json")); o["heartbeat_unix"] = old; json.dump(o, open(d + "/owner.json", "w"))
for f in ("owner.json", "herzschlag", ""):
    p = os.path.join(d, f)
    if os.path.exists(p):
        os.utime(p, (old, old))
EOF
$P claim 1 --session s99 >/dev/null 2>&1 || fail "verwaiste Übernahme nicht übernehmbar"

# 5. locks
$P lock build-main --session a >/dev/null 2>&1 || fail "lock a"
$P lock build-main --session b >/dev/null 2>&1; [ $? = 2 ] || fail "doppelte Sperre"
$P unlock build-main --session b >/dev/null 2>&1; [ $? = 2 ] || fail "fremdes unlock"
$P unlock build-main --session a >/dev/null 2>&1 || fail "unlock a"
$P lock build-main --session b >/dev/null 2>&1 || fail "lock b nach unlock"

# 6. no thread line lost
[ "$(grep -c '' "$T/issues/$(ls "$T/issues" | grep '^0001')/verlauf.jsonl")" -ge 7 ] || fail "Verlauf unvollständig"
echo "OK    issues.py (Übernahmen, Nummern, Rechte, Sperren, verwaiste Übernahmen)"
