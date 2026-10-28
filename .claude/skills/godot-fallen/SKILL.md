---
name: godot-fallen
description: Use this skill before writing or changing GDScript, scenes, UI or networking code in the Tiefbau Tycoon Godot 4.5 project. It lists the engine pitfalls this project already ran into and the coding conventions that keep parallel sessions compatible.
---

# Godot-4.5-Fallen und Konventionen in diesem Projekt

Alle Punkte stammen aus echten Fehlern. Die Details und Belege stehen in `docs/lessons/`, der Slug ist in Klammern angegeben.

## Sofort-Check nach jeder Änderung

`tools/check.sh` (2 s, kompiliert alles mit Autoloads) und `python3 tools/lint.py`. Nach einer neuen `class_name` vorher `godot --headless --path game --import` (klassen-cache).

## GDScript

- **Typinferenz:** `:=` nur, wenn der Typ eindeutig ist. Bei Werten aus Dictionaries, untypisierten Arrays, `get()`, JSON oder ternären Ausdrücken den Typ hinschreiben: `var n: int = int(d.get("n", 0))` (gdscript-typinferenz).
- **void:** `return f()` in einer `-> void`-Funktion ist ein Fehler. `f()` und `return` als zwei Anweisungen schreiben (void-return).
- **Packed*Array** hat kein `any/all/filter/map/reduce`. Schleife schreiben oder `Array(x)` verwenden (packed-arrays).
- **JSON-Zahlen sind float:** IDs und Zähler mit `int()` umwandeln (json-zahlen).
- **Lambdas** fangen Variablen per Wert. Zähler, die das Lambda ändern soll, in ein Array oder Dictionary packen.
- `@onready` und `get_node` nur für Nodes, die im Baum sind. Die UI baut ihre Knoten in Code (`UI`-Kit in `src/ui/ui.gd`), nicht in .tscn.

## Engine

- **HTTPRequest:** nie `use_threads = true`, das blockiert den Hauptthread beim Abbrechen. Für große Downloads `download_chunk_size` auf 1 << 18 setzen (http-ohne-threads).
- **Weiterleitungen:** Godot folgt nur 301/302. Für 303/307/308 die Schleife aus `geofabrik.gd` verwenden (http-weiterleitungen).
- **Lange Arbeit** (Parsen, Aufbereiten, Speichern großer Daten) läuft in `Thread`/`WorkerThreadPool`. Fortschritt über Mutex und Polling, nie Nodes aus dem Thread anfassen (hauptthread-frei).
- **Controls über der 3D-Welt** (Markierungen): `MOUSE_FILTER_PASS`, nur den eigenen Klick mit `accept_event()` annehmen, Rechtsklick-Befehle über `World.marker_command`. STOP schluckt Ziehen und Rechtsklick der Kamera. In Tests `push_input` statt `_gui_input` (ui-ueber-welt-pass).
- **Node-Namen** ohne `. : @ / "`, sonst bricht `get_node` (node-namen).
- **Namen wiederverwenden:** vor `queue_free()` erst `remove_child()` (queue-free-namen).
- **`clip_polygons` / `merge_polygons` / `offset_polygon`** liefern Löcher als eigene Polygone im Uhrzeigersinn. Wer nur die gegen den Uhrzeigersinn behält, verliert das Loch (clip-polygons-loecher).
- **Skript-Tests (`-s`, `extends SceneTree`)** kennen keine Autoloads, auch nicht in den Klassen, die sie benutzen (`TrafficSim` → `Clock`). Solche Tests als Szene starten (`test/drive_test.tscn`), immer mit `timeout` – ein Kompilierfehler lässt den Prozess sonst hängen (autoload-in-skripttests).
- **Anker:** `set_anchors_preset()` setzt keine Offsets. `set_anchors_and_offsets_preset()` verwenden oder die Offsets direkt danach setzen (ui-anker).
- **Pause:** Simulation-Nodes pausieren mit dem Baum. UI, Welt-Input und der e2e-Treiber laufen mit `PROCESS_MODE_ALWAYS`.
- **Sichtweite:** `visibility_range_*` misst vom Ursprung des Knotens, nicht von der Geometrie. Meshes mit Weltkoordinaten an ihre Stelle setzen (sichtweite-ursprung, Test `sichtweite`).
- **Headless** (`--headless`) rendert nicht. Screenshots gehen nur mit `tools/gd.sh run` (xvfb + Vulkan). Viewport-Texturen sind headless leer.
- **Editor-Binary vs. Export:** Das Linux-Binary hat das Feature „editor“. Export-Verhalten (portable.txt, Daten-pck) über Schalter testbar machen, nicht über `OS.has_feature` (editor-binary).
- **Kein override.cfg** (kein-override-cfg). Logs schreibt `GameLogger`.
- **Mesh-Kompression:** `ARRAY_FLAG_COMPRESS_ATTRIBUTES` rundet Positionen auf 1/65535 der AABB. Für Millimeter-Abstände zwischen Ebenen ist das zu grob (mesh-kompression).

## Projektkonventionen

- **Datenpfade:** nur `Game.data_path("<sub>")`. `user://` steht ausschließlich in `game.gd` (datenordner-portabel).
- **Zahlen und Preise:** in `src/core/balance.gd`, nicht verstreut.
- **Kommunikation:** zwischen Systemen über `Events` (Signalbus), z. B. `Events.notify`, `site_changed` oder `request_focus`. Spielermeldungen mit `Events.info/ok/warn/error("…")` auf Deutsch.
- **Koordinaten:** `Vector2(x, z)` in Metern, x = Osten, z = Süden (Godot −Z = Norden). Spurkoordinaten (Schlüssel, s, seitlich) erklärt der Skill `spiel-architektur`.
- **Höhen:** Die Karte hat Gelände. Orte auf der Karte nie mit fester Höhe bauen, sondern `Terrain.at(p)`, `Terrain.near(p, y)` oder in der Baustelle `Site.gw(p, y)`. Flache Kartenebenen bekommen ihre Tiefe im Shader (`terrain_depth`) (gelaende-hoehen).
- **Speichern:** Jedes System hat `save_state() -> Dictionary` / `load_state(d)`. Neue Felder immer mit `d.get("feld", standard)` lesen, damit alte Spielstände laden. Das gilt auch für Spielstände aus Meldungen.
- **Spieltexte** sind deutsch; Kommentare und Bezeichner englisch.
- **Neue Klassen** bekommen einen `##`-Kommentar ganz oben: was die Klasse tut und wem sie gehört. `session_start` und Agenten lesen diese Zeile.
- **Einrückung mit Tabs** (Godot-Standard). Nichts umformatieren, was nicht zur Aufgabe gehört (parallele Sessions).
