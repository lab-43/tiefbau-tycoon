---
titel: Ein Knick im Höhenprofil gehört auf eine Stützstelle – sonst schneidet die lineare Zwischenrechnung ihn ab
bereich: karte
datum: 2026-10-30
pruefung: e2e:bruecken
---

**Was passiert ist:** Meldung #32. Profile von Rampen liegen in gleichmäßigen 2-m-Stationen vor; dazwischen wird linear gerechnet. In der Kreuzungsfläche war das Profil flach (Abstand auf den Rand der Fläche geklemmt), ab dem Rand stieg es an. Der Knick lag zwischen zwei Stationen, die Zwischenrechnung traf am Rand der Kreuzungsfläche nicht deren Höhe: bis 0,11 m Stufe (Utrecht, 7 % Steigung), auf dem Waltershof-Gelände nur 0,035 m und deshalb lange unbemerkt.
**Ursache:** Stützstellen und Knickstellen unabhängig gewählt; der Fehler wächst mit Steigung × Stationsabstand.
**Regel:**
- Entweder Stützstellen auf die Knicke legen, oder das Profil über den Knick hinaus geradlinig fortsetzen, wo es ohnehin nicht gezeichnet wird (hier: in der Kreuzungsfläche, `f` ungeklemmt). Dann darf die Fortsetzung aber nirgends als Oberfläche zählen (`Terrain._drawn`), sonst trifft ein Klick eine unsichtbare Fläche über der Kreuzung.
- Prüfungen auf mehreren Karten laufen lassen: Der Brückentest läuft deshalb auch auf Utrecht (flach, steile Rampen, viele kleine Brücken).
