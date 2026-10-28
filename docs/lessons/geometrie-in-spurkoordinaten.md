---
titel: Geometrie entlang einer Straße in Spurkoordinaten (s, seitlich) interpolieren, nicht als Gerade zwischen zwei Weltpunkten
bereich: baustelle
datum: 2026-10-28
pruefung: e2e:absperrung (Prüfpunkt „Platz für Bagger und Kipper frei“ mit einer Leitbaken-Kette über 26 m)
---

**Was passiert ist:** Im Absperrung-Designer (#9) setzte das Werkzeug „Gerade“ Leitbaken auf der geraden Linie zwischen zwei Klickpunkten an der linken Fahrstreifenkante (seitlich −1,15 m). Auf der Oude Pijlsweerdstraat (Utrecht) ist die Straße leicht gekrümmt: Die mittlere Bake stand bei −0,94 m, also im Platz des Baggers, und die Prüfung „Maschinenplatz frei“ schlug an. Auf dem Bildschirm sah die Linie gerade und richtig aus.

**Ursache:** Auch Straßen zwischen zwei Kreuzungen sind Polylinien mit kleinen Knicken. Eine Sehne über 10–30 m weicht schnell 0,2–0,5 m von der Spur ab – bei 3 m breiten Fahrstreifen und Maschinen mit 2,5 m Breite ist das zu viel.

**Regel:**
- Alles, was „entlang der Straße“ liegt (Absperrteile, Markierungen, Fahrwege, Stellplätze), in Spurkoordinaten rechnen: `SiteLayout.lane_coords(p)` → (s, seitlich), interpolieren, zurück mit `lane_pt(s, seitlich)`.
- Ketten im Designer: `ClosurePlan.lane_path(a, b, lay)` folgt der Spur, wenn beide Enden nah an Spur K liegen und die Kette ungefähr parallel läuft; sonst bleibt es die Gerade (z. B. quer über die Fahrbahn).
- Tests nicht nur auf schnurgeraden Straßen prüfen: Das Szenario `absperrung` nimmt die erste passende Straße der Utrecht-Karte, die gekrümmt ist.
