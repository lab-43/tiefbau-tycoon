---
titel: Lange Arbeit nie im Hauptthread
bereich: godot
datum: 2026-10-27
pruefung: e2e: loadshot
---

**Regel:**
- Parsen, Aufbereiten, Speichern und Laden großer Karten laufen in einem Worker-Thread mit Fortschrittsmeldung (`MapBuilder`, `MapService`).
- Windows markiert ein Fenster nach etwa 5 s ohne Event-Verarbeitung als „Keine Rückmeldung“.
- Der Ladebildschirm muss immer zeigen, dass noch etwas passiert.
