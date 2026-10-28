# Lektionen

Eine Datei pro Lektion. Sie entstehen aus echten Fehlern und Umwegen in diesem Projekt (Skill `lernen`). Jede Session sieht die Liste beim Start (`tools/agent/session_start.sh`) und liest vor einer Änderung die Lektionen ihres Bereichs.

```
---
titel: <Regel in einem Satz>
bereich: netz | karte | godot | ui | build | baustelle | verkehr | fahrzeuge | pc-bruecke | werkzeuge | ablauf
datum: JJJJ-MM-TT
pruefung: lint:<regel> | check | e2e:<szenario> | manuell[: wie]
---

**Was passiert ist:** … (konkret, mit Datei/Fehlertext)
**Ursache:** …
**Regel:** … (was ab jetzt gilt)
```

- **Prüfung:** Wenn sich eine Lektion maschinell prüfen lässt, gehört eine Regel in `tools/lint.py` oder ein Test dazu. Dann `pruefung: lint:<name>`.
- **Lektionen pflegen:** Eine Lektion, die sich als falsch herausstellt, wird korrigiert, nicht gelöscht. Doppelte Lektionen werden zusammengelegt.
