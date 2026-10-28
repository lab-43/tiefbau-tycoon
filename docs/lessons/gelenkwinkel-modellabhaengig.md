---
titel: Gelenkwinkel aus der Animation eines Modells nicht auf ein anderes übertragen – Haltung über die Weltlage festlegen
bereich: fahrzeuge
datum: 2026-10-28
pruefung: e2e:schaufel (Löffel des R 938), e2e:rig
---

**Was passiert ist:** Meldung #24. Der Arbeitszyklus des Baggers (`ExcavatorRig.material_cycle`) ist auf den Mobilbagger A 918 abgestimmt: Löffel −88° zum Tragen, +55° zum Auskippen, als Gelenkwinkel ab der Ruhelage des Modells. Der R 938 hat eine andere Ruhelage (Löffel 40° anders zum Stiel) und einen 1,6-mal längeren Arm. Bei nahen Zielen hängt sein Stiel steil nach hinten, und derselbe Winkel drehte den Löffel kopfüber: Test `schaufel` meldete „Erde zeigt beim Tragen nicht nach oben (−0.17)“. Ein fester Versatz aus der Ruhelage half nicht (gleiches Ergebnis), weil der Stielwinkel je Ziel anders ist.

**Ursache:** Gelenkwinkel sind relativ zum Vorgängerglied und zur Ruhelage des jeweiligen Modells. Gleiche Zahlen bedeuten bei anderer Geometrie eine andere Haltung in der Welt.

**Regel:**
- Für ein Modell mit anderen Proportionen die Haltung in der Welt vorgeben, nicht den Gelenkwinkel: `bucket_world_zero_deg` in der Modell-JSON schaltet den Löffel des `ExcavatorRig` auf Weltlage (Tragen −88° = −161° in der Armebene wie beim A 918). Bestehende Modelle ohne den Schlüssel bleiben unverändert.
- Gelenkgrenzen des Modells bleiben die harte Grenze. Der R 938 schafft beim Auskippen höchstens 110°; bei 5 m / 2,5 m bleibt deshalb ein Rest im Löffel, bei seiner Kipphöhe (7 m / 4,2 m) nicht.
- Jedes neue Bagger-Modell in `rig_test.gd` (`--model=`) und `bucket_test.gd` aufnehmen. Prüfen, an welchen Punkten das Modell im Spiel wirklich arbeitet, und dort testen.
