---
titel: Alle Datenpfade über Game.data_path()
bereich: godot
datum: 2026-10-27
pruefung: lint:datenordner-portabel
---

**Regel:**
- Spielstände, Karten, Auszüge, Meldungen und Logs liegen dort, wohin `portable.txt` zeigt (`data=../../userdata`). Ohne Datei ist es `user://`.
- Nur `src/core/game.gd` kennt `user://`. Alles andere nutzt `Game.data_path("<unterordner>")`.
- So teilen sich `build/main` und `build/issue-<n>` dieselben Daten.
