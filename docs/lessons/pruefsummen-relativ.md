---
titel: Prüfsummen mit relativen Pfaden erzeugen
bereich: pc-bruecke
datum: 2026-10-27
pruefung: manuell
---

**Was passiert ist:** SHA256SUMS enthielt Container-Pfade. Auf dem PC passte `sha256sum -c` deshalb nicht.

**Regel:** Vor `sha256sum` mit `cd` in den Ordner wechseln und relative Namen verwenden.
