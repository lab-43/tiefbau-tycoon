---
titel: Routen zu Zielen hinter dem Fahrzeug
bereich: verkehr
datum: vor 2026-10-27 (MVP v1.3)
pruefung: e2e: job
---

**Was passiert ist:** Lag das Ziel auf derselben Kante hinter dem Fahrzeug, fand der Router keine Route.

**Regel:** Bei jeder Routing-Änderung den Fall „Ziel hinter mir, gleiche Kante“ testen. Der Router muss über die nächste Kreuzung wenden.
