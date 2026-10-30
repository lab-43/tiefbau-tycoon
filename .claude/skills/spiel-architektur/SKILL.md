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
    - Knoten mit nur zwei Straßen sind Übergänge (`cont`): abgerundet, Breite und Gehweg laufen aus (`_continuation_geometry`); dasselbe für Mitglieder einer Gruppe, an denen eine Straße einfach weitergeht (`_pass_through_cuts`, `_taper_piece`),
    - Abbiegewege: Gerade–Bogen–Gerade mit größtem Radius (`turn_path`), gerade Fahrt zur seitlich nächsten Spur (`_nearest_out_lane`),
    - Prüfstand für alles hier: `tools/kreuzungen.sh` (Skill tycoon-dev),
  - `RoadMesher` (Fahrbahn, Gehweg, Bordstein, Markierung entlang der Straßen, Halt-/Wartelinien) mit `RoadMarkings` (Linien durch Übergänge und Gruppen, Knotenpunkt-Leitlinien, Richtungspfeile, Sperrflächen; Maße nach RMS als Konstanten, Lektion markierungen-rms),
  - `CityMesher` (Gebäude, Flächen, Wasser, Bäume, Laternen); Bäume und Laternen nie auf die Fahrbahn: `AsphaltIndex` (`on_asphalt`, `clear_spot` rückt echte Bäume an den Rand, Lektion objekte-neben-der-fahrbahn),
  - je Chunk ein `MeshLayer` pro Material aus `Mats`.
- **Unter der Oberfläche (#31):** `RoadNet.is_under(tags)` – `tunnel=yes`, `indoor=yes`, Garagengassen/überdachte Zufahrten mit `layer<0` – setzt `edge.under`; Ketten unter 25 m bleiben oben (`MIN_TUNNEL`), Knoten nur mit Tunnelstraßen sind `node.under`, `JunctionMerge` fasst entlang Tunneln nicht zusammen. `building_passage` und Unterführungen ohne Tunnel-Tag bleiben oben. Gleise mit Tunnel-Tag oder `layer<0` stehen in `OsmData.under_rails`. Statt Fahrbahn entstehen die Ebenen `under_road`, `under_subway`, `under_rail` (nur Untergrund-Ansicht, `UndergroundView.is_layer`). Wo ein Tunnel auf die Oberfläche trifft, meldet der Mesher ein Portal bei `TunnelPortals` an; `MapBuilder` baut alle nach beiden Meshern (parallele Röhren als ein Bauwerk, Tiefe endet vor kreuzenden Straßen/Gleisen, Bäume und Laternen darauf entfallen). Prüfung: `tools/test.sh tunnel`.
- **Brücken (#32):** `BridgeHeights` (`src/map/bridge_heights.gd`) läuft in `MapBuilder` nach `RoadNet` und vor den Meshern, mit Gelände oder `Terrain.flat_for(bounds)`. Drei Netze (Straße = RoadNet-Kanten mit freier Länge zwischen den Kreuzungsflächen `trim_a/trim_b`, Bahn und Wege aus `OsmData`). Kreuzungen: Mittellinien schneiden sich und die Brücke liegt oben (`above`: layer, `*_link` über Hauptstraße, mehr Platz), dazu Wasserläufe und große Brücken (`OsmData.bridge_areas`, `man_made=bridge` mit `bridge:structure`). Nötige Höhe = Boden/Deck darunter + lichte Höhe (`clearance`, `maxheight`) + Bauhöhe (`DEPTH`). Höchstwert-Dijkstra über die Knoten mit Steigung je Klasse (`grade`, `descent`: auf steilerem Gefälle ein Viertel schneller als der Boden), gerundete Kuppen (`cone`), Herkunftskette gegen Selbstanhebung, bis 6 Runden. Ergebnis: `Terrain.decks[edge]` = Profil-Dict (`make_deck`: `h`, `g`, `lv` je Station; `deck_at` = max(lv, Boden), quer eben), `Terrain.node_decks/node_pos/node_poly` (Kreuzung eben auf Höhe, nie unter dem Boden; „angehoben“ heißt über dem tiefsten Boden ihrer Fläche samt Fahrbahnrändern; Umriss für `surface_near`), `info.top` (höchste Fläche, Startpunkt für `CameraRig.terrain_hit`), `CityMesher.rail_decks/path_decks`. `RoadMesher` baut Böschungen ab der Höhe am Fahrbahnrand (`_embankment`, `_junction_embankment`, Ebene `embankment`), `CityMesher` Böschungen unter angehobenen Gleisen und Wegen und Brüstungen auf Bahn- und Fußbrücken. `JobManager` legt keine Aufträge auf Decks. Prüfung: `tools/test.sh bruecken`.
- **Koordinaten:** `Geo.to_local(lat, lon)` → `Vector2(x, z)`, x = Ost, z = Süd.
- **Geländehöhen (#8):** `TerrainSource` lädt Höhenkacheln (Mapterhorn), `TerrainBake` macht daraus im Bake das 5-m-Raster `Terrain` (Wasser flach, Hof eben; Brückendecks setzt `BridgeHeights`). Höhe holen: `Terrain.at(p)` (Boden), `Terrain.near(p, y)` (Boden oder Brücke, je nachdem was näher an y liegt), `Terrain.piece_y(piece, p)` (Routenstück), in Baustellen `Site.gw(p, y)`. Kartenebenen-Shader rechnen die Höhe pro Pixel aus (`terrain_depth`); Fahrbahn, Gehweg und Markierung auf Brücken liegen in eigenen Ebenen `*_deck`, die nur angehoben werden (`terrain_depth_deck`). Mausklicks treffen mit `Terrain.top(p)` auch Brücken. Ohne Höhen (offline, Testkarte) ist alles 0. Neue Weltpunkte nie mit fester Höhe bauen (Lint-Regel gelaende-hoehen).
- **Spurschlüssel:** `edge*16 + dir*8 + lane`. Spur 0 ist die linke Spur in Fahrtrichtung. **Spurkoordinaten:** s = Meter entlang der Spur, seitlich + = rechts (Bordstein).

## Verkehr und Wege

- **`TrafficSim`** (`src/traffic/`): Mikrosimulation in festen 0,1-s-Schritten, Darstellung interpoliert.
  - IDM-Folgemodell, Ampelzyklen, Vorfahrt, rechts vor links, Busse an Haltestellen.
  - Sperrungen und Engstellen (Z 208/308 mit Fairness, Reißverschluss bei zwei Streifen gleicher Richtung).
  - Sicherungsbereiche halten den Verkehr an, wenn ein Fahrzeug rückwärts fährt.
  - Kurs = Sehne ±1,5 m (`_smooth_dir`, `yaw_chord`), Tempo vor Bögen gedrosselt (`_speed_cap` mit dem Kurvenprofil `vprof` der Stücke aus `Router.curve_profile`). Prüfung: `tools/test.sh fahren` (Lektion ruhig-fahren).
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
- **`BucketLoad`** (Kind der Schaufel): Erde im Löffel. Findet Hohlraum und Öffnung aus dem Schaufelmodell (Schnitte quer zur Gelenkachse, keine festen Koordinaten), füllt den Hohlraum und häuft aus der Öffnung. `set_load()` am Rig; die Baustelle füllt beim Graben mit (`progress`), beim Auskippen (Keyframe `pour`) rutscht die Erde heraus. Test: `tools/test.sh schaufel`.

## Baustelle (`src/site/`)

- **`JobManager`** erzeugt Angebote auf geeigneten Straßen und macht aus einem angenommenen Auftrag eine `Site`. Er verwaltet auch Ablauf und Abrechnung. `check_spot(p, pipe)` (#33) prüft ohne Nebenwirkung, ob eine Grube an p passt (Vorschau und Debug-Platzieren über `offer_at`). Geprüft wird nur die Grube: rechter Fahrstreifen der angeklickten Richtung, nicht Brücke/Tunnel/Kreuzungsfläche, Platz für Bagger und Kipper dahinter, keine Überschneidung (`_clash`). Zebrastreifen, Haltestellen und kurze Straßen sind nur Hinweise (`_spot_hints`). Debug-Vorschau: `PlaceJobTool` + `PitPreview` (`src/debug/`).
- **`Job`:** Vertrag (Leitung, DN, Graben, Vergütung, Frist).
- **`SiteLayout`:** die gesamte Geometrie in Spurkoordinaten der gesperrten Spur K, also Schilder, Verziehung, Grube, Stellplätze (exc, load, van, stage, lowbed) und Ausweichspur K2.
  - Die Grube liegt immer bei `anchor_s + TAPER + HEAD_GAP`. An Kreuzungen staucht sich die Vorlage (#33): `s0` ≥ `HEAD_MIN`, `taper_out`/`det_out` kürzer, `squeezed`. Die Grundwerte der Verkehrsgeometrie stehen in `_def` (Basis jedes Spielerplans), `extent_limits()` ist der ganze Abschnitt minus `REV_ROOM`.
  - Parkplätze (`plan_kerb(ext)` → `kerb`): Bus (`s_van` ≥ 0 auf K, sonst `kerb.van`), drei Warteplätze, Tieflader. Zuerst auf K vor/hinter der Absperrung, sonst auf dem geraden Zulauf (`pre_key`) oder Ablauf (`post_key`). In `site.gd` nur über `van_spot()`, `van_pose()`, `stage_spot(i, rear_ext)`, `lowbed_spot(back)` und `kerb_pt/kerb_dir/kerb_len` (Spur kann eine andere sein als K).
- **`Site`** (größte Datei, Hotspot):
  - `STEPS` = scout → closure → dig → pipe → refill → asphalt → demob → teardown → acceptance.
  - `phase`, `running`, `status`, `progress`, `sub`.
  - Fahrzeuge melden sich an (`spot_of`, `in_place`), Material über `needs` (inklusive unterwegs befindlicher Ladungen).
  - Am Ende wird die Baustelle mit `retired` stillgelegt, nicht gelöscht (Lektion baustelle-stilllegen).
- **Debug-Menü (F3):** `src/debug/`. Wer einen Arbeitsschritt ändert oder neu baut, passt `DebugTools.finish_step` an, damit er sich sofort erledigen lässt, und prüft das mit `tools/test.sh debug`.
- **`SiteTerrain`:** Höhenraster (10 cm) mit Schichten Asphalt, Tragschicht und Boden. Die Grube wird gegraben und verfüllt.
- **`SiteProps`:** Absperrteile (FS25-Set, privat) und Schilder. **`Worker`:** Kolonne mit einfachen Animationen.
- **`ClosurePlan`** (#9): die Absperrung als Plan in Weltkoordinaten – Teile `{kind, pos, yaw, phase, group}` und gelbe Linien. Vorlage = `SiteLayout.items()` (Reihenfolge und Verkehr unverändert, `custom = false`), sonst vom Spieler. Ketten, Prüfliste, Speichern. `plan.extent(lay)` liefert die Verkehrsgeometrie des Plans; `plan.traffic` (#19) hält selbst gelegte Fahrspuren als Stützpunkte `{k: [Vector2(s, lat)], k2: [...]}` (leer = automatisch).
- **Fahrspuren (#19):** `SiteLayout.k_ctrl` / `k2_ctrl` sind Stützpunkte in Fahrstreifenkoordinaten von K bzw. K2, `ctrl_path`/`ctrl2_path` machen daraus die Polylinie (smoothstep zwischen den Punkten). Automatisch: `auto_k_ctrl(ext)` (gleiche Kurve wie früher). `_finish_extent` klemmt Spielerpunkte in die Grenzen und setzt `two_way` (`paths_apart`, 2,5 m): dann kein `set_zone` → keine Engstelle.
- **Stellplätze (#22):** `ClosurePlan.slots` (exc = Drehpunkt, load = Heck des Kippers beim Laden, pile = Haufenmitte, van, stage; je `Vector2(s, lat)`). `SiteLayout._finish_slots` klemmt sie (hinter dem Graben, Reihenfolge Bagger → Kipper, Fahrbahnrand bis Bordstein) und `apply_extent` setzt `s_tc`/`s_exc`/`exc_lat`, `load_rear`/`load_lat`, `pile_s`/`pile_lat`, `stage0`; `load_s`, `dump_s`, `pile_center`, `stage_s` rechnen daraus. `Site._go_slot(v, spot, s, lat)` setzt mit `_lat_blend` seitlich ein, `exit_plan` fährt so heraus, `_repark` setzt Maschinen nach einer Planänderung direkt um (`_moving`: der Arbeitsschritt bleibt). `ClosurePlan.machine_spots` liefert die Grundflächen für Prüfung und Zeichnung.
- **Umbau während der Arbeiten (#21):** `Site.set_plan` in einem Arbeitsschritt (`WORK_STEPS`): läuft gerade ein Baggerspiel, eine Verdichtung oder der Rohrtausch (`_safe_for_rebuild`), wird der Plan als `_pending_plan` geparkt und in `_process` übernommen, sobald es geht. `work_paused()` hält die Ticks von Graben/Verfüllen/Asphalt an und sperrt die Aktionen; `rebuild` → `_start_rebuild` (Kolonne vor Ort) → `_tick_crew_tasks` → `_finish_rebuild`, dann laufen die Ticks weiter.
- **Vollsperrung (#20):** `ClosurePlan.full`. `Site._traffic_activate` setzt dann Hindernisse auf K und K2, `TrafficSim.close_edges(Site.closed_edges())` und nur die Verschwenkung von K ohne Zone (für die eigenen Fahrzeuge). `TrafficSim`: `closed_lanes` = Fahrstreifen der gesperrten Abschnitte plus Zuläufe ohne anderen Ausgang; `_choose_conn` lässt sie aus, `_try_spawn` setzt dort keine Autos ab, `_reroute_closed` kürzt Routen vor dem Einbiegen, Wartende vor der Sperrung verschwinden (`_on_closed`). `Vehicle._avoid_edges(start_key, dest_key)` meidet gesperrte Abschnitte außer Start/Ziel.
  - `Site.item_defs` kommt aus `plan.defs(lay)`; `in_lane` = Teil sperrt Spur K. Das erste gesetzte `in_lane`-Teil schaltet den Verkehr um, das letzte entfernte zurück.
  - Ein eigener Plan verschiebt die Verkehrsgeometrie (`SiteLayout.extent_for` / `apply_extent`: `s_det0/1`, `p_full0/1`, `obst0/1`, `s_van`, K2-Bereich). Wer in `site.gd` Positionen aus dem Layout liest, nimmt die Felder, nicht die Standardformeln.
  - `Site.set_plan()` übernimmt einen Plan, auch wenn schon Teile stehen (passende bleiben, der Rest wird von der Kolonne eingesammelt).

## Welt und Oberfläche

- **`World`** besitzt Karte, Umgebung, HQ, Verkehr, Fuhrpark, Aufträge, Lichter und die Kamera (`CameraRig`, Shapez-2-Stil). `CameraRig.enter_topdown()` / `exit_topdown()` schalten auf eine orthografische Draufsicht (Absperrung-Designer).
  - `DayNight`: Sonne nach Breitengrad und Datum.
  - `LightPool`: echte Lichter an den nächsten Laternen.
  - `SignalHeads`: Ampeln (nicht in Tunneln).
  - `UndergroundView` (#31, Taste U): Schleier über der Stadt, Ebenen `under_*` sichtbar, Fahrzeuge in Tunneln als Kästen. `TrafficSim.in_tunnel(ag)` entscheidet, ob ein Fahrzeug im Tunnel ist (Körper hinter dem Portal); dann zeichnen weder `_place_visual` noch `Vehicle.apply_agent_pose` das Modell. `Router.nearest_lane` findet Tunnelspuren nur mit `under = true` (Klick auf die Oberfläche meint die Straße oben).
  - `HQ`: Hof, Halle, Lagerboxen, Parkplätze.
- **`HUD`:** obere Leiste, linke Leiste (Aufträge, Fuhrpark, Finanzen, Hilfe, **Meldungen** mit Zähler) und Kontextfenster für Fahrzeug und Baustelle.
  - `ClosureDesigner` (#9, „Absperrung planen“): eigenes Vollbild-Control im HUD, blendet die übrigen HUD-Teile (außer Meldungen/Toasts) aus, ist `World.tool` (Rechtsklick), pausiert das Spiel und zeichnet den Plan als Symbole über der Draufsicht. Übernehmen → `Site.set_plan()`.
  - Stil: schwarz/weiß mit orangem Akzent (`UI`-Kit).
  - **`WorldMarkers`** (erstes Kind des HUD, also unter allen Fenstern): Markierungen für Zentrale, Baustellen, Ausschreibungen und Fahrzeuge, am Bildrand mit Pfeil; Leiste unten rechts mit Ansicht-Schaltern (H Markierungen, B Gebäude = Ebene `building` der Kartenkacheln, U Untergrund – wird nicht gespeichert). Der freie Bildbereich hängt an `HUD.LEFT_W`/`RIGHT_W`; wer dort Fenster ändert, prüft die Markierungen mit `tools/test.sh markierungen`.

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
