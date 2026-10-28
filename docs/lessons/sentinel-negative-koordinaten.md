---
titel: Eine Hilfsfunktion mit „-1 = nichts gefunden“ nur mit Werten benutzen, die nie negativ sind – seitliche Abstände sind es oft
bereich: baustelle
datum: 2026-10-28
pruefung: e2e:vollsperrung
---

**Was passiert ist:** Für die Vollsperrung (#20) prüft `ClosurePlan._across_cover`, ob Absperrschranken die ganze Fahrbahnbreite abdecken. Dafür wurde `_first_gap(cov, a, b)` wiederverwendet. Das Szenario `vollsperrung` entfernte eine Schranke im Gegenfahrstreifen – die Prüfung meldete trotzdem „ganz gesperrt“.

**Ursache:** `_first_gap` liefert die Stelle der ersten Lücke oder `-1.0` für „lückenlos“. Bisher lief es nur über `s` entlang des Fahrstreifens, das ist nie negativ. Quer zur Fahrbahn liegt der Gegenfahrstreifen bei negativem seitlichen Versatz: Die Lücke bei −4,6 m sah aus wie „keine Lücke“.

**Regel:**
- Bevor eine Funktion mit einem Platzhalter-Rückgabewert (`-1`, `0`, `INF`) für neue Größen benutzt wird, prüfen, ob der Platzhalter in deren Wertebereich liegt.
- Seitliche Versätze (`lat`, `lane_coords().y`) sind links negativ. Für solche Prüfungen die Werte auf einen Rand beziehen (hier: ab dem äußeren Fahrbahnrand messen), dann bleiben sie ≥ 0.
- Jede Prüfung bekommt im Test auch den Fall „verletzt“ (hier: eine Schranke fehlt), nicht nur die Vorlage, die alles erfüllt.
