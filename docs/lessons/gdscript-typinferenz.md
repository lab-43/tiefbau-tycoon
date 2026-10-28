---
titel: `:=` nur mit eindeutig typisierten Werten
bereich: godot
datum: 2026-10-27
pruefung: check
---

**Was passiert ist:** Mehrfach scheiterte das Parsen mit „Cannot infer the type“ (`is_bus`, `force_overpass`, `q` in `_draw_pin`, `id`, `kind`). Auslöser waren Werte aus Dictionaries, untypisierten Arrays oder ternären Ausdrücken mit gemischten Typen.

**Regel:**
- Bei Variant-Quellen den Typ hinschreiben: `var id: int = int(d.get("id", 0))`.
- Danach `tools/check.sh` ausführen. Es kompiliert alles in 2 s.
