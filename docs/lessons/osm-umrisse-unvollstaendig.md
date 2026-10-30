---
titel: Umrisse am Kartenrand kommen abgeschnitten und offen an – Nähe statt Punkt-im-Polygon
bereich: karte
datum: 2026-10-30
pruefung: e2e:bruecken
---

**Was passiert ist:** Meldung #32. Große Brücken erkennt das Spiel am Brückenumriss (`man_made=bridge` mit `bridge:structure=cable-stayed` oder `suspension` – die Köhlbrandbrücke ist in OSM als `suspension` eingetragen, obwohl sie eine Schrägseilbrücke ist). Auf Jonathans Karte (4 × 4 km) wurde sie trotzdem nicht als große Brücke erkannt: Ihr Umriss ist ein geschlossener Weg (147 Punkte), der über den Kartenrand hinausreicht. Der Parser schneidet Wege am Rand ab und behält das längste Stück innen – offen. Die Prüfung verlangte einen geschlossenen Ring, danach sagte `Geometry2D.is_point_in_polygon` für Fahrbahnpunkte nahe der offenen Seite „außerhalb“.
**Ursache:** Was am Kartenrand abgeschnitten wird, ist kein Polygon mehr. Bei Relationen aus Auszügen (Geofabrik, `osmium extract`, Overpass-Ausschnitte) fehlen außerdem manchmal Ringteile.
**Regel:**
- Umrisse, die nur als Hinweis dienen, auch offen übernehmen (ab 3 Punkten) und mit Abstand prüfen (hier: Fahrbahn höchstens 25 m vom Umriss oder darin), nicht nur mit Punkt-im-Polygon.
- Bei Tags auf mehrere gleichwertige Werte prüfen (`cable-stayed` und `suspension`), OSM ist hier nicht genau.
- Der Test prüft ein bekanntes Beispiel mit echtem Umriss (Köhlbrandbrücke in `testdata/bruecken`).
