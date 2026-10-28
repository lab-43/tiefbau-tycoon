---
titel: Geänderte Datei nie unter demselben stagedPath erneut zum PC schicken
bereich: pc-bruecke
datum: 2026-10-28
pruefung: manuell: sha256sum im Container und auf dem PC vergleichen
---

**Was passiert ist:** Meldung #2. `bus_citaro.glb` wurde aus `/mnt/user-data/outputs/bus_citaro/bus_citaro.glb` zum PC übertragen, dann im Container neu gebaut, an dieselbe Stelle kopiert und noch einmal mit `device_commit_files` geschickt. Die Antwort war „written“, die Datei auf dem PC hatte aber weiter die alte SHA256 (gleiche Größe, neue mtime). Die Brücke hatte den Inhalt zum gleichen `stagedPath` zwischengespeichert.

**Regel:**
- Jede neue Fassung unter einem neuen Namen oder Ordner in `/mnt/user-data/outputs/` ablegen (z. B. `…_v2`) und mit `devicePath` auf das Ziel schreiben.
- Nach jeder Übertragung die SHA256 im Container und auf dem PC vergleichen. „written“ allein reicht nicht.
- Wurde etwas an `private/assets.tar` angehängt (`tar -rf`), gilt beim Entpacken der letzte Eintrag. Nach dem Korrigieren also noch einmal anhängen und per `tar -xf … <datei>` mit SHA256 prüfen.
