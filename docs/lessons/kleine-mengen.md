---
titel: Kleine Restmengen nicht verlieren
bereich: baustelle
datum: vor 2026-10-27 (MVP v1.3)
pruefung: e2e: job
---

**Was passiert ist:** Kleine Kippmengen fielen durch Rundung und Schwellwerte weg, und die Baustelle wartete ewig auf Material.

**Regel:**
- Mengen mit Toleranz vergleichen.
- Reste übertragen oder ausdrücklich verwerfen.
- Unterwegs befindliche Ladungen mitzählen.
