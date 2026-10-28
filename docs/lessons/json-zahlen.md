---
titel: JSON-Zahlen sind float
bereich: godot
datum: 2026-10-27
pruefung: e2e: issue (gibt „ISSUE #1“ aus)
---

**Was passiert ist:** Die Meldungsnummer erschien als „#1.0“, weil `JSON.parse_string` jede Zahl als float liefert.

**Regel:** IDs und Zähler aus JSON immer mit `int()` umwandeln, bevor sie formatiert oder verglichen werden.
