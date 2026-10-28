---
titel: .gitignore-Muster mit / verankern
bereich: werkzeuge
datum: 2026-10-28
pruefung: lint:gitignore-anker
---

**Was passiert ist:** Das Muster `build/` sollte den Build-Ordner im Wurzelverzeichnis ausschließen. Es traf aber auch `tools/build/`, sodass `tools/build/LIESMICH.txt` nie im Git war. In jedem frischen Klon wäre `tools/build.sh` nach dem kompletten Export am `cp` gescheitert.

**Regel:**
- Ordner der Wurzel mit führendem Schrägstrich ausschließen: `/build/`, `/userdata/`, `/private/`.
- `tools/lint.py` prüft, dass jede Datei, die ein Skript über `$ROOT/<pfad>` benutzt, im Git ist.
- Größere Änderungen an Werkzeugen in einem frischen Klon ausprobieren (`git clone <repo> /tmp/x`).
