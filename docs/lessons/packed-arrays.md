---
titel: Packed*Array hat kein any()/filter()/map()
bereich: godot
datum: 2026-10-27
pruefung: check
---

**Was passiert ist:** `PackedStringArray.any()` existiert nicht, der Parse-Fehler kam erst beim Laden.

**Regel:** Schleife schreiben oder vorher in ein `Array` umwandeln (`Array(psa)`).
