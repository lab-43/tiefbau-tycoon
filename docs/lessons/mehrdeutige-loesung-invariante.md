---
titel: Mehrdeutige Geometrie-Lösungen nach einer Invariante wählen, nicht nach Nähe zum letzten Bild
bereich: fahrzeuge
datum: 2026-10-28
pruefung: e2e:rig (tools/test.sh rig)
---

**Was passiert ist:** Meldung #3: Beim Mobilbagger lief die Kolbenstange des Schaufelzylinders durch das Schaufelblech, Umlenkhebel und Lasche hingen falsch. `ExcavatorRig._solve_fourbar()` schneidet zwei Kreise (Viergelenk am Löffel) und nahm von den zwei Schnittpunkten den, der am nächsten am Gelenkpunkt des letzten Bildes lag. `setup()` springt aber sofort von der Ruhepose in die Fahrstellung (ganzer Arm bewegt sich um Meter). Nach diesem Sprung war der „nächste“ Punkt der gespiegelte, und weil jede folgende Stellung wieder den nächsten nahm, blieb das Gestänge für immer auf der falschen Seite. Sichtbar erst aus der Nähe; kein Test prüfte das Gestänge.

**Ursache:** „Nächste Lösung zum letzten Bild“ setzt kleine, stetige Bewegungen voraus. Sprünge (setup, Laden eines Spielstands, Teleport, `reach_*` mit weit entferntem Ziel) brechen diese Annahme.

**Regel:**
- Bei zwei oder mehr Lösungen (Kreisschnitt, Kniegelenk, IK-Ellbogen) die Lösung über eine Größe wählen, die sich bei echter Bewegung nicht ändert, z. B. auf welcher Seite der Verbindungslinie der Punkt liegt. Den Wert einmal aus dem Modell in Ruhepose bestimmen.
- Vorher prüfen, dass die Größe wirklich unveränderlich ist: Beim Viergelenk wechselt die Seite nur, wenn B, C, D kollinear werden. Hier liegt |BD| in allen Stellungen zwischen 0,02 und 0,68 m, die Grenzen dafür wären 0,006 bzw. 1,17 m.
- Neues Gestänge oder Gelenk am Bagger: `tools/test.sh rig` laufen lassen, bei sichtbaren Änderungen mit `-- --shots=<dir>` (gerendert) die Seitenansichten ansehen.
- Nebenbei: `RigUtil.local_aabb(node)` zählt nur Kinder-Meshes, nicht den Knoten selbst. Für Zylinderhälften (`hyd_*_a/b` sind selbst Meshes) liefert es eine leere Box.
