---
titel: Einen Netzabschnitt sperren heißt auch alle Fahrstreifen sperren, die nur in ihn hineinführen – sonst fährt der Verkehr in eine Sackgasse
bereich: verkehr
datum: 2026-10-28
pruefung: e2e:vollsperrung
---

**Was passiert ist:** Die erste Vollsperrung (#20) sperrte nur den Abschnitt (`edge`) der Baustelle. `_choose_conn` ließ an Kreuzungen keine Abzweige in gesperrte Abschnitte mehr zu. Das Szenario `vollsperrung` fand trotzdem 7 Autos auf der gesperrten Straße. Alle kamen über denselben Weg: Fahrstreifen 136 hat genau einen Ausgang, geradeaus in den gesperrten Fahrstreifen 120.

**Ursache:** Ein Abschnitt endet an jedem Knoten mit Abzweig oder Wechsel (Spurzahl, Name, Brücke – siehe Lektion osm-knoten-sind-keine-kreuzungen). Die Straße „zwischen zwei Kreuzungen“ besteht deshalb oft aus mehreren Abschnitten. Wer in den vorderen einbiegt, hat dort keine Wahl mehr.

**Regel:**
- Gesperrt sind die Fahrstreifen der gesperrten Abschnitte und jeder Fahrstreifen, dessen Ausgänge alle in gesperrte Fahrstreifen führen (`TrafficSim._rebuild_closed_lanes`, so lange wiederholen, bis nichts mehr dazukommt). Eine Wendemöglichkeit zählt als Ausweg.
- Abzweig-Wahl, Einsetzen neuer Autos und das Kürzen bestehender Routen prüfen gegen diese Fahrstreifen (`is_closed`), nicht gegen den Abschnitt.
- Tests zählen nicht nur „biegt niemand in den gesperrten Abschnitt“, sondern beobachten eine Weile, wer tatsächlich darauf fährt.
