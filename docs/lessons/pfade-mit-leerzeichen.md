---
titel: Pfade mit Leerzeichen – auf dem PC heißt der Ordner „Tiefbau Tycoon“
bereich: pc-bruecke
datum: 2026-10-28
pruefung: manuell: tools/agent/test_issues.sh in der Geräte-Shell auf dem PC ausführen
---

**Was passiert ist:** `tools/agent/test_issues.sh` lief im Container grün, auf dem PC aber nicht („FAIL issues: create“). Das Skript stand in einer String-Variable (`P="python3 $ROOT/…"`), und der Pfad `…/mnt/Tiefbau Tycoon/…` zerfiel am Leerzeichen.

**Regel:**
- Pfade in Shell-Skripten immer in Anführungszeichen setzen.
- Befehle in Funktionen statt in String-Variablen ablegen.
- Was in der Geräte-Shell laufen soll (`issues.py`, `test_issues.sh`), einmal dort ausprobieren.
