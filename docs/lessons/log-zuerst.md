---
titel: Bei Fehlern vom PC zuerst die Logs lesen
bereich: ablauf
datum: 2026-10-27
pruefung: manuell
---

**Was passiert ist:** Die Ursachen des Hamburg-Hängers (HTTP 307, blockierender Abbruch) wurden erst klar, als ich Jonathans `laden.log` direkt von seinem PC gelesen habe. Vorher waren es Vermutungen.

**Regel:**
- Logs liegen in `Tiefbau Tycoon/userdata/logs/spiel.log` und `userdata/maps/<karte>/laden.log`.
- Meldungen bringen ihre Logs selbst mit (`logs/` im Meldungsordner).
- Erst lesen, dann Hypothese, dann reproduzieren.
