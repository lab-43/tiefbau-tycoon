---
titel: Autos ruhig fahren lassen – Kurs aus der Sehne, Tempo aus dem engsten Bogen, und beides messen
bereich: verkehr
datum: 2026-10-28
pruefung: e2e:fahren
---

**Was passiert ist:** Meldung #5: „Sehr wackliges Fahren der Autos“. Auf `main` (Stand Etappe 2) zählte der neue Fahrtest 101,7 Rucke pro km und 13,5 zu schnelle Kurvenstellen pro km. Drei Ursachen:
1. Der Kurs des Fahrzeugs war die Tangente des aktuellen Segments. Jeder Knick in einer Spur (OSM-Knoten, Versatz-Schwalbenschwänze, Stückgrenzen) drehte das Auto in einem Schritt um bis zu 15°.
2. Das Kurventempo kam aus dem mittleren Radius des ganzen Abbiegewegs (Länge / Winkel). Bei Gerade–Bogen–Gerade ist der Bogen viel enger, bei S-Wegen ist der Gesamtwinkel 0. Die Autos fuhren mit 35–50 km/h durch Bögen von 5–20 m. Ein Tempo nur aus dem engsten Bogen für den ganzen Weg ließ sie dagegen 60 m lang kriechen.
3. In Kreuzungsgruppen gingen Straßen an einem Mitglied einfach weiter (2 → 3 Spuren), mit 0,6 m Rückschnitt. Der gerade Weg hatte 0,8 m Versatz auf 1,2 m Länge.

**Ursache:** Weg und Fahrverhalten wurden nie gemessen, nur die Geometrie auf Bildern angesehen.

**Regel:**
- Kurs = Richtung der Sehne zwischen den Routenpunkten 1,5 m hinter und vor dem Fahrzeug (`TrafficSim._smooth_dir`). Bei Rangierwegen (POLY, rückwärts, Wendepunkte) gilt die Tangente.
- Tempo nach Abschnitten: `Router.curve_profile` liefert für Abbiegewege und Spuren die Bögen mit v = √(2,8 m/s² · r). r wird über ±1,5 m gemessen (Spuren: ±6 m, damit kleine OSM-Knicke nicht bremsen). `_speed_cap` bremst mit 2 m/s² davor. Kein Stück-Tempo aus Mittelwerten.
- Wo Spuren seitlich springen, den Weg verlängern statt den Sprung zu glätten. An Übergängen (`_continuation_geometry`) und Durchgängen in Gruppen (`_pass_through_cuts`) ist der Rückschnitt 4 · Versatz + 1 m.
- Jede Änderung an Spuren, Abbiegewegen oder Fahrlogik mit `tools/test.sh fahren` prüfen (6 s). Dort zählt ein Ruck, wenn sich die Drehung pro Schritt um mehr als 2° ändert, und „zu schnell“ ab 4,5 m/s² quer. Mit `--v` stehen Ort und Stücktyp jedes Fundes im Log.
