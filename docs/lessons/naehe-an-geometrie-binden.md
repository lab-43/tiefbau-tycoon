---
titel: „Steht da schon einer?“ an der Geometrie prüfen, nicht an einer Gruppen-ID
bereich: karte
datum: 2026-10-30
pruefung: e2e:bruecken
---

**Was passiert ist:** Meldung #32, Etappe 2. Damit Pfeiler nicht zu dicht stehen, verwarf `BridgeStructures` einen Pfeiler, wenn im halben Abstand schon einer „derselben Brückenkette“ stand. Parallele Richtungsfahrbahnen sind über Rampen und Kreuzungen meist eine Kette: Die Pfeiler der einen Fahrbahn strichen die der anderen. Waltershof: 35 Pfeilerstellen über 3 m Höhe stillschweigend gestrichen, ein 103 m langer Abschnitt ganz ohne Pfeiler. Gefunden hat es die unabhängige Prüfung, nicht der eigene Test (er zählte nur Abschnitte ohne irgendeinen Pfeiler und ließ jeden fünften durch).
**Ursache:** Die Ketten-ID beschreibt „hängt zusammen“, gemeint war „trägt dasselbe Deck“.
**Regel:**
- Abstands- und Doppelprüfungen fragen die Geometrie: Steht der vorhandene Pfeiler unter diesem Deck (`deck_ds(dk, p).x <= Halbbreite`)?
- Was still verworfen wird, wird gezählt und im Protokoll genannt, sonst fällt es nicht auf.
