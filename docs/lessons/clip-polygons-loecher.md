---
titel: Geometry2D.clip_polygons gibt Löcher als eigene Polygone im Uhrzeigersinn zurück – wer sie wegfiltert, verliert das Loch
bereich: godot
datum: 2026-10-28
pruefung: manuell: tools/kreuzungen.sh, Spalte markierung_neben_m2 (Markierung über Inseln oder Boden) muss bei etwa 0 bleiben
---

**Was passiert ist:** Meldung #5, Etappe 4. Sperrflächen entstehen als „Kreuzungsfläche minus Fahrwege minus Inseln“. Am Burchardplatz lag eine Insel (77 m²) ganz innerhalb einer solchen Restfläche. Die Schraffur lief quer über die Insel, der Prüfstand zeigte 9,4 m² Markierung neben dem Asphalt. Zuvor hatte in Etappe 3 eine ähnliche Stelle (`_group_polygon`, Inseln nach dem Schneiden) nur deshalb funktioniert, weil die Löcher dort getrennt geführt werden.

**Ursache:** `Geometry2D.clip_polygons(a, b)` mit `b` vollständig in `a` liefert zwei Polygone: `a` unverändert (gegen den Uhrzeigersinn) und `b` als Loch (im Uhrzeigersinn). Der übliche Filter `if not is_polygon_clockwise(r)` behält nur die Außenkontur, das Loch ist weg. Dasselbe gilt für `merge_polygons` und `offset_polygon`.

**Regel:**
- Nach `clip_polygons`, `merge_polygons` oder `offset_polygon` prüfen, ob ein Ergebnis im Uhrzeigersinn läuft. Das ist ein Loch und muss mitgeführt werden (eigene Liste, beim Zeichnen ausschneiden, bei Flächen abziehen).
- Alternativ alles, was ganz innen liegen kann, nachträglich mit `intersect_polygons` gegen das Ergebnis prüfen und ausschneiden (so in `RoadMarkings.sperrflaechen`).
- Zeichnen auf Flächen mit Inseln: der Prüfstand misst mit `markierung_neben_m2`, ob Markierung auf Boden oder Inseln liegt.
