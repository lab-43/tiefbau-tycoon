---
name: spiel-architektur
description: Use this skill to understand how the Tiefbau Tycoon game is built before changing a system. It covers game flow, map loading and baking, the road network and lane coordinates, traffic simulation, routing, vehicles and the excavator rig, construction sites and their work steps, jobs, HQ, UI and save/load. It shows which file owns what.
---

# Architektur – wer macht was

Spezifikation: `docs/Baustellen-Manager-Konzept-MVP.md`. Umsetzungsstand und Abweichungen: `docs/MVP-Umsetzung.md`. Jede Datei hat oben einen `##`-Kommentar; für einen schnellen Überblick:
`for f in $(find game/src -name '*.gd'); do echo "$f: $(grep -m1 '^##' $f)"; done`

## Ablauf

`scenes/main.tscn` → `src/main.gd`: Hauptmenü → Firmengründung (`setup_screen.gd`, Karte `map_picker.gd`) → Ladebildschirm → `World` + `HUD`. Ebenfalls dort: Fortsetzen/Laden, `--autostart`, e2e-Treiber, F8 (`IssueReporter`) und das Fenster „Meldungen“ (`IssueBrowser`).

Autoloads (`project.godot`):
- `Events`: Signalbus und Verlauf der Meldungen.
- `Balance`: alle Zahlen, Fahrzeugkatalog, Material.
- `Clock`: 1 Spielstunde = 2 min bei 1x; Stufen 0/1/3/10.
- `Game`: Firma, Geld, Karte, Auswahl, Speichern, Datenordner, Logger, Build-Info.

## Karte (`src/map/`)

- **`MapService`** organisiert alles: Cache prüfen → Daten holen → aufbereiten → Szene → speichern. Der Kartenordner ist `Game.data_path("maps")/<id>/`, mit `manifest.json` und `laden.log`.
- **Daten holen:**
  1. `GeofabrikSource` lädt den kleinsten passenden .osm.pbf-Auszug (MD5, 30 Tage Cache in `extracts/`).
  2. Rückfall ist `MapDownloader`: Overpass in 1-km-Kacheln, die bis 250 m geteilt werden, mehrere Server, Statusprüfung, Fortsetzen.
- **Lesen:** `PbfReader` (3 Durchläufe) oder `OsmParser.parse_dir` (Overpass-JSON) → `OsmData`, schon projiziert (`Geo`) und klassifiziert.
- **Aufbereiten** (`MapBuilder`, Worker-Thread):
  - `RoadNet` (Graph, Querschnitte, Kreuzungsflächen, Spuren, Abbiegebeziehungen, Konflikte, Ampeln/Vorfahrt),
    - `JunctionMerge` fasst die OSM-Knoten einer echten Kreuzung zu einem Knoten zusammen (`group`, `reach`), Fläche als Vereinigung (`_group_polygon`),
    - Knoten mit nur zwei Straßen sind Übergänge (`cont`): abgerundet, Breite und Gehweg laufen aus (`_continuation_geometry`),
    - Prüfstand für alles hier: `tools/kreuzungen.sh` (Skill tycoon-dev),
  - `RoadMesher` (Fahrbahn, Gehweg, Bordstein, Markierung),
  - `CityMesher` (Gebäude, Flächen, Wasser, Bäume, Laternen),
  - je Chunk ein `MeshLayer` pro Material aus `Mats`.
- **Koordinaten:** `Geo.to_local(lat, lon)` → `Vector2(x, z)`, x = Ost, z = Süd. Das Gelände ist flach (y = 0).
- **Spurschlüssel:** `edge*16 + dir*8 + lane`. Spur 0 ist die linke Spur in Fahrtrichtung. **Spurkoordinaten:** s = Meter entlang der Spur, seitlich + = rechts (Bordstein).

## Verkehr und Wege

- **`TrafficSim`** (`src/traffic/`): Mikrosimulation in festen 0,1-s-Schritten, Darstellung interpoliert.
  - IDM-Folgemodell, Ampelzyklen, Vorfahrt, rechts vor links, Busse an Haltestellen.
  - Sperrungen und Engstellen (Z 208/308 mit Fairness, Reißverschluss bei zwei Streifen gleicher Richtung).
  - Sicherungsbereiche halten den Verkehr an, wenn ein Fahrzeug rückwärts fährt.
- **`Agent`:** ein Verkehrsteilnehmer. Firmenfahrzeuge nutzen denselben Agent.
- **`Router`** (`src/nav/`): A* über den Spurgraph. Er liefert Stücke: LANE, BLEND (Spurwechsel), CONN (Kreuzung) und POLY (freie Linie abseits der Straße, z. B. in die Absperrung oder auf den Hof).

## Fahrzeuge (`src/vehicles/`)

- **`Fleet`** besitzt alle Firmenfahrzeuge: Kauf, Kennzeichen, Speichern.
- **`Vehicle`** ist ein Fahrzeug oder eine Maschine.
  - Zustände: parked, driving, waiting, working, loading, on_trailer.
  - `drive_plan(ziel, …)` plant und fährt durch den Verkehr.
  - Lichtautomatik, Kipper, Rampe, Ladung.
  - Tieflader-Logik: Bagger auf- und abladen.
- **`VehicleModels`** lädt `assets/consim/<id>/<id>.glb` + `.json` (Räder, Gelenke, Lichtmarker). Ohne Assets gibt es ein prozedurales Ersatzmodell.
- **`ExcavatorRig`:** IK über die echte Gelenkkette (turret, boom, boom2, stick, bucket) mit Viergelenk. `RigUtil` steuert die Hydraulikzylinder (look_at) und Teleskopstufen.

## Baustelle (`src/site/`)

- **`JobManager`** erzeugt Angebote auf geeigneten Straßen (rechter Streifen, Abstand zur Kreuzung, kein Zebrastreifen und keine Haltestelle). Aus einem angenommenen Auftrag wird eine `Site`. Er verwaltet auch Ablauf und Abrechnung.
- **`Job`:** Vertrag (Leitung, DN, Graben, Vergütung, Frist).
- **`SiteLayout`:** die gesamte Geometrie in Spurkoordinaten der gesperrten Spur K, also Schilder, Verziehung, Grube, Stellplätze (exc, load, van, stage, lowbed) und Ausweichspur K2.
- **`Site`** (größte Datei, Hotspot):
  - `STEPS` = scout → closure → dig → pipe → refill → asphalt → demob → teardown → acceptance.
  - `phase`, `running`, `status`, `progress`, `sub`.
  - Fahrzeuge melden sich an (`spot_of`, `in_place`), Material über `needs` (inklusive unterwegs befindlicher Ladungen).
  - Am Ende wird die Baustelle mit `retired` stillgelegt, nicht gelöscht (Lektion baustelle-stilllegen).
- **Debug-Menü (F3):** `src/debug/`. Wer einen Arbeitsschritt ändert oder neu baut, passt `DebugTools.finish_step` an, damit er sich sofort erledigen lässt, und prüft das mit `tools/test.sh debug`.
- **`SiteTerrain`:** Höhenraster (10 cm) mit Schichten Asphalt, Tragschicht und Boden. Die Grube wird gegraben und verfüllt.
- **`SiteProps`:** Absperrteile (FS25-Set, privat) und Schilder. **`Worker`:** Kolonne mit einfachen Animationen.

## Welt und Oberfläche

- **`World`** besitzt Karte, Umgebung, HQ, Verkehr, Fuhrpark, Aufträge, Lichter und die Kamera (`CameraRig`, Shapez-2-Stil).
  - `DayNight`: Sonne nach Breitengrad und Datum.
  - `LightPool`: echte Lichter an den nächsten Laternen.
  - `SignalHeads`: Ampeln.
  - `HQ`: Hof, Halle, Lagerboxen, Parkplätze.
- **`HUD`:** obere Leiste, linke Leiste (Aufträge, Fuhrpark, Finanzen, Hilfe, **Meldungen** mit Zähler) und Kontextfenster für Fahrzeug und Baustelle.
  - Stil: schwarz/weiß mit orangem Akzent (`UI`-Kit).
  - **`WorldMarkers`** (erstes Kind des HUD, also unter allen Fenstern): Markierungen für Zentrale, Baustellen, Ausschreibungen und Fahrzeuge, am Bildrand mit Pfeil; Leiste unten rechts mit Ansicht-Schaltern (H Markierungen, B Gebäude = Ebene `building` der Kartenkacheln). Der freie Bildbereich hängt an `HUD.LEFT_W`/`RIGHT_W`; wer dort Fenster ändert, prüft die Markierungen mit `tools/test.sh markierungen`.

## Speichern

- **Format:** `Game.save_data()` → Dictionary mit `version`, `company`, `map`, `ledger`, `clock`, `world` und `build`. Die Datei ist zstd-komprimiert über `store_var`.
- `World.save_state()` sammelt `fleet`, `jobs` (inklusive Sites mit Terrain) usw.
- **Laden:** Kopf anwenden → Karte laden → `World.load_state`. Erst werden die Fahrzeuge wieder an Baustellen gehängt, dann laufen die Abläufe weiter.
- Meldungen enthalten denselben Spielstand. Neue Felder deshalb immer abwärtskompatibel lesen.

## Meldungen (Issue-System)

- `IssueStore` (`src/core/issue_store.gd`) legt die Ordner an, schreibt den Verlauf und sammelt System- und Zustandsdaten.
- `IssueReporter` ist der F8-Dialog: Screenshot sofort, markieren, weitere Bilder, Spielstand, Logs.
- `IssueBrowser`: Liste, Verlauf, Antworten, Behoben/Nicht behoben.
- Agentenseite: `tools/agent/issues.py` (Skill issue-ablauf).
