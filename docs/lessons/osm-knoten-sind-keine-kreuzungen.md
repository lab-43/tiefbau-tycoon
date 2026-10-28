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
- Die Fläche einer zusammengefassten Kreuzung entsteht als Vereinigung (Sternpolygon, Eckkeile, innere Stücke, Straßenstummel, Abbiegewege mit 1,3 m Breite), dann 2 m schließen (`CLOSE_R`). Gehwege werden gegen diese Fläche geschnitten.
- Auf der Außenseite einer Biegung treffen sich die Bordsteine in einem Punkt hinter dem Rückschnitt (`_outer_corner`). Eine gerade Linie zwischen den Rückschnitten schneidet in die Fahrbahn, und der Eckgehweg liegt dann auf der Fahrspur.
- Knoten mit nur zwei Straßen sind keine Kreuzung, sondern ein Übergang (Spurzahl, Gehweg, Name wechseln). Dort keine Kreuzungsfläche bauen, sondern abrunden und die Breite auslaufen lassen (`_continuation_geometry`). Sonst entstehen Stufen und Kerben (Etappe 2, 28.10.).
- Teile, die aneinanderstoßen, aus derselben Geometrie berechnen. Die Ecken der Kreuzungsfläche kamen aus einer Geraden in Richtung der ersten 6 m, die Straßenfläche aus der echten Mittellinie. An gekrümmten Zufahrten ergab das Stufen und Risse. Jetzt nimmt die Fläche Punkt und Richtung der Mittellinie an der Schnittkante (`inf.q`, `inf.qd`).
- Ein Schließen (wachsen, dann schrumpfen) darf keine Fläche verlieren. Godot nähert die Bögen mit Sehnen an, dadurch wurden konvexe Ecken um bis zu 1 m abgeschnitten (Kerben an jeder Einmündung). Danach mit dem Original vereinigen (Etappe 3).
- Etwas, das doppelt gezeichnet wird, kann Fehler verdecken. `o != best` verglich mit der schon geschlossenen Fläche, deshalb lag die ungeschlossene Fläche als „Extra“ noch einmal darunter. Sie deckte alle Inseln zu. Die Bank fand das erst, als eine echte Lücke durchkam.
- Ob ein Weg die Fläche verlässt, entlang des Weges prüfen (alle 2 m), nicht nur an seinen Punkten. Lange gerade Wege haben nur 4 Punkte und schneiden konkave Flächen dazwischen.
- Abbiegewege sind Gerade–Bogen–Gerade mit dem größten Radius, der passt. Wenn die Ausfahrt neben oder hinter dem Spurende beginnt, keine Kurve bauen, sondern eine gerade Linie. Die Kurve bildete sonst eine Schleife auf der Stelle.
- Jede Änderung an `road_net.gd`, `road_mesher.gd` oder `junction_merge.gd` mit dem Prüfstand vergleichen. Bei Spuren und Abbiegewegen zusätzlich `tools/test.sh fahren` (Lektion ruhig-fahren).
- Asphalt unter einem Gehweg sieht man nicht. Entscheidend ist `ueber_gehweg_m` (Fahrweg über erhöhtem Gehweg), dazu die Fehlerbilder.
