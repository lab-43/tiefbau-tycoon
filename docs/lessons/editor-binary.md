---
titel: Mit dem Editor-Binary lässt sich kein Export-Verhalten testen
bereich: build
datum: 2026-10-27
pruefung: manuell
---

**Was passiert ist:** Der Test des portablen Modus war ungültig. Das Linux-Binary ist der Editor und hat das Feature „editor“, deshalb läuft er andere Pfade als die exportierte Windows-exe. Ein Linux-Export-Template ist nicht vorhanden.

**Regel:**
- Exportpfade über Schalter testbar machen (`--data-pack=`, `--main-pack`).
- Den Windows-Build auf Jonathans PC als „noch nicht unter Windows geprüft“ kennzeichnen, bis er es bestätigt.
