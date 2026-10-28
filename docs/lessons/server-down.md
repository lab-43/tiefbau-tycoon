---
titel: Nicht erreichbare Server sofort aussortieren
bereich: netz
datum: 2026-10-27
pruefung: e2e: mock_overpass.py flaky
---

**Was passiert ist:** overpass.private.coffee antwortete nicht und bekam trotzdem immer neue Teile. Jedes Teil wartete auf das Zeitlimit.

**Regel:** Wer den Statuscheck nicht besteht, gilt als „nicht erreichbar“ und bekommt keine Arbeit, bis eine neue Prüfung (alle 60 s) gelingt. Fehlgeschlagene Teile gehen an einen anderen Server.
