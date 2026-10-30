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

**Nachtrag (unabhängige Prüfung):** Die Tests waren grün, trotzdem fand der Prüf-Agent einen echten Fehler: `ExcavatorRig.material_cycle(…, drop_h)` behandelte `drop_h` als Höhe über der Maschine, die Baustelle übergab aber `drop.y` bzw. `Terrain.at3(…) + 0,6`, also Welthöhen. Auf flachen Karten ist beides gleich, deshalb fiel es im Auftragstest (flach) nicht auf; am Hang hätte der Bagger Meter neben der Mulde ausgekippt. Ebenso übersehen: eine Kachel-„Antwort“, die in Wahrheit eine HTML-Seite ist, wurde gespeichert, und `--no-terrain` hätte die echte gespeicherte Karte durch eine flache ersetzt.
- Jede Funktion, die eine Höhe annimmt, sagt im `##`-Kommentar, ob es eine Welthöhe oder eine Höhe relativ zu etwas ist. Beim Umstellen auf Gelände jeden Aufrufer prüfen, nicht nur die Stellen mit `y = 0`.
- Heruntergeladene Binärdaten vor dem Speichern am Dateikopf prüfen (PNG/WebP), nicht nur an Status 200 und Größe.
- Schalter, die das Ergebnis verändern (Testdaten, Abschalten), bekommen eigene Cache-Dateien.

**Nachtrag (Brücken an echten Ufern):** Das Testgelände (künstliche Hügel, Utrecht) hat keine steilen Ufer an Brückenenden. Erst Bilder der Lombardsbrücke zeigten: Die Brückenfahrbahn hing am Land-Ende bis zu 2 m durch (der Übergang mischte die Bodenhöhe der Böschung ein), und Wasser lag als Dreiecke auf der Fahrbahn. Gemessen mit einem Wegwerf-Skript über `baked_v7.bin` (Deckhöhe gegen Boden entlang jeder Brücke): 69 von 405 Decks lagen stellenweise unter dem Boden.
- Bei Änderungen an Brücken oder Ufern echte Karten rendern, nicht nur das Testgelände (`--e2e=repro --views=…`, Prüfstelle Lombardsbrücke: `-405,-1722,45,-35,28|-357,-1700,45,-35,28|-426,-1584,220,-35,28` auf hamburg_1793191710).
- Vorher/nachher am selben Bild vergleichen: alter Stand in einem `git worktree`, gespeicherte Karte vorher beiseitelegen (gleiche BAKE_VERSION, gleicher Dateiname).
- Gespeicherte Testkarten (`baked_v<BAKE_VERSION>_syn.bin`) überleben Code-Änderungen mit gleicher BAKE_VERSION; `tools/test.sh gelaende` löscht sie jetzt vorher.

**Nachtrag (Rebase auf #9):** Die Absperrungs-Planung (#9) kam parallel auf main und setzte Höhen wieder fest (`Vector3(tp.x, 0.05, tp.z)`, Kolonnenbus mit y = 0, Draufsicht-Abbildung auf y = 0,06). Die Lint-Regel erkannte nur `Vector3(p.x, Zahl, p.y)`; sie erkennt jetzt auch `Vector3(p.x, Zahl, p.z)` (3D-Punkt flachgedrückt). Richtungen und Verschiebungen bekommen `# lint-ok`. Die Draufsicht ist orthografisch: Die Kartenebenen-Shader rechnen die Tiefe jetzt auch dort pro Pixel (Strahl entlang der Blickrichtung), vorher nur in der Perspektive.

**Nachtrag (#32, Brücken bis 55 m):** `CameraRig.terrain_hit` begann seinen Strahl 12 m über dem höchsten Boden (`info.max`). Brücken darüber (Köhlbrandbrücke 55 m über dem Wasser) waren für die Maus unsichtbar, der Klick traf das Wasser darunter. Der e2e-Test `gelaende` fiel erst auf, als auch flache Karten Brückenhöhen bekamen. Wer neue Höhen einführt, sucht alle Stellen, die einen Höhenbereich annehmen (`info.get("max"`, feste Obergrenzen): jetzt `info.top` = höchste Fläche samt Brücken.
