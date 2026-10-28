---
titel: Größere Werkzeug- und Ablaufänderungen unabhängig prüfen lassen
bereich: ablauf
datum: 2026-10-28
pruefung: manuell: Prüf-Agent ohne Vorwissen, Bericht abarbeiten
---

**Was passiert ist:** Nach dem Aufbau von Skills, `merge.sh`, CI und `issues.py` waren lint und Tests grün. Eine unabhängige Prüfung durch einen frischen Agenten, der nur den Code bekam, fand trotzdem 20 Probleme. Drei davon waren kritisch:
- `tools/build/LIESMICH.txt` war nicht im Git.
- Eine private Mail-Adresse stand als Git-Identität in `.git/config`.
- Ein Skript war im Git nicht ausführbar.

Dazu kamen echte Wettlaufbedingungen bei Übernahmen. Eigene Tests prüfen meist nur, woran man selbst gedacht hat.

**Regel:** Bei Änderungen an Abläufen, Werkzeugen oder gemeinsam genutzten Daten einen Prüf-Agenten starten.
- Er bekommt den Code und die Frage, nicht die eigene Einschätzung.
- Die Funde werden belegt (nachstellen) und behoben.
- Wo möglich, wird aus jedem Fund ein Test oder eine Lint-Regel.
