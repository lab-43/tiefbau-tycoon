---
titel: Testdaten enthalten das ganze Bauwerk samt Zufahrten – sonst rechnet der Test eine abgeschnittene Welt
bereich: karte
datum: 2026-10-30
pruefung: e2e:bruecken
---

**Was passiert ist:** Meldung #32 (Brückenhöhen). Der erste Ausschnitt für `testdata/bruecken` war ein Quadrat von 2,4 km um die Mitte der Köhlbrandbrücke (wie die Karte von Jonathan). Im Test lag die Brücke nur 36 m hoch, auf Jonathans Karte 55 m. Grund: Die Höhe großer Brücken ist durch ihre Rampen begrenzt (Steigung × Länge bis zum Boden). Die Brücke ist mit Rampen 3,6 km lang und reicht nach Osten bis x = 2475 m; der Parser schneidet Wege am Kartenrand (`halbe_kante_m`) ab, also fehlte die halbe Ostrampe.
**Ursache:** Den Ausschnitt nach dem Ort gewählt, nicht nach der Ausdehnung des Bauwerks. Alles, was über Ketten von Abschnitten rechnet (Rampen, Brückenketten, Routen), hängt an Dingen außerhalb der Stelle, die man prüft.
**Regel:**
- Vor dem Zuschneiden die Ausdehnung des Prüfobjekts ausgeben (Wege mit dem Namen, Mittelpunkt und Rechteck in lokalen Metern) und den Ausschnitt so legen, dass es mit Zufahrten ganz drin liegt. `osmium extract --strategy complete_ways` holt Wege zwar ganz, aber nicht die Nachbarwege dahinter, und der Parser schneidet am Kartenrand trotzdem.
- Der Test vergleicht mit einem Wert, der auf der echten Karte gemessen ist (hier: Köhlbrandbrücke über 40 m), damit ein zu kleiner Ausschnitt auffällt.
- Höhenkacheln für die Testdaten müssen den ganzen Ausschnitt abdecken (Zoom 13: eine Kachel ≈ 2,9 km in Hamburg).
