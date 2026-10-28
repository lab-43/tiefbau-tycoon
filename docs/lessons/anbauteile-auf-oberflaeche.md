---
titel: Anbauteile auf die Modelloberfläche setzen, nicht auf die Bounding-Box
bereich: fahrzeuge
datum: 2026-10-28
pruefung: e2e:leuchten
---

**Was passiert ist:** Meldung #1 – die beiden Rundumleuchten des Kolonnenbusses (Modell `van_crew`, ein Transporter ohne eigene Leuchten) schwebten in der Luft. `vehicle.gd` setzte sie fest auf `Vector3(±0.45, height + 0.02, -0.9)`. `height` ist `bbox_max.y` aus der Modell-JSON (2,02 m) – das ist aber die Antenne hinten auf dem Dach. Das Dach liegt bei 1,96 m, und bei z = −0,9 ist schon die schräge Windschutzscheibe (1,86 m). Die Leuchten hingen also knapp 20 cm über der Scheibe. Auf dem Screenshot vom PC fiel das auf, im Code nicht.

**Ursache:** Position aus Bounding-Box und geschätzten Maßen statt aus der echten Form des Modells. Die Bounding-Box sagt nichts darüber, wo an einer Stelle tatsächlich Oberfläche ist (Antennen, Spiegel, Schrägen).

**Regel:**
- Teile, die das Spiel selbst an ein Modell baut (Leuchten, Schilder, Halter), auf die Oberfläche setzen: `VehicleModels.surface_y()` / `roof_mounts()` schießen einen Strahl von oben auf die Dreiecke des Modells. Das Ergebnis je Modell zwischenspeichern.
- Keine festen Koordinaten für Modelle aus `assets/consim` – Jonathan ersetzt sie später durch eigene Modelle, dann stimmen feste Werte nicht mehr.
- Neues Anbauteil → in `e2e:leuchten` (oder ein eigenes Szenario) prüfen, dass es auf der Oberfläche sitzt (Abstand ≤ 6 cm), und einen Nah-Screenshot ansehen (Lektion screenshot-pruefen).
