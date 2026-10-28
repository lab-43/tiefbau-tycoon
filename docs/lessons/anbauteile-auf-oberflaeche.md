---
titel: Anbauteile und Ladungen an der echten Modellform ausrichten, nicht an Bounding-Box und angenommenen Achsen
bereich: fahrzeuge
datum: 2026-10-28
pruefung: e2e:leuchten, e2e:verkehrslichter, e2e:schaufel
---

**Was passiert ist:** Meldung #1 – die beiden Rundumleuchten des Kolonnenbusses (Modell `van_crew`, ein Transporter ohne eigene Leuchten) schwebten in der Luft. `vehicle.gd` setzte sie fest auf `Vector3(±0.45, height + 0.02, -0.9)`. `height` ist `bbox_max.y` aus der Modell-JSON (2,02 m) – das ist aber die Antenne hinten auf dem Dach. Das Dach liegt bei 1,96 m, und bei z = −0,9 ist schon die schräge Windschutzscheibe (1,86 m). Die Leuchten hingen also knapp 20 cm über der Scheibe. Auf dem Screenshot vom PC fiel das auf, im Code nicht.

**Ursache:** Position aus Bounding-Box und geschätzten Maßen statt aus der echten Form des Modells. Die Bounding-Box sagt nichts darüber, wo an einer Stelle tatsächlich Oberfläche ist (Antennen, Spiegel, Schrägen).

**Regel:**
- Teile, die das Spiel selbst an ein Modell baut (Leuchten, Schilder, Halter), auf die Oberfläche setzen: `VehicleModels.surface_y()` / `roof_mounts()` schießen einen Strahl von oben auf die Dreiecke des Modells. Das Ergebnis je Modell zwischenspeichern.
- Keine festen Koordinaten für Modelle aus `assets/consim` – Jonathan ersetzt sie später durch eigene Modelle, dann stimmen feste Werte nicht mehr.
- Neues Anbauteil → in `e2e:leuchten` (oder ein eigenes Szenario) prüfen, dass es auf der Oberfläche sitzt (Abstand ≤ 6 cm), und einen Nah-Screenshot ansehen (Lektion screenshot-pruefen).

**Noch einmal (Meldung #2, Verkehrsautos):** `TrafficModels._add_lights()` setzte Front-, Rücklicht- und Blinkerkästen auf `±Länge/2` der Bounding-Box, symmetrisch um 0. Die Box enthält Spiegel und Stoßstange, ist nicht um 0 zentriert (Kleinwagen −1,89…+1,74 m), und die echten Leuchten sitzen zurückversetzt an der gerundeten Karosserie. Ergebnis beim MPV: Rückleuchten 34 cm hinter dem Heck, Frontleuchten mehr als 50 cm vor der Front. Im Spiel sah es Jonathan sofort, im Code fiel es niemandem auf.

**Regel (ergänzt):**
- Hat ein Modell eigenes Lampenglas (Materialien `*__light_head`, `__light_tail`, `__light_brake`, `__indicator_l/r`), dieses Glas leuchten lassen statt Teile anzubauen. Firmenfahrzeuge: `Vehicle._setup_lights()`, Verkehr: `carlamp.gdshader` (ein Material pro Modell und Funktion, Zustand pro Auto über `instance uniform lamp`).
- Fehlt das geteilte Glas im Asset, ist aber bekannt, wo es liegt, wird es beim Laden aufgeteilt (`LampSplit`: Polizei übernimmt das Glas des Kompakt-Pkw, Scania wird an den Lichtmarkern geteilt). Jonathan zur ersten Fassung mit Kästen: „passe es so an, dass man KEINE Flächen die rausgucken mehr zu sehen sind“.
- Kästen nur noch für die Ersatzmodelle ohne private Assets, dann an den Markern per Strahl auf die Oberfläche (`TrafficModels._on_surface`).
- Farbige Lampen: Emission ≤ ~2 (Lektion leuchten-nicht-ueberstrahlen).
- `e2e:verkehrslichter` prüft jedes Verkehrsmodell (Glas vorhanden oder Kasten ≤ 6 cm von der Karosserie) und schlägt mit dem alten Code an.

**Noch einmal (Meldung #11, Erde im Baggerlöffel):** `ExcavatorRig` setzte den Erdhügel in die Mitte der Bounding-Box der Schaufel und ließ ihn entlang der lokalen +Y-Achse wachsen. Beim Ersatzmodell (Kastenlöffel aus `VehicleModels._excavator`) zeigt +Y tatsächlich in die Öffnung, beim echten Liebherr-Löffel aber zur Rückwand. Ergebnis im Spiel: In jeder Stellung ragte eine braune Schale hinten aus dem Blech, von vorne sah man in eine leere Schaufel. Kein Test schaute auf die Ladung, und die Bilder ohne private Assets zeigen nur das Ersatzmodell.

**Regel (ergänzt):**
- Nicht nur die Position, auch die **Richtung** aus der Modellform bestimmen. Keine lokale Achse als „oben“ oder „Öffnung“ annehmen. `BucketLoad` findet die Öffnung über Schnitte quer zur Gelenkachse und Strahlen aus dem Hohlraum.
- Code, der am Ersatzmodell stimmt, ist für das echte Modell nicht geprüft: Die Ersatzmodelle haben andere Achsen und Formen. Sichtbares immer mit den privaten Assets ansehen (Bild).
- Ein Test für „liegt im Modell“ braucht eine **Gegenprobe**: Er muss die alte, falsche Platzierung erkennen (`tools/test.sh schaufel`: 90 von 169 Punkten hinter dem Blech). Sonst weiß man nicht, ob er überhaupt etwas prüft. Die Toleranz (hier 6 cm) begründen: Zahnhalter an der Schneide ragen ein paar Zentimeter in die Erde, das ist richtig so.
