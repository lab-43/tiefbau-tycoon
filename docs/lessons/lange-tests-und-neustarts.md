---
titel: Container-Neustarts brechen lange Hintergrundläufe ab – lange Szenarien einzeln mit Commit-Hash laufen lassen, dann zusammenführen
bereich: werkzeuge
datum: 2026-10-28
pruefung: manuell: Testprotokoll mit HEAD-Hash vor merge.sh, Hash im Meldungsverlauf nennen
---

**Was passiert ist:** In der Session zu #9 wurde der Container zweimal neu gestartet. Beim ersten Mal starb ein gerenderter Screenshot-Lauf, beim zweiten Mal `tools/agent/merge.sh --e2e=job,save+load,debug,absperrung,markierungen` mitten im Szenario `job`. Alle Hintergrundprozesse waren weg, eine Rückmeldung kam nicht, main war unverändert. Mit den langen Szenarien (job ~10 min, save+load ~6 min) in einem einzigen `merge.sh`-Lauf ging jedes Mal die ganze Testzeit verloren.

**Ursache:** Die Session-Container werden gelegentlich neu gestartet. Dateien im Repo und in `/tmp/claude-0` bleiben, laufende Prozesse nicht.

**Regel:**
- Lange Szenarien vorher einzeln laufen lassen und das Protokoll mit dem Commit festhalten: `git rev-parse --short HEAD > …/tested_head.txt; tools/test.sh job save+load …`.
- Danach `merge.sh` mit den kurzen Szenarien des eigenen Bereichs (es testet immer lint, check, smoke, issue). Die langen Tests gelten nur, wenn HEAD seitdem gleich geblieben ist. Den getesteten Hash in der Meldung nennen.
- Nach jedem Neustart als Erstes prüfen: `git status -sb`, laufender Rebase (`.git/rebase-merge`), Stand von `origin/main`. Upstream-Verfolgung kann fehlen („no remote branch“), dann `git config branch.<b>.remote origin` und `…merge refs/heads/<b>` setzen und die Branch-Refspec ergänzen.
- Temporäre Testhaken nie im Arbeitsbaum liegen lassen, wenn der Container neu starten kann: als Diff in `/tmp/claude-0` sichern und nach dem Lauf sofort zurücknehmen.
