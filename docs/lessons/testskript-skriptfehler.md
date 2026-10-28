---
titel: In Testskripten bricht ein Laufzeitfehler nur die Funktion ab – Prüfungen geben true zurück, dazu ein Wachhund
bereich: godot
datum: 2026-10-28
pruefung: manuell: Fehler in einer Wegwerf-Kopie einbauen, der Test muss FAIL melden
---

**Was passiert ist:** Eine Gegenprobe für `game/test/layer_test.gd` (#4) baute in `_check_meshes()` einen Zugriff auf einen fehlenden Dictionary-Schlüssel ein. Godot meldete `SCRIPT ERROR: Invalid access to property or key …`, brach aber nur `_check_meshes()` ab. `_initialize()` lief weiter, die Fehlerliste war leer, der Test meldete `EBENEN OK` mit Exit 0. Ein Fehler direkt in `_initialize()` erreichte dagegen nie `quit()`. Godot lief weiter, bis `timeout 300` es nach 5 Minuten beendete.
**Ursache:** Godot (ohne Debugger, `-s`) beendet bei einem Laufzeitfehler nur die laufende Funktion. Sie gibt den Standardwert zurück, der Aufrufer macht weiter.
**Regel:**
- Prüffunktionen in Testskripten geben am Ende `true` zurück. Der Aufrufer wertet alles andere als Abbruch: `if not _check(...): bad.append("… abgebrochen")`.
- Am Anfang von `_initialize()` einen Wachhund setzen: `create_timer(120.0).timeout.connect(_on_watchdog)`. Er meldet FAIL und ruft `quit(1)`, wenn ein `_done`-Flag (Member, keine Lambda-Variable) noch false ist.
- Jede neue Prüfung mit einer absichtlichen Verletzung in einer Wegwerf-Kopie gegenprüfen, auch mit einem eingebauten Skriptfehler.
- Bekannt, noch nicht umgestellt: `pbf_test.gd` und `rig_test.gd` haben das Muster ohne Wachhund. Bei einem Skriptfehler hängen sie bis zum Timeout.
