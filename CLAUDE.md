# Tiefbau Tycoon – Baustellen Manager

Privates Godot-4.5.1-Spiel (GDScript) von Jonathan: Tiefbau-/Straßenbau-Tycoon auf echten OpenStreetMap-Stadtkarten (Testgebiet Hamburg). Ziel-PC: Windows, GTX 1080 Ti.

## Erster Schritt jeder Session

`bash tools/agent/session_start.sh`. Der Lagebericht zeigt:
- Branch und neue Commits auf main,
- parallele Branches anderer Sessions,
- was an der Umgebung fehlt,
- alle Lektionen nach Bereich.

## Harte Regeln

1. **Private Assets:** Construction-Simulator- und FS25-Modelle (`game/assets/consim/`, `game/assets/barriers/`) und die Extraktionswerkzeuge (`tools/consim_extract/`, `tools/fs-i3d/`) sind nur für den privaten Gebrauch.
   - Nie committen, nie weitergeben.
   - `tools/lint.py` prüft das bei jedem Lauf.
2. **Spielordner tabu:** Niemals in `C:\Program Files (x86)\Steam\steamapps\common\Construction Simulator` schreiben.
3. **E-Mail-Adresse:** Jonathans Mail-Adresse geht an keinen Dienst. Auch nicht in User-Agents.
4. **Sprache:**
   - Spieltexte, Kommunikation mit Jonathan und Docs: Deutsch.
   - Code-Kommentare: Englisch, wie im bestehenden Code.
5. **Ehrlich bleiben:** Jonathan stört es, wenn Claude ihm einfach recht gibt. Widerspruch begründen, Unsicherheit benennen, Einschränkungen offen sagen.
6. **Andere Sessions:** Es arbeiten oft mehrere Sessions gleichzeitig am Repo. Vor jeder Arbeit den Skill `parallel-arbeiten` befolgen.

## Wo was liegt

| Pfad | Inhalt |
|---|---|
| `game/` | Godot-Projekt. `src/core` Zustand, Uhr, Meldungen · `src/map` Karte (Geofabrik/PBF, Overpass, Bake) · `src/nav` Routing · `src/traffic` Verkehr · `src/site` Baustelle · `src/vehicles` Fahrzeuge, Bagger-IK · `src/world` Welt, Kamera, Tag/Nacht · `src/ui` Oberfläche |
| `game/test/` | `e2e_driver.gd` (e2e-Szenarien; über `tools/test.sh`: smoke, issue, job, lowbed, save+load, pbf; direkt: repro, loadshot, retry, showcase), `compile_all.gd`, `mock_overpass.py`, `pbf_test.gd`, `layer_test.gd` (Höhen der Kartenebenen, Wasser über dem Boden, `tools/test.sh ebenen`, läuft auch bei `pbf`), `rig_test.gd` (Bagger-Gestänge, `tools/test.sh rig`), `drive_test.tscn` (ruhige Fahrt auf den Prüfstand-Kreuzungen, `tools/test.sh fahren`), `junction_bench.gd` (Kreuzungs-Prüfstand, `tools/kreuzungen.sh`), `bucket_test.gd` (Erde im Löffel, `tools/test.sh schaufel`) |
| `tools/` | `setup_env.sh` (neue Session), `lint.py` (Regeln aus Lektionen), `check.sh` (kompilieren), `test.sh` (e2e), `build.sh` (Windows-Build), `gd.sh` (Godot-Helfer, Screenshots) |
| `tools/agent/` | `issues.py` (Meldungen, Übernahmen – läuft in der Geräte-Shell auf dem PC), `merge.sh` (automatisch nach main), `session_start.sh` (Lagebericht), `fetch_templates.py` |
| `.claude/skills/` | Abläufe für Agenten (siehe unten), PC-Übertragung in `tycoon-dev/pc-bruecke.md` |
| `docs/` | Konzept, Umsetzungsstand (`MVP-Umsetzung.md`), `lessons/` (eine Datei pro Lektion) |
| `testdata/` | Utrecht-.osm.pbf für Tests |
| Jonathans PC: `C:\Users\Jonathan\Documents\Tiefbau Tycoon` | Git-Klon. Außerdem: Assets, `private/assets.tar`, `build/main` (aktuelles Spiel), `build/issue-<n>` (Testversionen), `userdata/` (Spielstände, Karten, **Meldungen**, Logs) |

## Skills – wann welchen laden

- `tycoon-dev`: Umgebung einrichten, Assets holen, bauen, testen, Screenshots, Build auf den PC liefern.
- `issue-ablauf`: wenn an Meldungen aus dem Spiel gearbeitet wird (holen, übernehmen, reproduzieren, beheben, zurückmelden).
- `parallel-arbeiten`: immer, bevor Code geändert wird (Branch, Sperren, Rebase, automatisches Zusammenführen).
- `godot-fallen`: vor Änderungen an GDScript. Bekannte Fallen dieses Projekts.
- `spiel-architektur`: um Systeme zu verstehen (Koordinaten, Verkehr, Baustelle, Karte).
- `lernen`: am Ende jeder Aufgabe. Lektion schreiben, Prüfung ergänzen.

## Definition of Done

Eine Aufgabe ist fertig, wenn:
- `python3 tools/lint.py` sauber ist,
- `tools/check.sh` keine Fehler meldet,
- das passende e2e-Szenario grün ist,
- bei sichtbaren Änderungen ein Screenshot angesehen wurde,
- der Branch nach `main` zusammengeführt ist (siehe `parallel-arbeiten`; bei Exit 5 erst nach `merge.sh --wait`),
- Jonathan einen Build hat (falls er etwas testen soll),
- die Lektion geschrieben ist (siehe `lernen`).
