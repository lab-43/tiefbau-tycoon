---
titel: Kein `return f()` in void-Funktionen
bereich: godot
datum: 2026-10-27
pruefung: check
---

**Was passiert ist:** `return _end(...)` in einer `-> void`-Funktion ist ein Parse-Fehler („A void function cannot return a value“), auch wenn `_end` selbst void ist.

**Regel:** `_end(...)` und `return` als zwei Anweisungen schreiben.
