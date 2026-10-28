---
titel: Eine echte Kreuzung besteht in OSM aus vielen Knoten – Straßengeometrie nie pro OSM-Knoten bauen
bereich: karte
datum: 2026-10-28
pruefung: manuell: tools/kreuzungen.sh vorher/nachher vergleichen (--compare), Spalten knoten, kurz, luecke_m, ueber_gehweg_m und die Bilder *_fehler.png
---

**Was passiert ist:** Meldung #5 zeigte zerrissene Kreuzungen, helle Zacken, fehlende Markierungen und wackelnde Autos. Ursache: `RoadNet` baute für jeden OSM-Knoten mit mindestens drei Straßen eine eigene Kreuzungsfläche. An der gemeldeten Stelle (Billhorner Brückenstraße) liegen 23 solche Knoten und 7 Ampeln in 120 m: getrennte Richtungsfahrbahnen, Abbiegestreifen, eine Wendeschleife. Dazwischen lagen Stummel von wenigen Metern. Die Rückschnitte wurden auf 45 % ihrer Länge gekappt, die Flächen überlappten sich oder ließen Lücken (die „Zacken“ waren der Boden, der durchscheint), und Autos fuhren durch 5–6 Mini-Kreuzungen.

**Ursache:** In OSM ist eine Kreuzung keine Einheit. Jede Richtungsfahrbahn ist ein eigener Weg, also hat jede Kreuzung zweier zweibahniger Straßen mindestens vier Knoten.

**Regel:**
- Knoten, zwischen denen nach dem Ausschneiden der Kreuzungsecken kein echtes Straßenstück übrig bleibt, gehören zu einer Kreuzung (`JunctionMerge`, Kreisverkehre ausgenommen, höchstens 70 m Ausdehnung).
- Welche Ausfahrt von welcher Einfahrt erreichbar ist, folgt den entfernten inneren Stücken in Fahrtrichtung. Nicht alles mit allem verbinden.
- Die Fläche einer zusammengefassten Kreuzung entsteht als Vereinigung (Sternpolygon, Eckkeile, innere Stücke, Straßenstummel, Abbiegewege mit 1,3 m Breite), dann 1 m schließen. Gehwege werden gegen diese Fläche geschnitten.
- Auf der Außenseite einer Biegung treffen sich die Bordsteine in einem Punkt hinter dem Rückschnitt (`_outer_corner`). Eine gerade Linie zwischen den Rückschnitten schneidet in die Fahrbahn, und der Eckgehweg liegt dann auf der Fahrspur.
- Jede Änderung an `road_net.gd`, `road_mesher.gd` oder `junction_merge.gd` mit dem Prüfstand vergleichen.
- Asphalt unter einem Gehweg sieht man nicht. Entscheidend ist `ueber_gehweg_m` (Fahrweg über erhöhtem Gehweg), dazu die Fehlerbilder.
