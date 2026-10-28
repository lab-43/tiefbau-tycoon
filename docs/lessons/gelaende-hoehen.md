---
titel: Weltpunkte immer mit Geländehöhe, Kartenebenen bekommen ihre Tiefe pro Pixel
bereich: karte
datum: 2026-10-28
pruefung: lint:gelaende-hoehen und e2e:gelaende
---

**Was passiert ist:** Meldung #8 (Gelände in 3D). Das ganze Spiel ging von y = 0 aus: Verkehr (`Geo.v3(p, 0.05)`), Fahrzeuge (`p.y = 0.0`), Baustelle (`Vector3(c.x, SiteTerrain.Y_ROAD - job.depth + 0.05, c.y)`, 22 Stellen in `site.gd`), Zentrale, Kamera (Ebene y = 0), Markierungen (#7, `Vector3(lc.x, 10.0, lc.y)`), Sofort-Absperrung im Debug-Menü. Die Lint-Regel fand nach dem Rebase zwei Stellen aus #7 und #6, die ich übersehen hätte. Die flachen Kartenebenen liegen nur 1–20 mm übereinander (Lektion kartenebenen-ueber-boden). Mit groben Dreiecken auf einem Hang hätten sie sich überdeckt.
**Ursache:** Höhen waren nirgends zentral, jede Stelle setzte y selbst.
**Regel:**
- Höhe nur über `Terrain`: `Terrain.at(p)` (Boden), `Terrain.near(p, y)` (Boden oder Brückendeck, je nachdem was näher an y liegt), `Terrain.piece_y(piece, p)` (Routenstück), in der Baustelle `Site.gw(p, y)`. Auf flachen Karten liefern alle 0.
- Kein `Vector3(p.x, <Zahl>, p.y)` für Orte auf der Karte. Richtungen dürfen so gebaut werden (Lint kennt die üblichen Namen, sonst `# lint-ok`).
- Neue flache Kartenebenen: Shader mit `t_off` im Vertex-Shader und `DEPTH = terrain_depth(...)` (Vorbild `ground.gdshader`). Die Tiefe kommt dann aus der exakten Geländehöhe pro Pixel, nicht aus den Dreiecken. Ebenen über 0,6 m (Brückendecks) behalten ihre eigene Tiefe.
- CPU-Meshes auf der Karte: `MeshLayer.terrain = Terrain.cur` hebt jeden Punkt an und schneidet große Flächen in 20-m-Zellen.
- Wasser liegt flach. Seine Böschung liegt innerhalb der Wasserfläche und wird im Wasser-Shader überdeckt (`water_depth`). Sonst folgt das Ufer dem 5-m-Raster und franst aus (mit echten Hamburg-Daten gesehen).
