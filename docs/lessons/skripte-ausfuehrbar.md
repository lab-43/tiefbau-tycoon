---
titel: Skripte im Git ausführbar speichern
bereich: werkzeuge
datum: 2026-10-28
pruefung: lint:skripte-ausfuehrbar
---

**Was passiert ist:** `tools/agent/merge.sh` und `session_start.sh` lagen mit Modus 100644 im Git, weil sie erst nach `git add` ausführbar gemacht wurden. In einem frischen Klon hätte `tools/agent/merge.sh` mit „Permission denied“ abgebrochen. Gefunden hat es die unabhängige Prüfung.

**Regel:**
- Neue Skripte mit `chmod +x` anlegen, dann erst `git add`.
- Sonst nachträglich `git update-index --chmod=+x <datei>`.
- `tools/lint.py` prüft alle `.sh`-Dateien und `tools/agent/*.py`.
