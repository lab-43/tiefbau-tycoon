---
titel: Workflow-YAML prüfen – kein „: “ in ungequoteten Ausdrücken
bereich: werkzeuge
datum: 2026-10-28
pruefung: lint:yaml-gueltig
---

**Was passiert ist:** In `.github/workflows/ci.yml` stand `if: … contains(…, 'Automerge: ja')` ohne Anführungszeichen. Wegen des „: “ im Text ist das ungültiges YAML. GitHub hätte den ganzen Workflow verworfen, die CI wäre also nie gelaufen. Aufgefallen ist es erst beim Parsen mit PyYAML.

**Regel:**
- `if:`-Ausdrücke als `"${{ … }}"` in Anführungszeichen schreiben.
- `tools/lint.py` parst alle `.yml`/`.yaml`-Dateien.
- Neue Workflows erst lokal parsen, bevor sie committet werden.
