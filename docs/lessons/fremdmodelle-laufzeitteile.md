---
titel: Construction-Simulator-Prefabs sind nicht das ganze Modell – Laufzeitteile nachbauen, Hilfsknoten aussortieren
bereich: fahrzeuge
datum: 2026-10-28
pruefung: e2e:fahrzeuge
---

**Was passiert ist:** Meldung #24 (neue Maschinen).
- Der Liebherr R 938 hatte im Prefab keine Ketten. `Tread_L/R` sind leere Knoten mit Kontrollpunkten `CP0000…`; die Kette setzt das Spiel zur Laufzeit zusammen (`WbSplineTrackVisuals`: Glied-Mesh „Track“ entlang einer geschlossenen CurvySpline). Ohne Nachbau stünde der Bagger auf Laufrollen in der Luft.
- Das Gestänge des R 938 (`WbRotateWithComponent`) nennt seine Gelenkpunkte nur über Verweise; der Mesh-Ursprung der Lasche saß am Löffelbolzen statt am gemeinsamen Gelenk.
- Hilfsknoten passten auf die Lichtregeln: `IndicatorTarget` (Kamera-Ziel) wurde beim tractor_tgx_heavy zu `indicator_sr2` 0,26 m vor der Kabine, `SwitcherComponent/Indicator` beim Kipper mit Kran zum Blinker. Mesh-Knoten `wheel_FL01` in den Rad-Pivots des Bobcat S550 drehte das Spiel als fünftes bis achtes Rad mit Radius 0,5 (Test: Rad 11 cm im Boden).
- Der Nooteboom-Auflieger stand im Prefab auf der Federung leicht schräg (vordere Achse 3 cm in der Luft).

**Ursache:** Das Prefab enthält nur, was als MeshFilter/Renderer hängt. Ketten, Schläuche, Rundumleuchten und Gestängelogik entstehen aus MonoBehaviours; UI-, Kamera- und Physikknoten tragen Namen, die wie Lampen oder Räder aussehen.

**Regel:**
- Fehlt sichtbare Geometrie oder ist ein Gelenk unklar: die MonoBehaviours der Knoten lesen (`read_typetree()`, Skriptname über `m_Script` → `m_ClassName`) und Verweise auf Knoten auflösen. Laufzeitteile im Build-Skript nachbauen (`_track_chain()` in `tools/consim_extract/build_assets.py`).
- Nach jedem neuen Modell prüft `e2e:fahrzeuge` (bzw. dieselben Funktionen aus `game/test/e2e_fahrzeuge.gd`): jedes Rad und jede Kette am Boden (≤ 5 cm), jeder Lichtmarker ≤ 10 cm an einem Dreieck des Modells, jede Rundumleuchte auf der Oberfläche. Ein Marker weit weg oder ein Rad im Boden heißt fast immer: ein Hilfsknoten wurde falsch erkannt.
- Hilfsknoten im Build ausschließen (`LIGHT_EXCLUDE`, `drop()`), Mesh-Knoten mit kanonisch wirkenden Namen umbenennen (`tyre_…`), Auflieger mit `_level()` gerade stellen.
- Ältere Builds (tractor_tgx, truck_traffic_scania) tragen noch einen solchen Marker; beim nächsten Neubau verschwindet er.
