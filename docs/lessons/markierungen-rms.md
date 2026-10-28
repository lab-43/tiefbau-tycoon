---
titel: Markierungen nach RMS – Linien enden an der Haltlinie, laufen durch Übergänge, Sperrflächen nur auf ungenutzter Fläche
bereich: karte
datum: 2026-10-28
pruefung: manuell: tools/kreuzungen.sh (zweite Tabelle „Markierungen“, Spalte markierung_neben_m2) und Nahbilder der Kreuzungen
---

**Was passiert ist:** Meldung #5, Etappe 4. Markierungen gab es nur entlang einzelner Straßen: Linien brachen an jedem Übergang ab, in großen Kreuzungen fehlte alles, Haltlinien lagen auf der Furt, an Doppelknoten wurden Furten als X gezeichnet, Richtungspfeile und Sperrflächen gab es nicht. Beim Bauen fielen drei Fallen auf:
1. Die Mittellinie zwischen den linken Fahrwegen beider Richtungen sprang, wenn auf einer Seite eine Linksabbiegespur beginnt. Die Mittellinie hängt an den Straßen, nicht an den Spuren.
2. Sperrflächen als „Rest ohne Fahrweg“ schraffierten eine Rampe der Wendeschleife. Die Abbiegewege folgen in Gruppen nicht der OSM-Rampe, die Fläche war trotzdem Straße.
3. Eine Insel ganz innerhalb der Restfläche wurde mitschraffiert (Lektion clip-polygons-loecher).

**Regel:**
- Maße stehen als Konstanten in `RoadMarkings` (Schmalstrich 0,12, Breitstrich 0,25, Haltlinie 0,50, Wartelinie 0,50 mit 0,50/0,25, Leitlinie innerorts 3/6, im Knoten 1,5/1,5, Warnlinie 3/1,5, Pfeil 5 m bzw. 7,5 m). Wikipedia/RMS bestätigt Strichbreiten, Leitlinien und Haltlinie. Furt (0,50/0,20 Breitstrich), Wartelinie und Sperrflächen-Raster sind nach bestem Wissen gesetzt, nicht am Regelwerk geprüft.
- Längslinien enden an der Halt- oder Wartelinie. Diese liegt 0,6 m vor dem Spurende und mindestens 1 m vor einer Furt (`RoadMesher._end_line`). Über Zebrastreifen und Furten pausieren die Linien.
- Wo eine Straße nur weitergeht (`cont`, Durchgang in einer Gruppe), laufen die Leitlinien als Mittel der benachbarten Fahrwege durch. Die Mittellinie läuft von Straßenmitte zu Straßenmitte, ein Versatz wird 1:8 verzogen (`center_back`).
- Sperrflächen nur auf Fläche, die weder ein Fahrweg noch eine OSM-Straße noch eine Insel ist, und nur vor Inseln oder in schmalen Zwickeln (überall schmaler als 4 m, kaum Bordstein). Breite Restflächen bleiben frei.
- Nach jeder Änderung den Prüfstand laufen lassen und die Nahbilder ansehen. Die Zählung zeigt, ob etwas wegfällt, `markierung_neben_m2` zeigt, ob etwas auf Boden oder Inseln liegt.
