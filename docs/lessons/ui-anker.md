---
titel: set_anchors_preset() setzt die Offsets nicht
bereich: ui
datum: 2026-10-27
pruefung: lint:ui-anker
---

**Regel:**
- Godot 4: `set_anchors_preset()` ändert nur die Anker. Ohne passende Offsets landet das Element verschoben oder hat die Größe 0.
- Stattdessen `set_anchors_and_offsets_preset()` verwenden oder die Offsets direkt danach setzen.
- Danach immer einen Screenshot ansehen.
