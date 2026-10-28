---
titel: Auf dem PC-Mount nichts per tar überschreiben
bereich: pc-bruecke
datum: 2026-10-27
pruefung: manuell
---

**Was passiert ist:** `tar -x` konnte vorhandene Dateien im verbundenen Ordner nicht ersetzen. Ohne Löschrecht darf nichts gelöscht werden, und tar löscht vor dem Schreiben.

**Regel:**
- Einzelne Dateien mit `tar -xOf archiv member > ziel` ausschreiben.
- Alternativ einmal Löschrecht anfragen (`device_request_delete_permission`).
- Für git auf dem PC gilt dasselbe: ohne Löschrecht bleiben `.lock`-Dateien liegen.
