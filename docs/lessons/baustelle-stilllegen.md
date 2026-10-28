---
titel: Fertige Baustellen stilllegen statt löschen
bereich: baustelle
datum: vor 2026-10-27 (MVP v1.3)
pruefung: e2e: job (prüft site.retired)
---

**Regel:**
- Fahrzeuge melden sich manchmal spät zurück, etwa wenn eine Route fertig berechnet ist oder ein Callback läuft. Eine sofort freigegebene Baustelle führt dann zu Zugriffen auf gelöschte Objekte.
- Deshalb wird die Baustelle mit `retired = true` stillgelegt.
- Callbacks prüfen `retired`.
