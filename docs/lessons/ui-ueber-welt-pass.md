---
titel: Klickbare Controls über der 3D-Welt mit MOUSE_FILTER_PASS und nur den eigenen Klick annehmen – sonst schlucken sie Ziehen und Rechtsklick der Kamera
bereich: ui
datum: 2026-10-28
pruefung: e2e:markierungen
---

**Was passiert ist:** Die Kartenmarkierungen aus #7 (`world_markers.gd`) waren zuerst `MOUSE_FILTER_STOP` und haben Links- und Rechtsklick in `_gui_input` selbst behandelt. Eine unabhängige Prüfung fand:
- Godot 4.5 markiert jedes Maus-Ereignis als behandelt, das ein STOP-Control erreicht, auch wenn es nicht angenommen wird.
- Rechts ziehen (Karte verschieben), das auf einer Markierung beginnt, hat deshalb die Karte nicht bewegt, sondern sofort das gewählte Fahrzeug losgeschickt.
- Mittleres Ziehen über eine Markierung hinweg verlor Ereignisse.
- Fast unsichtbare Markierungen (Einblenden ab 280 m) fingen trotzdem Klicks.
- Das Mausrad ging durch, weil `mouse_force_pass_scroll_events` standardmäßig an ist. Die Vermutung der Prüfung, auch das Zoomen sei blockiert, war falsch (per Test nachgeprüft).
- Der erste Test rief `_gui_input()` direkt auf und konnte das nicht sehen.

**Ursache:** STOP beendet die Weitergabe an `_unhandled_input`, wo `CameraRig` und `World` die Maus auswerten. Die Unterscheidung „kurzer Rechtsklick“ gegen „Ziehen“ trifft erst die Kamera beim Loslassen.

**Regel:**
- Controls, die über der Karte liegen (Markierungen, Symbole), bekommen `MOUSE_FILTER_PASS` und rufen `accept_event()` nur für das, was sie selbst erledigen (hier: Linksklick). Alles andere läuft weiter zu Kamera und Welt.
- Ein Rechtsklick-Befehl auf so ein Control geht über die Welt: `World.marker_command(screen)` wird in `World._on_right_click` gefragt, nach einem aktiven Werkzeug und vor dem normalen Befehl.
- Ist ein aktives Werkzeug gesetzt (`World.tool`), nimmt das Control auch den Linksklick nicht an.
- Halb ausgeblendete Controls auf `MOUSE_FILTER_IGNORE` setzen.
- Eingaben in Tests über `get_viewport().push_input(ev, true)` schicken, nicht `_gui_input()` direkt aufrufen. Nur so wird die echte Weitergabe geprüft. Das Szenario `markierungen` prüft Mausrad, Rechts-Ziehen, Rechtsklick und Werkzeug; mit STOP schlägt es fehl (gegengeprüft).
- Das `true` ist Pflicht: Ohne es rechnet Godot die Position vom Fenster in den Viewport um. Headless ist der Viewport 1920×1920 und das Fenster nicht, die Klicks landen dann woanders. Im Szenario `absperrung` (#9) gingen so alle Klicks ins Leere, nur die Tasten wirkten.
