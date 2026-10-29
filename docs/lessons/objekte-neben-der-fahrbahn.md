---
titel: Objekte aus echten Daten gegen die gezeichnete Fahrbahn prüfen – das Spiel schätzt Straßenbreiten, OSM-Positionen sind genau
bereich: karte
datum: 2026-10-29
pruefung: e2e:baeume
---

**Was passiert ist:** Meldung #30 „Bäume stehen auf der Straße“ (Bernadottestraße, Hamburg). Die Bäume kommen aus dem Hamburger Straßenbaumkataster in OpenStreetMap (`natural=tree` mit `ref:bukea`) und stehen dort zentimetergenau, meist im Parkstreifen zwischen den Buchten (`parking:both=street_side`) oder an der Bordsteinkante. `RoadNet._make_edge` zeichnet aber jeden Parkstreifen als durchgehenden Asphalt und schätzt Spurbreiten. Die Fahrbahn ist dadurch oft 1–2 m breiter als in echt, manche Straßen sind auch neben ihrer OSM-Linie versetzt. `CityMesher._trees` setzte die Bäume ohne jede Prüfung. Gemessen mit einem Wegwerf-Skript über `baked_v9.bin`: 2052 von 42 522 Bäumen standen auf Fahrbahn oder Kreuzungsfläche (an der gemeldeten Stelle 17 von 44), dazu 47 von 5881 Laternen. Zufällige Bäume in Parks und Wäldern landeten genauso auf Straßen, die durch die Fläche führen.

**Ursache:** Zwei Quellen mit unterschiedlicher Genauigkeit (echte Positionen gegen geschätzte Querschnitte) wurden nie gegeneinander geprüft.

**Regel:**
- Alles, was neben der Straße stehen soll (Bäume, Laternen, später Schilder, Poller …), gegen die gezeichnete Fahrbahn prüfen: `AsphaltIndex` (Fahrbahn zwischen den Kreuzungsschnitten, Kreuzungsflächen ohne Inseln, ohne Brückendecks).
- Echte Objekte nicht wegwerfen, sondern auf kürzestem Weg an den Rand rücken (`clear_spot`: 1 m hinter die Bordsteinkante, höchstens 5 m). Nur was tiefer steht, fällt weg. In Hamburg: 1664 gerückt, 125 weggelassen (0,7 %).
- Zufällige Objekte gar nicht erst auf Asphalt setzen und erfundene Straßenbäume nicht direkt neben echte (sonst stehen nach dem Rücken zwei Stämme beieinander).
- Inseln sind nur frei, wenn das Mesh sie wirklich ausschneidet. `MeshLayer.triangulate` fällt ohne Inseln auf den Umriss zurück, wenn das Verbinden der Löcher scheitert. Die Insel ist dann Asphalt (in Utrecht stand so ein Baum auf einer „Insel“ mitten im Asphalt). `AsphaltIndex._holes_cut` prüft das.
- Getestet wird gegen die Dreiecke des Asphalt-Meshes, also das, was der Spieler sieht, nicht gegen dasselbe Modell, das die Objekte setzt (`tools/test.sh baeume`, läuft auch bei `pbf`). Mit dem alten Stand meldet der Test 357 Bäume auf der Fahrbahn.
- Wer Breiten oder Querschnitte in `road_net.gd` ändert, sieht im Ladeprotokoll die Zeile „Bäume: … an den Rand gerückt, … weggelassen“. Steigt die Zahl stark, ist die Fahrbahn breiter geworden als die Wirklichkeit.
