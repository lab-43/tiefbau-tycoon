---
titel: Große Dateien zum PC in 10-MB-Teilen über stagedPath
bereich: pc-bruecke
datum: 2026-10-27
pruefung: manuell
---

**Was passiert ist:** `device_commit_files` mit `stagedPath` scheiterte bei einer 28-MB-Datei mit HTTP 400.

**Was funktioniert (28.10.2026 geprüft):**
- Teile von 10 MB mit `stagedPath` aus `/mnt/user-data/outputs/` gehen problemlos, bis 100 MB pro Aufruf.
- Das 233-MB-Daten-pck kam so in 3 Aufrufen an, ohne Dateikarten im Chat.

**Regel:**
- Dateien über 10 MB mit `split -b 10M -d -a 2` teilen und auf dem PC mit `cat teil?? > datei` zusammensetzen.
- Danach SHA256 vergleichen (`tycoon-dev/pc-bruecke.md`).
- `SendUserFile` + `fileUuid` nur, wenn Jonathan die Datei auch im Chat sehen soll.
