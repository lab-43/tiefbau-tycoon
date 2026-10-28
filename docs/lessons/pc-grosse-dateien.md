---
titel: Große Dateien zum PC: SendUserFile + fileUuid, max. 30 MB
bereich: pc-bruecke
datum: 2026-10-27
pruefung: manuell
---

**Was passiert ist:** `device_commit_files` mit `stagedPath` scheiterte bei 28 MB mit HTTP 400.

**Regel:**
- Größere Dateien erst mit `SendUserFile` hochladen, dann mit `fileUuid` committen.
- Grenze: 30 MB pro Datei. Darüber mit `split -b 25M` teilen und auf dem PC mit `cat` zusammensetzen.
- Danach SHA256 vergleichen (siehe `tools/agent/pc.md`).
