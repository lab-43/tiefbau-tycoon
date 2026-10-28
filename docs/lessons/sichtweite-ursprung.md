---
titel: visibility_range zählt vom Ursprung des Knotens – Meshes mit Weltkoordinaten an ihren Ort setzen
bereich: godot
datum: 2026-10-28
pruefung: e2e:sichtweite
---

**Was passiert ist:** Meldung #5: „Teilweise gibt es gar keine Markierungen“. Die Markierungen waren in den Daten, im Spiel aber nur bis etwa 900 m um die Kartenmitte (die Zentrale) zu sehen. Bordsteine verschwanden ab 1300 m, Gleise ab 1200 m. `MapBuilder.add_chunk_layers` legte jede Kachel als `MeshInstance3D` im Ursprung an, die Ecken in Weltkoordinaten. `visibility_range_end` (mark 900 m) misst Godot aber vom Ursprung des Knotens zur Kamera, nicht von der Geometrie. Bild: ohne die Grenze waren an der gemeldeten Stelle (1,4 km von der Mitte) alle Linien da.

**Ursache:** Das Mesh lag zwar an der richtigen Stelle, der Knoten aber in der Kartenmitte. Für Sichtweite (HLOD) zählt nur der Knoten.

**Regel:**
- Ein Mesh mit `visibility_range_*` muss an seinem Ort liegen: Knoten auf die Mitte der Geometrie setzen, Ecken relativ dazu (`Transform3D(Basis(), -c) * verts`, das läuft nativ).
- Shader nehmen die Weltposition aus `MODEL_MATRIX * VERTEX`, nie aus `VERTEX` allein, damit das Verschieben nichts ändert.
- `tools/test.sh sichtweite` (läuft auch bei `pbf`) prüft für alle Kacheln der Utrecht-Karte, dass Knoten und Geometrie höchstens eine Kachel auseinanderliegen.
