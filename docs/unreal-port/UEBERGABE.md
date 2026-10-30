# Tiefbau Tycoon → Unreal Engine: Übergabe an die Port-Session

Stand: 30.10.2026 · Für: Claude Code, lokal auf Jonathans MacBook · Referenzstand Godot: `lab-43/tiefbau-tycoon` @ `222298a` (30.10.2026, 04:19)

Diese Datei ist der Einstieg für die Session, die das Spiel nach Unreal Engine portiert. Sie fasst zusammen, was es gibt, was entschieden ist, wie die Arbeit abläuft und was offen ist. Die Startnachricht zum Kopieren steht in Anhang A.

---

## 0. Kurzfassung

- **Was:** Das Godot-Spiel (GDScript, ~30.500 Zeilen) wird nach **Unreal Engine 5.8** (C++) portiert. Das ist eine Neuschreibung mit der Godot-Fassung als Vorlage, keine Konvertierung. Kein Code läuft direkt weiter.
- **Wo:** Claude Code läuft lokal auf dem MacBook Pro (M4 Max, 16 CPU- und 40 GPU-Kerne, 48 GB RAM). Unreal Editor, Xcode und der MCP-Server des Editors laufen auf demselben Rechner.
- **Erst prüfen, dann portieren:** Phase 0 ist ein **Look-Test** (1–2 Sessions). Eine fertige Hamburg-Karte aus Godot wird als glTF exportiert und in Unreal mit Lumen geöffnet. Danach entscheidet Jonathan, ob der Port startet und wo er spielen will (Mac oder Windows-PC).
- **Godot bleibt spielbar.** Bis die Unreal-Fassung gleichzieht, ist die Godot-Fassung das Spiel. Das Godot-Repo ist für dich nur Referenz.
- **Jonathan will lernen.** Er will in das Projekt hineinschauen und an deiner Arbeit lernen. Deshalb gibt es einen Lernpfad (Abschnitt 8).

---

## 1. Ausgangslage

### 1.1 Wer, wofür
- Jonathan baut das Spiel nur für sich (privat, nie veröffentlicht). Hamburg ist Testgebiet.
- Bisher arbeiten mehrere Cloud-Sessions parallel am Godot-Repo und arbeiten Meldungen ab, die Jonathan im Spiel mit F8 schreibt. Die Builds landen auf seinem Windows-PC.
- Jonathans Rechner:
  - **MacBook Pro** M4 Max (16 CPU, 40 GPU, 48 GB): Entwicklung in Unreal.
  - **Windows-PC** mit GTX 1080 Ti und Monitor 3440×1440: Dort läuft heute das Godot-Spiel. Dort liegen die privaten Modelle, Construction Simulator und die Meldungen (`C:\Users\Jonathan\Documents\Tiefbau Tycoon`).

### 1.2 Ehrliche Einordnung
- Die Godot-Fassung ist in rund vier Tagen mit vielen parallelen Sessions entstanden. Der Port dauert länger:
  - C++ muss kompiliert werden.
  - Unreal-Assets sind Binärdateien.
  - Auf einem Mac arbeitet sinnvoll nur eine Session gleichzeitig.
- Rechne mit Wochen. In dieser Zeit kann die Unreal-Fassung weniger als die Godot-Fassung.
- Unreal kann auf dem Mac **keine Windows-Builds** erstellen. Soll das Spiel auf dem PC laufen, wird es dort gebaut (Phase 8).

---

## 2. Entscheidungen

| Thema | Entscheidung | Warum |
|---|---|---|
| Engine | **Unreal Engine 5.8** (neueste 5.8.x) | Aktuelle Version. Bringt das experimentelle Unreal-MCP-Plugin mit, über das Claude Code den Editor bedient. |
| Sprache | **C++** für alle Logik. Blueprints höchstens als dünne Schicht. | Text lässt sich lesen, vergleichen und in Git zusammenführen. Binäre Blueprints nicht. |
| Entwicklungsrechner | MacBook, Claude Code lokal | Wunsch von Jonathan |
| Neues Repo | **`lab-43/tiefbau-tycoon-unreal`, privat**, Git LFS für Binärdateien | Getrennt vom Godot-Repo. Die Godot-Sessions laufen ungestört weiter. |
| Ordner auf dem Mac | `~/Documents/GitHub/tiefbau-tycoon-unreal` (neu), `~/Documents/GitHub/tiefbau-tycoon` (Godot-Referenz) | So liegen auch Jonathans andere Projekte |
| Projektname | Unreal-Projekt und C++-Modul `TiefbauTycoon`, Fenstertitel „Baustellen Manager“ | Wie die Godot-Fassung |
| Ziel des Ports | **Gleiches Verhalten wie Godot @ `222298a`**. Verbesserungen erst danach. | Die Godot-Fassung samt Tests ist die Spezifikation. So bleibt messbar, ob der Port fertig ist. |
| Oberfläche | Gleich im neuen Stil **„Elbglas“** (Anhang B), nicht die alte Godot-Oberfläche nachbauen | Jonathan hat den Stil am 28./29.10. freigegeben. In Godot ist er noch nicht umgesetzt. |

**Offen, Jonathan entscheidet** (nach dem Look-Test fragen):
1. Port starten: ja oder nein?
2. Wo spielen: Mac oder PC? Davon hängt ab, wann Windows-Builds nötig sind (Abschnitt 7, Phase 8).
3. Godot während des Ports einfrieren (nur noch Fehlerbehebungen)? Empfehlung: ja, sonst läuft der Port einem bewegten Ziel hinterher.

---

## 3. Harte Regeln

1. **Private Assets:** Die Modelle aus Construction Simulator und dem FS25-Mod sind nur für den privaten Gebrauch.
   - Sie kommen nie ins Git, auch nicht als importierte `.uasset`. Importierte Fassungen liegen unter `Content/Private/`, und der Ordner steht in `.gitignore`.
   - Ein Prüfskript (wie `tools/lint.py` in Godot) verhindert, dass sie doch eingecheckt werden.
   - Ohne private Modelle muss das Spiel trotzdem starten, mit einfachen Ersatzmodellen (wie in Godot).
2. **Construction-Simulator-Ordner tabu.** Nie in den Steam-Ordner schreiben (betrifft nur den PC).
3. **E-Mail-Adresse:** Jonathans Mail-Adresse geht an keinen Dienst, auch nicht in User-Agents.
4. **Sprache:**
   - Spieltexte und Doku auf Deutsch, Code-Kommentare auf Englisch.
   - Mit Jonathan sprichst du in der Sprache, in der er schreibt.
5. **Ehrlich bleiben.** Jonathan stört es, wenn Claude ihm einfach recht gibt.
   - Widerspruch begründen.
   - Unsicherheit benennen.
   - Grenzen offen sagen.
   - „Funktioniert“ erst nach Test oder Screenshot.
6. **Repo privat halten.** Nach dem Anlegen die Sichtbarkeit prüfen.
   - Hinweis: `lab-43/tiefbau-tycoon` ist auf GitHub derzeit **öffentlich**, geprüft am 30.10. Laut Konzept sollte es nie öffentlich sein.
   - Ob das so bleibt, entscheidet Jonathan.
7. **Godot-Repo nur lesen.** Aus der Port-Session nichts dorthin committen. Lokale Hilfsskripte für den Export bleiben uncommittet.
8. **Unreal-MCP sicher nutzen.**
   - Der Server hat keine Anmeldung. Er läuft nur lokal und nur, solange er gebraucht wird.
   - Kein `--dangerously-skip-permissions`, solange das Plugin geladen ist.
   - Vor langen Editor-Aktionen speichern und committen.

---

## 4. Arbeitsplatz auf dem Mac (Phase 0a)

Prüfe, was schon da ist. Sag Jonathan genau, was er selbst installieren oder anklicken muss: Epic-Konto, Launcher, Xcode-Download, Repo anlegen, Dateien vom PC kopieren.

1. **Unreal Engine 5.8** über den Epic Games Launcher.
2. **Xcode** in der Version, die Epic auf der Seite „macOS Development Requirements“ für 5.8 nennt.
3. **macOS 15 oder neuer:** Shader Model 6 auf dem Mac braucht es, also auch Nanite.
4. **Git LFS.**
5. **Godot 4.5.1** für macOS, Standard-Fassung, nicht .NET. Damit läuft die Referenzfassung und der Export für den Look-Test.
6. **Godot-Repo klonen:**
   - Befehl: `git clone https://github.com/lab-43/tiefbau-tycoon ~/Documents/GitHub/tiefbau-tycoon`
   - Den Referenz-Commit `222298a` merken. Neuere Commits auf main zeigt Abschnitt 9.
7. **Private Modelle** (~170 MB) vom PC holen:
   - Quelle: `C:\Users\Jonathan\Documents\Tiefbau Tycoon\private\assets.tar` oder die Ordner `game/assets/consim` (45 Modelle, je `.glb` + `.json`) und `game/assets/barriers` (6 FS25-Absperr-GLBs).
   - Jonathan kopiert sie selbst, z. B. per USB-Stick.
   - Auf dem Mac ins Godot-Klon entpacken (`game/assets/…`, dort per `.gitignore` ausgeschlossen) und als Importquelle für Unreal nutzen.
8. **Unreal MCP** (experimentell in 5.8):
   - Im Projekt die Plugins **Unreal MCP** (Kennung `ModelContextProtocol`) und **AllToolsets** aktivieren.
   - In der Editor-Konsole `ModelContextProtocol.GenerateClientConfig ClaudeCode` ausführen. Das schreibt `.mcp.json` ins Projekt.
   - Danach `ModelContextProtocol.StartServer` (Port 8000). Die Namen stehen in Epics Doku, im Editor gegenprüfen.
   - In Claude Code: `/plugin install unreal-engine-skills-for-claude-code@claude-plugins-official` (Epics offizielles Plugin: Skill und Projekt-Hinweis).
9. **Neues Repo** `lab-43/tiefbau-tycoon-unreal`, **privat**. Jonathan legt es an, oder du mit `gh repo create … --private`, wenn `gh` angemeldet ist und er zustimmt.
   - `.gitattributes`: LFS für `*.uasset`, `*.umap`, Bilder, Audio.
   - `.gitignore`: `Binaries/`, `Intermediate/`, `Saved/`, `DerivedDataCache/`, `Content/Private/`, `.mcp.json`.

---

## 5. Was es gibt: die Godot-Fassung

### 5.1 Pflichtlektüre im Godot-Repo
| Datei | Wofür |
|---|---|
| `CLAUDE.md` | Regeln, Ordner, Definition of Done |
| `.claude/skills/spiel-architektur/SKILL.md` | **Die wichtigste Karte für den Port:** welche Datei was besitzt, Ablauf, Koordinaten, Spurschlüssel, Baustellen-Logik |
| `docs/MVP-Umsetzung.md` | Was das Spiel heute kann, Abweichungen vom Konzept, Grenzen, Testszenarien je Feature |
| `docs/Baustellen-Manager-Konzept-MVP.md` | Ursprüngliche Spezifikation (Ziele, Performance-Ziele in 13.2) |
| `docs/lessons/*.md` (94) | Lektionen aus echten Fehlern. Etwa ein Drittel betrifft nur Godot. Der Rest (OSM-Eigenheiten, Markierung nach RMS, Gelände, Verkehr, Testdisziplin) gilt weiter. |
| `docs/consim_assets.md` | Woher die Modelle kommen und ihre Konventionen: Achsen (Fahrzeuge schauen nach −Z), Räder, Gelenke, Lichtmarker, Zylinder, Materialien, JSON-Felder |
| `game/test/e2e_driver.gd`, `tools/test.sh` | Die Testszenarien sind die Abnahmekriterien des Ports |
| `.claude/skills/tycoon-dev/SKILL.md` | Spielschalter (`--autostart --fixture=utrecht --e2e=…`), Tests, Screenshots |

### 5.2 Code (Stand `222298a`)
| Ordner | Zeilen | Inhalt |
|---|---:|---|
| `src/map/` | 10.005 | Geofabrik/PBF, Overpass, Geländehöhen (Mapterhorn), Straßennetz, Kreuzungen, Markierung (RMS), Brücken, Tunnel, Gebäude, Flächen, Bäume, Chunks |
| `src/site/` | 6.012 | Baustelle (Arbeitsschritte, Graben-Höhenraster 10 cm), Layout in Spurkoordinaten, Absperrplan, Aufträge |
| `src/ui/` | 5.709 | HUD, Absperrungsplaner, Ladebildschirm, Kartenauswahl, Meldungen (F8), Markierungen |
| `src/vehicles/` | 3.138 | Fahrzeug, Fuhrpark, Bagger-IK mit Viergelenk, Zylinder, Erde im Löffel, Modell-Lader |
| `src/traffic/` | 1.986 | Mikrosimulation (IDM, Ampeln, Vorfahrt, 208/308, Vollsperrung), Verkehrsmodelle |
| `src/world/` | 1.225 | Welt, Kamera (Shapez-2-Stil), Tag/Nacht, Lichter-Pool, Ampelköpfe, Zentrale, Untergrund-Ansicht |
| `src/debug/` | 913 | Debug-Menü (F3), Auftrag platzieren |
| `src/core/` | 883 | Autoloads `Game`, `Clock`, `Balance`, `Events`, Logger, Meldungsablage |
| `src/nav/` | 382 | A* auf dem Spurgraph, fahrbare Stücke |
| **Summe** | **30.493** | 69 Dateien. Dazu ~5.900 Zeilen Tests, 13 Shader + 2 Include-Dateien |

Größte Dateien (Hotspots): `site.gd` 2.527 · `closure_designer.gd` 1.882 · `road_net.gd` 1.625 · `vehicle.gd` 1.442 · `traffic_sim.gd` 1.203 · `hud.gd` 1.043.

### 5.3 Testdaten im Godot-Repo
- `testdata/utrecht.osm.pbf`: Offline-Karte, Grundlage fast aller Tests.
- `testdata/kreuzungen`: 8 Hamburger Kreuzungen.
- `testdata/bruecken`: Waltershof mit Köhlbrandbrücke.
- `tools/osm_fixture`.

---

## 6. Umsetzung in Unreal

### 6.1 Grundsätze
1. **Verhalten wie in Godot.** Bei Zweifeln entscheidet der Godot-Code, nicht dein Gefühl für „wie man es in Unreal macht“. Abweichungen nur mit Grund, notiert in `docs/abweichungen.md`.
2. **Logik als Text, Binärdateien sparsam:**
   - Eine fast leere Karte (Level). Die Stadt entsteht zur Laufzeit wie in Godot.
   - Wenige Master-Materials plus Instanzen.
   - UMG-Widgets mit C++-Elternklassen (`BindWidget`).
   - Zahlen (Balance, Fahrzeugkatalog, Markierungsmaße, RSA-Werte) in Textdateien (JSON/CSV) im Repo.
   - Wo es geht, Binär-Assets per Skript erzeugen (Python-Editor-Scripting oder MCP) und das Skript committen.
3. **Module:**
   - `TiefbauCore`: reines C++ in Metern, möglichst ohne UObject. Enthält Geo, OSM, PBF, Straßennetz, Brücken, Gelände-Raster, IDM, Router, Layout- und Plan-Rechnung, Balance. Hier liegt der größte Teil, gut testbar.
   - `TiefbauTycoon`: Actors, Components, Darstellung, Eingabe, UI.
   - `TiefbauEditor`: Import der Modelle, Asset-Werkzeuge.
4. **Tests von Anfang an:**
   - Unreal-Automation-Tests, headless mit `-nullrhi -unattended`.
   - Dazu ein e2e-Treiber über Kommandozeilenschalter wie in Godot (`-autostart -fixture=utrecht -e2e=job -shots=<dir>`), der auch im gepackten Spiel läuft.
   - Screenshots gerendert (ohne `-nullrhi`) und **angesehen**.
5. **Klein committen.** Ein Branch pro Phase, `main` bleibt grün.

### 6.2 Koordinaten (früh festlegen und testen)
- **Kern wie Godot:**
  - 2D-Punkte in Metern, `FVector2D(x = Ost, y = Süd)`. Das ist Godots `Vector2(x, z)` aus `Geo.to_local`.
  - Höhen getrennt.
  - Damit bleiben alle 2D-Algorithmen samt Umlaufsinn und Vorzeichen gleich.
- **Unreal-Welt:** `X = Ost, Y = Süd, Z = oben`, Faktor 100 (cm).
  - Das ist Godots (x, y, z) mit vertauschtem y und z. Die Händigkeit (rechts → links) stimmt damit automatisch.
  - Umrechnung an genau **einer** Stelle, mit Test.
- **Drehwinkel um die Hochachse wechseln das Vorzeichen.**
  - In Godot ist eine Drehung gegen den Uhrzeigersinn (von oben gesehen) positiv.
  - In Unreal dreht positiver Yaw X Richtung Y, also im Uhrzeigersinn.
  - Godot-Fahrzeuge schauen nach −Z (`vehicle.gd`: `yaw = atan2(-dir.x, -dir.y)`).
  - Mit Test prüfen, nicht raten.
- **Große Welt:** Unreal rechnet mit 64-Bit-Weltkoordinaten (Large World Coordinates). Der verschiebbare Ursprung aus dem Konzept entfällt.
- **Unverändert übernehmen:**
  - Spurschlüssel `edge*16 + dir*8 + lane` (Spur 0 = links in Fahrtrichtung).
  - Spurkoordinaten (s = Meter entlang der Spur, seitlich + = rechts).
  - So bleiben Tests, Spielstände und Meldungen vergleichbar.

### 6.3 Godot → Unreal: was wohin
| Godot | Unreal | Achtung |
|---|---|---|
| Autoloads `Game`, `Clock`, `Balance`, `Events` | Subsystems (`UGameInstanceSubsystem`, `UWorldSubsystem`), Events als Multicast-Delegates | |
| `ArrayMesh`/`SurfaceTool`/`MeshLayer` (je Chunk und Material) | `UDynamicMeshComponent` (Geometry Scripting) oder `UProceduralMeshComponent` | In Phase 2 beide messen (Aufbauzeit, FPS, Speicher). Zur Laufzeit erzeugte Meshes sind voraussichtlich kein Nanite. |
| `MultiMesh` (Bäume, Laternen, Absperrteile) | `UHierarchicalInstancedStaticMeshComponent` | |
| `Geometry2D` (offset/clip/merge/intersect/triangulate, Godot nutzt intern Clipper2) | GeometryCore/GeometryAlgorithms aus Unreal oder Clipper2 (Boost-Lizenz) als ThirdParty | Ergebnisse müssen den Godot-Werten entsprechen (Lektion `clip-polygons-loecher`) |
| `HTTPRequest`/`HTTPClient` (rund 50 Vorkommen) | `FHttpModule` | Weiterleitungen 301–308, Zeitlimits, Abbruch ohne Blockieren, User-Agent ohne Mail. Lektionen `http-weiterleitungen`, `http-ohne-threads`, `server-pruefen`, `overpass-antwort-pruefen`. |
| zlib-Blöcke im PBF | `FCompression` (`NAME_Zlib`) | |
| WebP-Höhenkacheln (Mapterhorn) | `ImageWrapper` | Prüfen, ob 5.8 WebP kann, sonst libwebp einbinden |
| `Thread`, Worker | `UE::Tasks`, `Async`, `FRunnable` | Hauptthread bleibt frei (Lektion `hauptthread-frei`) |
| 13 Shader (asphalt, mark, building, ground, terrain, grass, paving, water, bulk, warnlight, carlight, carlamp, carlamp_2s) | Materials (wenige Master + Instanzen) | `terrain_depth` (Höhe pro Pixel als Tiefe) nur nachbauen, wenn Ebenen flackern; sonst Pixel Depth Offset oder echter Versatz |
| `CameraRig` (Shapez-2-Stil), orthografische Draufsicht | Eigener Pawn + Enhanced Input, orthografische Kamera für den Absperrungsplaner | Steuerung siehe Konzept, Abschnitt 4 |
| Klicks über das eigene Höhenraster (`Terrain.top`) | Dieselbe Rechnung portieren | Keine Physik-Kollision auf den Stadt-Meshes nötig |
| `DayNight`, `LightPool` | Directional Light (Sonne/Mond), SkyAtmosphere, SkyLight, Height Fog. Pool aus Point Lights ohne Schatten. | MegaLights und Hardware-Raytracing gibt es auf dem Mac nicht, die 1080 Ti hat keine RT-Kerne. Also Lumen in Software. |
| UI (Control, `UI`-Kit) | UMG mit C++-Elternklassen, Stil Elbglas (Anhang B) | `BackgroundBlur` ersetzt den Blur-Shader, Schrift IBM Plex (OFL) |
| Spielstand (`store_var` + zstd) | Eigenes, versioniertes Format | Felder abwärtskompatibel lesen wie in Godot. Godot-Spielstände müssen nicht laden. |
| Modelle `consim/<id>/<id>.glb` + `.json` (`wheels`, `nodes`, `joints`, `joint_limits_deg`, `light_markers`, `hydraulics`, `bucket_linkage` …) | Import per Editor-Skript nach `Content/Private/`. JSON als Daten zur Laufzeit. | In Phase 1 am **Liebherr A918** entscheiden: Static-Mesh-Hierarchie mit erhaltenen Drehpunkten oder Skeletal Mesh. Lektionen `fremdmodelle-importieren`, `gelenkwinkel-modellabhaengig`, `anbauteile-auf-oberflaeche`. |
| FS25-Absperrset (Varianten per `extras.hidden`, leere Knoten `light_point`/`light_spot`) | Import, der Varianten per Namen schaltbar und Lichtpositionen auslesbar hält | |
| Meldungen (F8, `IssueStore`) | Später. Dasselbe Ordnerformat (`userdata/issues/<nr>-<titel>/`) behalten, dann funktioniert `tools/agent/issues.py` für beide Fassungen. | |

---

## 7. Phasen

Jede Phase endet mit:
- etwas Sichtbarem für Jonathan,
- grünen Tests und angesehenen Screenshots,
- einem Eintrag im Lernpfad,
- Jonathans OK, bevor die nächste startet.

Die Godot-Szenarien in Klammern sind die Messlatte. Referenzwerte (Zahlen, Bilder) erzeugst du selbst mit der Godot-Fassung @ `222298a` auf derselben Eingabe.

### P0 – Arbeitsplatz und Look-Test (1–2 Sessions, Entscheidungspunkt)
1. Arbeitsplatz nach Abschnitt 4. Was fehlt, an Jonathan melden.
2. Godot-Fassung auf dem Mac starten:
   - Offline mit `--autostart --fixture=utrecht`.
   - Danach eine Hamburg-Karte. Die Firmengründung lädt den Geofabrik-Auszug (51 MB) und die Höhenkacheln selbst.
3. **Stadt als glTF exportieren:**
   - Mit einem kleinen lokalen Skript, das nach dem Laden der Karte `GLTFDocument.append_from_scene` auf den Stadtknoten anwendet und `write_to_filesystem` schreibt.
   - Mit echtem Renderer starten, nicht `--headless`. Prüfen, ob der Dummy-Renderer im Headless-Modus Mesh-Daten liefert; vermutlich nicht.
   - Das Skript liegt im neuen Repo unter `tools/godot_export/`, nicht im Godot-Repo.
4. **In Unreal öffnen:**
   - glTF-Import, je Kartenebene ein einfaches Material (Asphalt, Gehweg, Markierung, Gebäude weiß-grau, Wiese, Wasser).
   - Sonne, Himmel, Lumen (Software), Virtual Shadow Maps.
   - Ein paar Maschinen und Absperrteile in eine Straße stellen.
5. **Vergleich:**
   - Je 4–5 Bilder aus Godot und Unreal von denselben Stellen: Wohnstraße, große Kreuzung, Köhlbrandbrücke, Deichtorplatz, Übersicht.
   - Bei Tag und bei Nacht.
   - FPS auf dem Mac (`stat fps`, `stat unit`) in voller Auflösung.
6. Jonathan die Bilder nebeneinander zeigen. **Entscheidungen aus Abschnitt 2 einholen.** Ohne sein Ja nicht weiter.

### P1 – Gerüst und Assets
- C++-Projekt mit den Modulen aus 6.1. Bauen per Kommandozeile (UnrealBuildTool), ein Automation-Test läuft headless.
- Koordinaten-Umrechnung mit Tests (6.2).
- Import-Skript für alle 45 Modelle und die 6 Absperr-GLBs nach `Content/Private/`:
  - benannte Teile und Drehpunkte,
  - Lichtmarker,
  - schaltbare Varianten,
  - Ersatzmodelle, wenn nichts da ist.
- Asset-Viewer-Karte: drehen, Lichter schalten, Gelenke bewegen, Absperrvarianten durchschalten.
- Prüfskript: keine privaten Assets und keine Mail-Adresse im Git.
- **`CLAUDE.md` und Skills fürs neue Repo:**
  - Architektur,
  - Unreal-Fallen,
  - Lernen,
  - Lektionen aus Godot einsortieren in „gilt weiter“ (übernehmen) und „nur Godot“ (weglassen).

### P2 – Karte (größte Phase, in 2a/2b/2c teilen)
- **2a Daten:**
  - Geofabrik (kleinster passender Auszug, MD5, 30-Tage-Cache) mit Overpass als Rückfall,
  - PBF-Leser,
  - Projektion,
  - Straßennetz mit Kreuzungs-Zusammenfassung, Spuren, Abbiegewegen, Konflikten, Vorfahrt,
  - Cache.
  - *Abnahme:* gleiche Zahlen wie Godot auf `utrecht.osm.pbf` und Hamburg: Straßenzüge, Kreuzungen, Spuren, Gebäude, Ampeln (`pbf`).
- **2b Darstellung:**
  - Fahrbahn, Gehweg, Bordstein, Markierung (RMS), Gebäude, Flächen, Wasser, Bäume und Laternen neben der Fahrbahn,
  - Chunks und Detailstufen.
  - *Abnahme:*
    - Messwerte des Kreuzungs-Prüfstands (`tools/kreuzungen.sh`) nicht schlechter als Godot,
    - `ebenen`, `baeume`,
    - Bilder an festen Stellen.
- **2c Höhen:**
  - Gelände (Mapterhorn, Rückfall AWS),
  - Brücken mit Rampen und Böschungen,
  - Tunnel und Portale,
  - Untergrund-Ansicht.
  - *Abnahme:* `gelaende`, `bruecken` (Köhlbrandbrücke über 40 m), `tunnel`.
- **Gesamt:** Hamburg 10 × 10 km lädt aus dem Cache in unter 10 s.

### P3 – Kamera, Zeit, Tag und Nacht
- Kamera wie in Godot.
- Uhr (1 Spielstunde = 2 min bei 1×; Stufen Pause/1×/3×/10×).
- Sonnenstand aus Breitengrad und Datum.
- Nachtbeleuchtung mit Lichter-Pool.
- *Abnahme:* `leuchten`, `verkehrslichter`, flüssiger Tag-Nacht-Wechsel.

### P4 – Navigation und Firmenfahrzeuge
- Router (A*, Stücke LANE/BLEND/CONN/POLY), Fahrzeug-Zustände, Lichtautomatik.
- Zentrale mit Stellplätzen.
- Tieflader auf- und abladen.
- Bagger-IK mit Viergelenk und Zylindern, Erde im Löffel.
- *Abnahme:* `lowbed`, `rig`, `schaufel`.

### P5 – Verkehr
- IDM, Ampeln, Vorfahrt, rechts vor links, Busse, Detailstufen.
- Engstelle 208/308 mit Fairness, Reißverschluss.
- Vollsperrung, Sicherungsbereiche.
- *Abnahme:*
  - `fahren`: Rucke und zu schnelle Kurven pro km nicht schlechter als Godot,
  - 300 Fahrzeuge,
  - 30 min ohne Deadlock.

### P6 – Baustelle und Aufträge
- Auftragsgenerator, Platzierungsprüfung, `SiteLayout`, `ClosurePlan`.
- Alle Arbeitsschritte (scout → closure → dig → pipe → refill → asphalt → demob → teardown → acceptance).
- Graben-Höhenraster, Kolonne, Kipper-Pendel, Abrechnung.
- *Abnahme:* `job`, `platzieren`, `stellplaetze`, `umbau`, `vollsperrung`, `fahrzeuge`.

### P7 – Oberfläche
- HUD, Fahrzeug- und Baustellenfenster, Fuhrpark, Händler, Finanzen im Elbglas-Stil.
- Absperrungsplaner, Debug-Menü (F3), Markierungen.
- Ladebildschirm, Hauptmenü, Firmengründung.
- *Abnahme:* `absperrung`, `markierungen`, `debug`, Bilder neben den Entwürfen.

### P8 – Speichern, Meldungen, Windows, Leistung
- Speichern und Laden (`save+load`, `altstand`).
- F8-Meldungen im selben Ordnerformat.
- **Windows-Build auf dem PC:** UE 5.8 und Visual Studio mit C++-Spieleentwicklung installieren, Bauskript (`RunUAT BuildCookRun`), optional GitHub-Actions-Runner auf dem PC.
- Test auf der 1080 Ti.
- Performance-Ziele aus Konzept 13.2.
- **Wenn Jonathan auf dem PC spielen will:** einen ersten Windows-Build schon nach P2 machen. So zeigt sich früh, ob die 1080 Ti mit den gewählten Einstellungen läuft (siehe Risiken).

---

## 8. Lernpfad für Jonathan

Jonathan will verstehen, was du tust. Deshalb:
- **`docs/lernpfad.md`** (Deutsch) im neuen Repo. Je Phase:
  - welche Unreal-Begriffe neu dazukamen,
  - wo sie im Code stehen,
  - was das Gegenstück in Godot war,
  - 1–2 kleine Übungen, die Jonathan selbst machen kann (z. B. einen Wert ändern und im Editor die Wirkung sehen).
- **Begriffe beim ersten Auftreten kurz erklären**, im Chat und im Lernpfad:
  - `UCLASS`/`UPROPERTY`/`UFUNCTION`, Reflection,
  - Actor vs. Component, Subsystems,
  - Module und `.Build.cs`,
  - Garbage Collection,
  - Live Coding,
  - Blueprint vs. C++.
- **Lesbarer Code vor cleverem Code.** Kommentare erklären das Warum (Englisch).
- Zeig Jonathan, wo er im Editor etwas findet: Einstellungen, Materialien, Widgets.

---

## 9. Arbeitsweise

- **Eine Session zur Zeit** auf dem Mac, denn Editor, Kompilieren und MCP teilen sich den Rechner. Subagenten zum Lesen und Vergleichen des Godot-Codes sind in Ordnung.
- **Rückfragen an Jonathan** bei Entscheidungen, die schwer zurückzunehmen sind. Sonst entscheiden und es im Phasenbericht sagen.
- **Godot-Änderungen nachziehen:**
  - Den Referenz-Commit in `docs/godot-referenz.md` festhalten.
  - Zu Beginn jeder Phase `git -C ~/Documents/GitHub/tiefbau-tycoon fetch` und `git log --oneline <referenz>..origin/main` prüfen.
  - Relevantes übernehmen, die Referenz weitersetzen.
- **Lektionen:** wie in Godot eine Datei pro Lektion in `docs/lessons/`, maschinell prüfbare als Regel im Prüfskript.
- **Definition of Done je Aufgabe:**
  - Prüfskript sauber,
  - Build ohne Fehler,
  - passende Tests grün,
  - Screenshot angesehen,
  - Lernpfad und Lektion geschrieben,
  - committet.

---

## 10. Risiken und offene Punkte

| Risiko | Was tun |
|---|---|
| **GTX 1080 Ti:** keine RT-Kerne, also Lumen nur in Software. Laut Forenberichten brach 5.7 Lumen unter Direct3D mit Shader Model 5. Ob die Pascal-Karte SM6 mit allen gewählten Features trägt, ist ungeprüft. | Wenn auf dem PC gespielt wird: früher Windows-Build nach P2. Rückfall: Lumen aus, klassische Schatten und Licht. |
| **Mac:** Nanite und Virtual Shadow Maps nur als Beta (M2 und neuer, SM6, macOS 15), kein Hardware-Raytracing, keine MegaLights. Unreal auf dem Mac ist weniger ausgereift als unter Windows. | Nichts davon voraussetzen. Mac-Probleme als Lektion festhalten. |
| **Unreal MCP ist experimentell.** | Für Code nicht nötig. Für Editor-Arbeit nutzen, aber nicht davon abhängig machen. |
| **Binärdateien in Git** lassen sich nicht zusammenführen. | Wenige, per Skript erzeugt, LFS. |
| **WebP, Clipper2, glTF-Hierarchie** sind ungeprüft. | Je ein kleiner Test am Anfang der Phase. |
| **Aufwand:** Wochen. Vollständige Gleichheit mit Godot ist viel Arbeit. | Nach jeder Phase ehrlich berichten, was fehlt. |
| **Godot-Repo öffentlich** (siehe Regel 6) | Jonathan entscheidet. Das neue Repo von Anfang an privat. |

---

## Anhang A – Startnachricht für Claude Code auf dem Mac

> Du portierst mein Spiel „Tiefbau Tycoon / Baustellen Manager“ von Godot nach Unreal Engine 5.8. Du läufst lokal auf meinem MacBook.
>
> 1. Klone das Godot-Repo als Referenz (dort nichts committen):
>    `git clone https://github.com/lab-43/tiefbau-tycoon ~/Documents/GitHub/tiefbau-tycoon`
> 2. Lies dort vollständig `docs/unreal-port/UEBERGABE.md`. Lies danach `CLAUDE.md`, `.claude/skills/spiel-architektur/SKILL.md` und `docs/MVP-Umsetzung.md`.
> 3. Starte mit Phase 0 aus der Übergabe:
>    - Prüfe den Arbeitsplatz und sag mir genau, was ich selbst installieren, anlegen oder vom PC kopieren muss.
>    - Mach danach den Look-Test.
>    - Fang den eigentlichen Port erst an, wenn ich nach dem Look-Test zugestimmt habe.
> 4. Ich will dabei lernen. Erkläre neue Unreal-Begriffe beim ersten Auftreten kurz und führe `docs/lernpfad.md`.
> 5. Sei ehrlich: Sag mir, wenn etwas nicht geht, du unsicher bist oder ich falsch liege.

---

## Anhang B – Oberfläche „Elbglas“ (sachliche Fassung, freigegeben 28./29.10.2026)

Entwürfe: https://claude.ai/artifact/28faU9K5E8jouNRTWQauYF. Nur Jonathan kann sie öffnen, denn sie brauchen sein Konto. Die Tokens hier sind die verbindliche Fassung.

- **Artboards:** 2580×1080. Das entspricht 3440×1440 bei Skalierung auf 1080 Höhe; in Unreal per DPI-Skalierung auf Basis 1080.
- **Schrift:**
  - IBM Plex Sans (Breite 85–100 %), Zahlen mit Tabellenziffern.
  - IBM Plex Mono für Uhrzeiten, Maße und Protokoll.
  - Größen: Fließtext 12–12,5 px, Werte 15–18 px, Panel-Titel 18–19 px.
  - Abschnittsüberschriften in Versalien, 11 px, Laufweite 0,07 em, Farbe #8C95A1.
- **Farben:**
  - Text #E4E8EC, gedämpft #929BA7 / #ADB4BE.
  - Akzent #F26B14, nur für Hauptaktionen, Auswahl und den aktiven Dock-Eintrag (Balken links). Preise und Kennzahlen neutral weiß.
  - Positiv #69BF92, Warnung #D9A957, Fehler #DC7D70.
- **Flächen:**
  - Panel rgba(18,21,26,0.9) mit 14 px Blur.
  - Rand 1 px weiß 8 %, flacher Schatten 0 4px 14px.
  - Keine Glows, keine Lichtkanten.
- **Radien:**
  - Panels und Dialoge 14, Karten 10, Knöpfe/Felder/Dock-Einträge 8, kleine Kacheln 6, Tags/Chips 5.
  - Kreise nur für Status-Punkte und Schritt-Nummern.
- **Rahmen:** 10 px Abstand zum Bildschirmrand, Topbar und Dock 52 px, Panels ab x 72 / y 72.
- **Animationen:** keine dekorativen. Es bleiben nur funktionale: Blinken der Rundumleuchte, Laufrichtung der Route, ruhige Kamerafahrt im Hauptmenü.
- **Muster:**
  - Fahrzeug und Ausschreibung → Inspektor rechts.
  - Baustelle und Fuhrpark → Seitenpanel links mit 40 % Breite; die Kamera zieht nach.
  - Listen → Blatt links neben dem Dock.
  - Händler → großes Fenster über der Karte mit echtem 3D-Modell.
  - Orange nur einmal pro Panel.
- **Dock:** Aufträge, Fuhrpark, Fahrzeughandel, Finanzen, Hilfe; darunter Meldungen und „Zur Zentrale“.
- **Neu gegenüber Godot** (Vorschläge aus den Entwürfen):
  - Routenlinie mit Ankunftszeit,
  - „Zum Ort zoomen“,
  - Baustellen-Protokoll, Kostenaufstellung,
  - Licht-Schalterleiste,
  - Händler mit Kategorien und 3D-Bühne,
  - Kauf-Vorschau,
  - Stellplatzplan der Zentrale,
  - Einsatz-Zeitstrahl je Fahrzeug,
  - Kontoverlauf,
  - Maße mit Dezimalkomma.
