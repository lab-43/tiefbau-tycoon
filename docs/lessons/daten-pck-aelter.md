---
titel: Ein anderer daten.hash heißt nicht „neuer“ – sind die eigenen privaten Assets älter, das Daten-pck auf dem PC lassen
bereich: pc-bruecke
datum: 2026-10-29
pruefung: manuell: vor dem Übertragen `ls game/assets/consim` im Container mit dem PC vergleichen und die Größe der Daten-pcks
---

**Was passiert ist:** Meldung #31. Beim Aktualisieren von `build/main` unterschied sich `daten.hash` (Container `921ba4d72b5aaef3`, PC `3a512aa3d18ac46b`). Nach der Regel „Daten-pck übertragen, wenn sich der Hash unterscheidet“ wäre das Container-pck (235 MB) über das des PCs (331 MB) gegangen. Die Assets im Container stammten aber vom Sessionstart; eine andere Session hatte inzwischen Raupenbagger R 938, Kompaktlader und Nooteboom-Tieflader (#24) auf dem PC ergänzt. Das Spiel hätte diese Modelle verloren. Derselbe Rückstand ließ im Container den Test `fahrzeuge` scheitern (Lichtmarker des Nooteboom-Sattelzugs), auf main genauso wie auf dem eigenen Branch.

**Ursache:** Der Hash sagt nur „anders“, nicht welche Seite neuer ist. Private Assets kommen nie über Git, jede Session hat den Stand ihres Sessionstarts.

**Regel:**
- Unterscheidet sich `daten.hash`, erst vergleichen: `ls game/assets/consim` hier und auf dem PC, Größe der Daten-pcks. Fehlt im Container etwas, nur Code-pck, `LIESMICH.txt`, `portable.txt` und `VERSION.txt` (mit `daten=` vom PC) übertragen, das Daten-pck des PCs bleibt.
- Für eigene Tests mit neuen Modellen zuerst `private/assets.tar` neu holen (Skill tycoon-dev).
- Ein roter Fahrzeugtest im Container erst auf main nachstellen, bevor man den eigenen Code verdächtigt.

**Nochmals (#33), andere Ursache:** Hash im Container `fe21eebc2190cb95`, auf dem PC `3a512aa3d18ac46b`, obwohl die Modelle gleich waren. Der Vergleich der Inhalte ohne `.import` ergab: Container 470 Dateien, PC 465. Der Unterschied war `bus_citaro`, nur im Container gab es zusätzlich `bus_citaro_0.jpg` … `_4.png`. Godot packt beim Import die eingebetteten Texturen dieses glb in den Ordner aus. Der PC importiert nie, deshalb fehlen sie dort. Der Hash in `tools/build.sh` zählt solche Dateien mit. Er kann sich also auch bei gleichen Modellen unterscheiden.
- Ein Vergleich, der etwas aussagt: Liste und Prüfsummen der `.glb`/`.json`/`.png` aus `private/assets.tar` (`tar -tvf`) gegen den Ordner auf dem PC. Sind sie gleich, nur das Code-pck übertragen und in `VERSION.txt` `daten=` vom PC eintragen.
