---
titel: Skript-Tests (-s, extends SceneTree) kennen keine Autoloads – Tests mit Clock, Game oder Events als Szene starten
bereich: godot
datum: 2026-10-28
pruefung: lint:autoload-in-skripttests
---

**Was passiert ist:** Meldung #5, Etappe 3. Der neue Fahrtest (`game/test/drive_test.gd`) war zuerst ein `extends SceneTree`-Skript und erzeugte `TrafficSim.new()`. Ergebnis: `SCRIPT ERROR: Compile Error: Identifier not found: Clock (traffic_sim.gd:900)`. Weil das Skript dadurch nie `quit()` erreichte, hing der Prozess über zehn Minuten (fast ohne CPU), bis er abgebrochen wurde. `tools/check.sh` war grün, denn es kompiliert mit Autoloads.

**Ursache:** Mit `godot -s <skript>` werden die Autoloads nicht angelegt. Der GDScript-Analysator löst einen Autoload-Namen dort nur für Konstanten auf (`Balance.MATERIALS` geht). Dafür muss das Autoload-Skript selbst ohne andere Autoloads kompilieren: `Clock.SPEEDS` scheitert, weil `clock.gd` `Events` benutzt. Methoden, Variablen oder der bloße Name ergeben „Identifier not found“. Das gilt auch in jeder Klasse, die der Test benutzt (`TrafficSim` → `Clock.hour()`).

**Regel:**
- Ein Test, der Spielklassen mit Autoload-Zugriff braucht (Verkehr, Fahrzeuge, Baustelle …), läuft als Szene: `.tscn` mit einem `Node`-Skript, Start mit `godot --headless --path game res://test/<name>.tscn -- …`, Ende mit `get_tree().quit(code)`. Vorbild: `test/drive_test.tscn`.
- Jeden Test-Aufruf mit `timeout` starten. Ein Skriptfehler hält den Prozess sonst unbegrenzt am Leben.
- `tools/lint.py` meldet SceneTree-Tests, die ein Autoload benutzen oder eine Klasse, die eines braucht (eine Ebene tief).
