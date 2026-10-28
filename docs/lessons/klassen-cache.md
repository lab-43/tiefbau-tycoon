---
titel: Neue class_name braucht einen Import-Lauf
bereich: godot
datum: 2026-10-27
pruefung: check (Hinweis in tools/check.sh)
---

**Regel:** Nach dem Anlegen einer Datei mit `class_name` einmal `godot --headless --path game --import` ausführen. Sonst melden andere Skripte „Identifier not declared“, weil `.godot/global_script_class_cache.cfg` veraltet ist.
