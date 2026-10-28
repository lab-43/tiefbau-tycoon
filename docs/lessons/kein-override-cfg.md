---
titel: Kein override.cfg mit Pfaden ausliefern
bereich: build
datum: 2026-10-27
pruefung: lint:kein-override-cfg
---

**Was passiert ist:** `override.cfg` sollte das Engine-Log umleiten und enthielt dafür einen absoluten Windows-Pfad. Unter Linux brach Godot damit ab, und auf anderen PCs wäre es genauso gekommen.

**Regel:**
- Protokolle schreibt `GameLogger` (`OS.add_logger`) nach `<data>/logs/spiel.log`.
- Es gibt kein override.cfg im Repo und keins im Build.
