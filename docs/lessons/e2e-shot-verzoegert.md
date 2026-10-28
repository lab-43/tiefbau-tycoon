---
titel: e2e-Bilder entstehen erst 8 Frames nach shot() – danach im selben Schritt nichts mehr an Kamera oder Auswahl ändern
bereich: werkzeuge
datum: 2026-10-28
pruefung: manuell: im Log von tools/gd.sh run nach „SHOT WARNUNG“ suchen (e2e_driver.gd meldet geänderte Kamera/Auswahl)
---

**Was passiert ist:** Im Szenario `markierungen` (#7) stand im selben Schritt erst `d.shot("markierungen_1_weit")` und direkt danach `camera_rig.set_view(…)` für den nächsten Prüfschritt. Das Bild „1_weit“ zeigte deshalb schon die neue Kamera, „3_baustelle“ zeigte die Lage nach `Game.select(null)` statt mit gewähltem Fahrzeug. Aufgefallen erst beim Ansehen der Bilder, die Prüfungen waren grün.

**Ursache:** `shot()` stellt das Bild nur in die Warteschlange (`shot_queue`, 8 Frames Vorlauf, damit Kamera und Schatten nachziehen). Alles, was danach im selben Frame passiert, landet im Bild.

**Regel:**
- Nach `shot()` den Schritt beenden. Kamera, Auswahl, Fenster erst im nächsten Schritt ändern; der nächste Schritt wartet mit `if not shot_queue.is_empty(): return`.
- `e2e_driver.gd` merkt sich beim Einreihen Kameraziel, Zoom und Auswahl und schreibt `SHOT WARNUNG <name>` ins Log, wenn sie sich bis zur Aufnahme geändert haben. Bei gerenderten Läufen das Log danach durchsuchen.
