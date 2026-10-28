---
titel: Node-Namen ohne . : @ /
bereich: ui
datum: 2026-10-27
pruefung: manuell
---

**Was passiert ist:** Zeilen im Ladebildschirm hießen nach Server-URLs, deshalb fand `get_node()` sie nicht mehr. Godot ersetzt `.` und `:` in Namen.

**Regel:** Nur einfache Namen wie `Ep%d` verwenden. Die Anzeige läuft über Label-Texte, nicht über Namen.
