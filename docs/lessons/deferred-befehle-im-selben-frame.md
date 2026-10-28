---
titel: Nach der Abnahme schickt das Spiel den Kolonnenbus per call_deferred heim – Befehle an ihn im selben Frame gehen verloren
bereich: baustelle
datum: 2026-10-28
pruefung: e2e:absperrung (wartet nach der Abnahme 5 s, bevor der Bus zur zweiten Baustelle fährt)
---

**Was passiert ist:** Das Szenario `absperrung` (#9) schickte den Kolonnenbus im selben Frame, in dem die erste Baustelle abgenommen wurde, zur zweiten Baustelle. Er kam dort nie an: `JobManager.finish_job()` ruft `van.drive_to_hq.call_deferred()`, das lief am Frame-Ende und überschrieb den neuen Auftrag. Der Test wartete 2400 s Spielzeit und meldete „Kolonnenbus kommt an Baustelle 2 nicht an“.

**Ursache:** `call_deferred` läuft nach allem, was im aktuellen Frame passiert – auch nach Befehlen, die später im selben Frame gegeben werden.

**Regel:**
- In Tests (und im Spiel, z. B. in Automatiken) nach einem Abschluss, der Fahrzeuge per `call_deferred` wegschickt, mindestens einen Frame warten, bevor man ihnen neue Ziele gibt.
- Wer selbst `call_deferred` für Fahrbefehle benutzt, prüft beim Ausführen, ob das Fahrzeug inzwischen etwas anderes zu tun hat (z. B. `v.site == null`).
