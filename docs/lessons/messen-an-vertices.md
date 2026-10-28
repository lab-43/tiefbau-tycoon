---
titel: Bodenkontakt und Abstände an den Dreiecken messen, nicht an der gedrehten AABB
bereich: godot
datum: 2026-10-28
pruefung: e2e:fahrzeuge
---

**Was passiert ist:** Meldung #24. Der neue Test prüfte, ob die geöffnete Rampe des Nooteboom-Aufliegers den Boden berührt, mit den acht Ecken von `mesh.get_aabb()` im globalen Raum. Ergebnis: Ende 0,42 m *im* Boden. Mit den Vertices (`mesh.get_faces()`) waren es 0,08 m, und das erklärt sich vollständig durch die Neigung des Aufliegers.

**Ursache:** Eine um 107° gedrehte, flache Rampe hat eine lokale AABB, deren Ecken nach der Drehung weit unter die echte Geometrie reichen. Die AABB ist nur in ihrem eigenen Raum dicht.

**Regel:**
- Für Boden-, Kontakt- und Abstandsprüfungen die Vertices transformieren (`mesh.get_faces()`), nicht die AABB-Ecken. `RigUtil.local_aabb()` ist nur für grobe Größen (Lasthügel, Abstände) gedacht.
- Abstand Punkt–Modell: `_dist_to_faces()` in `game/test/e2e_fahrzeuge.gd` (Box-Vorfilter + nächster Punkt auf dem Dreieck).
