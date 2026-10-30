---
titel: Ein Knick im Höhenprofil gehört auf eine Stützstelle – sonst schneidet die lineare Zwischenrechnung ihn ab
bereich: karte
datum: 2026-10-30
pruefung: e2e:bruecken
---

**Was passiert ist:** Meldung #32. Profile von Rampen liegen in gleichmäßigen 2-m-Stationen vor; dazwischen wird linear gerechnet. In der Kreuzungsfläche war das Profil flach (Abstand auf den Rand der Fläche geklemmt), ab dem Rand stieg es an. Der Knick lag zwischen zwei Stationen, die Zwischenrechnung traf am Rand der Kreuzungsfläche nicht deren Höhe: bis 0,11 m Stufe (Utrecht, 7 % Steigung), auf dem Waltershof-Gelände nur 0,035 m und deshalb lange unbemerkt.
**Ursache:** Stützstellen und Knickstellen unabhängig gewählt; der Fehler wächst mit Steigung × Stationsabstand.
**Erster Versuch, nicht genug:** Das Profil in der Kreuzungsfläche geradlinig fortsetzen. Damit stimmte der Rand nur, solange auf beiden Seiten derselbe Teil des Profils galt; wo eine andere Rampe oder eine Kuppe dicht dahinter übernahm, blieben bis 0,07 m (e2e `gelaende`, Grenze 0,05 m).
**Regel:**
- Stützstellen auf die Knicke legen: Die Stationen eines Straßendecks laufen jetzt gleichmäßig von Rand zu Rand der Kreuzungsflächen (`st0`/`st1` am Abschnitt, `s0` im Deck), außerhalb halten die Enden. Dann ist die Höhe an beiden Rändern exakt.
- Profile, die außerhalb des gezeichneten Teils weiterlaufen, dürfen nirgends als Oberfläche zählen (`Terrain._drawn`), sonst trifft ein Klick eine unsichtbare Fläche über der Kreuzung.
- Prüfungen auf mehreren Karten laufen lassen: Der Brückentest läuft deshalb auch auf Utrecht (flach, steile Rampen, viele kleine Brücken).
