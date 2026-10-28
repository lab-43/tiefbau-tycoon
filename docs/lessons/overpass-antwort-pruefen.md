---
titel: HTTP 200 heißt bei Overpass nicht „fertig“
bereich: netz
datum: 2026-10-27
pruefung: e2e: mock_overpass.py big/flaky (Skill tycoon-dev)
---

**Was passiert ist:** Overpass liefert bei Zeit- oder Speicherüberschreitung HTTP 200 mit einem `remark` im JSON. Beim Auslesen dieses Texts wurde an einem escapten Anführungszeichen abgeschnitten, außerdem war der Offset falsch.

**Regel:**
- Antworten immer auf `remark` prüfen (`_check_json`).
- Zu große Kacheln teilen.
- Bei JSON-Strings Escapes beachten (`_json_string_after`).
