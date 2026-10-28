---
titel: Langsame Fahrzeuge decken Umwege auf – Routenlänge (rem) im Log prüfen
bereich: baustelle
datum: 2026-10-29
pruefung: e2e:fahrzeuge
---

**Was passiert ist:** Meldung #24. Der Nooteboom lud den Raupenbagger R 938 hinter der Absperrung ab. Danach fuhr der Bagger nicht die ~20 m rückwärts in seinen Platz, sondern mit 5,3 km/h 1,2 km um den Block (`Raupenbagger 1 driving Fährt nach Auftrag 1 … rem=1224.4`). Im gerenderten Lauf dauerte das bis nach Mitternacht, das „Tag“-Bild vom Graben entstand um 00:58. Beim Mobilbagger nach dem Tieflader-Test war es genauso (`rem=711.3`), fiel bei 20 km/h aber nicht auf.

**Ursache:** `Site._go_slot` und `_go_stage` haben einen Sonderweg „steht schon hinter der Baustelle → direkt rückwärts hinein“. Die Prüfung `_behind_site` verlangte die Fahrzeugmitte hinter `tail_s()`. Eine rückwärts von der Rampe gefahrene Maschine steht aber mit dem Heck im Auslauf der Absperrung (Mitte ≈ `tail_s() + 1 − front_ext`). Also fiel sie durch, und der Router plante den Weg über das Straßennetz.

**Regel:**
- Hinter der Arbeitszone (`tail_s() − TAPER_OUT`) genügt für den direkten Weg.
- Bei neuen oder geänderten Abläufen mit Fahrzeugen die `rem=`-Werte im e2e-Log ansehen. Ein Ziel in Sichtweite mit mehreren hundert Metern Route ist ein Fehler, auch wenn der Test grün ist.
- Das Szenario `fahrzeuge` misst jetzt den größten Abstand des R 938 von der Baustelle zwischen Abladen und Arbeitsplatz (< 80 m).
- Zeitabhängige Bilder (Tag/Nacht) setzen die Uhr selbst, statt sich auf den Ablauf zu verlassen.
