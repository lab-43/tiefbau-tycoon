---
titel: Gespeicherte Straßenschlüssel beim Laden gegen die Lage prüfen – jede neue Kartenaufbereitung nummeriert die Straßen neu
bereich: baustelle
datum: 2026-10-28
pruefung: e2e:altstand
---

**Was passiert ist:** Meldung #23. Aufträge merken sich ihren Fahrstreifen als Schlüssel (`Job.key` = Kante << 4 | Richtung << 3 | Spur). Die Kanten sind die Reihenfolge im Straßennetz. Seit #5 (zusammengefasste Kreuzungen, Bögen) und #8 (Gelände) wird die Karte bei jeder neuen `BAKE_VERSION` neu aufbereitet, und die Nummern verschieben sich. Folgen beim Laden eines älteren Spielstands:
- Schlüssel fehlt: `SiteLayout.setup` griff ungeprüft auf `net.lane_geo[key]` zu. Im Editor war das ein Skriptfehler, und der Auftrag verschwand stillschweigend (Fahrzeuge „Abgestellt“). In der Windows-Release-Version war es ein Absturz beim Laden.
- Schlüssel gibt es, aber auf einer anderen Straße: Die Baustelle wäre an der falschen Stelle entstanden.
- Angebote mit altem Schlüssel ließen sich nicht annehmen.

**Ursache:** Ein Index in eine neu aufgebaute Datenstruktur wurde gespeichert, als wäre er eine feste ID.

**Regel:**
- Was auf das Straßennetz zeigt, braucht im Spielstand auch die Lage in Weltkoordinaten (`Job.center`). Beim Laden prüfen, ob der Schlüssel noch dorthin zeigt; sonst über die Lage neu zuordnen (`JobManager._relocate`: nächster Streifen, beide Richtungen, ≤ 2,5 m). Was sich nicht zuordnen lässt: Warnung im Spiel, nicht stillschweigend weglassen.
- Fremde Schlüssel nie ungeprüft als Index nutzen: zuerst `has()` bzw. Bereich prüfen (Lektion editor-binary: Release stürzt ab).
- Spurkoordinaten, die zu einem Schlüssel gehören (Verkehrsführung des Spielers, `plan.traffic`), passen nach einer Neuzuordnung nicht mehr. Sie werden auf automatisch zurückgesetzt.
- Wer `BAKE_VERSION` erhöht, lässt `tools/test.sh altstand` laufen. Der Test schreibt einen Spielstand mit fehlenden und falschen Schlüsseln und prüft, dass alle Aufträge an derselben Stelle wieder da sind. Mit dem alten Code schlägt er an (4 Fehler).
