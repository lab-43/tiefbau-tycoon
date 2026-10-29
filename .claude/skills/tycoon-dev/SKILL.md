---
name: tycoon-dev
description: Use this skill to set up, check, test, build or deliver the Tiefbau Tycoon / Baustellen Manager Godot game. It covers a new session's environment and private assets, lint/compile/e2e tests, screenshots, Windows builds and copying builds to Jonathan's PC.
---

# Tiefbau Tycoon – Entwickeln, Testen, Bauen, Liefern

## 1. Umgebung (einmal pro Session)

1. Lagebericht: `bash tools/agent/session_start.sh`. Er zeigt Branch, main, parallele Branches, fehlende Teile und Lektionen.
2. Assets vom PC holen. Sie sind privat und nicht im Git.
   - `get_device_info` liefert den Ordner „Tiefbau Tycoon“ (Jonathans PC: `C:\Users\Jonathan\Documents\Tiefbau Tycoon`).
   - `device_stage_files` mit `<Ordner>\private\assets.tar` (~130 MB). Das Archiv landet unter `/mnt/user-data/uploads/Tiefbau Tycoon/private/assets.tar`.
   - Fehlt die Datei, legt die Geräte-Shell sie an:
     `cd "$HOME/mnt/Tiefbau Tycoon" && mkdir -p private && tar -cf private/assets.tar game/assets/consim game/assets/barriers`
   - PC nicht erreichbar: Das Spiel läuft mit prozeduralen Ersatzmodellen, und alle Tests gehen. Builds für Jonathan gehen erst mit Assets. Sag ihm das.
3. Danach `tools/setup_env.sh` ausführen. Es erledigt:
   - Godot 4.5.1
   - Windows-Vorlagen (Teil-Download, 5 s)
   - xvfb/Mesa
   - Entpacken der Assets
   - Git-Identität und Pre-Commit-Lint
   - Import

## 2. Prüfen und Testen

| Befehl | Dauer | Wofür |
|---|---|---|
| `python3 tools/lint.py` | 1 s | Projektregeln aus den Lektionen (privat, Threads, user://, Mail …) |
| `tools/check.sh` | 2 s | Kompiliert alle Skripte mit Autoloads, Fehler mit Datei:Zeile |
| `tools/agent/test_issues.sh` | 3 s | Meldungswerkzeug: parallele Übernahmen, Nummern, Rechte, Sperren |
| `tools/test.sh` | ~40 s | smoke + issue (Standard, auch in merge.sh) |
| `tools/test.sh job` | ~7 min | ein kompletter Auftrag mit Startfuhrpark |
| `tools/test.sh lowbed save+load pbf` | 4 min · ~8 min · 35 s | Tieflader, Speichern/Laden mitten im Graben, PBF-Leser (`pbf` prüft auch die Ebenen, siehe nächste Zeile) |
| `tools/test.sh ebenen` | 12 s | Höhen der flachen Kartenebenen: Wasser und Flächen über dem Boden, Wasser über allen Flächen und unter Wegen, Gleisbett und Straßen |
| `tools/kreuzungen.sh [out]` | 25 s | Kreuzungs-Prüfstand: 8 feste Hamburger Kreuzungen (`testdata/kreuzungen`) aufbereiten, Lücken/Knicke/Versatz/Markierung messen, Bilder nach `<out>/bilder`. Pflicht bei Änderungen an `road_net.gd`/`road_mesher.gd`/`road_markings.gd`: Messwerte vorher/nachher vergleichen (`--compare=<export-dir>,label`); zweite Tabelle zählt Haltlinien, Pfeile, Sperrflächen …, `markierung_neben_m2` = Markierung auf Boden oder Inseln |
| `tools/test.sh fahren` | 6 s | Verkehr auf den Prüfstand-Kreuzungen: Rucke und zu schnelle Kurven pro km (`game/test/drive_test.tscn`, `--v` zeigt jeden Fund). Pflicht bei Änderungen an Spuren, Abbiegewegen, `traffic_sim.gd` oder `router.gd` |
| `tools/test.sh rig` | 5 s | Bagger-Gestänge und Zylinder in allen Stellungen (braucht private Assets). Seitenansichten: `xvfb-run -a godot --path game --rendering-driver vulkan -s res://test/rig_test.gd -- --shots=<dir>` |
| `tools/test.sh schaufel` | 2 s | Erde im Baggerlöffel (#11): liegt im Hohlraum, nichts ragt durchs Blech, zeigt beim Tragen nach oben, rutscht beim Kippen heraus. Ersatzmodell immer, echtes Modell mit privaten Assets. Bilder: `xvfb-run -a godot --path game --rendering-driver vulkan -s res://test/bucket_test.gd -- --shots=<dir>` |
| `tools/test.sh altstand` | 1 min | Spielstand von einer älteren Kartenaufbereitung (#23): Aufträge mit fehlenden oder falschen Straßenschlüsseln sind nach dem Laden an derselben Stelle wieder da, kein Skriptfehler. Pflicht, wenn `BAKE_VERSION` steigt oder Laden/Speichern von Aufträgen geändert wird |

- **Wann welcher Test:**
  - Änderungen an Baustelle, Fahrzeugen oder Verkehr: `job` ist Pflicht.
  - Änderungen am Bagger-Rig (`excavator_rig.gd`, `rig_util.gd`, `bucket_load.gd`): `rig` und `schaufel`, bei sichtbaren Änderungen mit Bildern.
  - Änderungen an Speichern/Laden: `save+load`, bei Aufträgen auch `altstand`.
  - Ein `SCRIPT ERROR` im Log ist in der Windows-Release-Version oft ein Absturz (Lektion editor-binary).
  - Änderungen an der Karte: `pbf` (enthält `ebenen`), plus Ladeweg mit Mock-Servern (Abschnitt 4). Wer Höhen von Kartenebenen ändert, erhöht `MapBuilder.BAKE_VERSION`, sonst lädt Jonathans PC die alte gespeicherte Karte.
- **Logs:** `/tmp/tt_e2e_<szenario>.log`. Der Treiber ist `game/test/e2e_driver.gd`; neue Szenarien gehören dort hinein und in `tools/test.sh`.
- **Spielschalter:**
  - `--autostart --fixture=utrecht`: Offline-Karte, Firma ohne Menüs.
  - `--e2e=<szenario> --speed=N --timeout=S --shots=<dir>`
  - `--overpass=url1,url2` und `--no-geofabrik`: Overpass erzwingen.
  - `--geofabrik-index=<url>`: lokaler Geofabrik-Ersatz.
  - `--data-pack=<pck>`
  - Repro: `--e2e=repro --issue=<ordner> --watch=<s> --out=<dir>` (Skill issue-ablauf). `--every=<s>` macht beim Laufen alle s Sekunden ein Bild der gemeldeten Kameraansicht (für Animationen).
  - Zusatzbilder: `--views=x,z,dist,yaw,pitch[,ohne][,unter]|…` („ohne“ blendet Gebäude aus, „unter“ schaltet die Untergrund-Ansicht ein). Nach Änderungen am Aufbereiten ohne Versionssprung alle `baked_v*.bin` der Karte löschen, auch `_flach` (Lektion karten-cache-flach).

## 3. Screenshots (bei jeder sichtbaren Änderung)

- `E2E_SHOTS=/tmp/shots tools/gd.sh run -- --autostart --fixture=utrecht --e2e=smoke --shots=/tmp/shots`
  - Gerendert wird mit Vulkan/Mesa unter xvfb, langsam aber echt.
  - Die PNGs mit dem Read-Tool ansehen.
- Eigene Kamerapositionen: `shot("name", fokus, distanz, yaw, pitch)` im e2e-Treiber.
- Einzelszene: `tools/gd.sh shot res://pfad.tscn /tmp/x.png`.

## 4. Kartenladen testen

- **Overpass:** `python3 game/test/mock_overpass.py <port> <modus>` spielt einen Server. Modi: ok, slow, rate, flaky, big.
  - Spiel starten mit `--overpass=http://127.0.0.1:<port>/api/interpreter --no-geofabrik`.
- **Geofabrik:**
  - lokal mit `python3 -m http.server` aus einem Ordner mit `index-v1.json` und einer `.osm.pbf` (z. B. `testdata/utrecht.osm.pbf`),
  - dann `--geofabrik-index=http://127.0.0.1:<port>/index-v1.json`.
- Prozesse beenden mit `pkill -f "http[.]server"` (Lektion pkill-muster).

## 5. Bauen

- `tools/build.sh build/main`: vollständiges Spiel.
- `tools/build.sh build/issue-<n> --test-build`: Testversion. Sie enthält nur Code-pck und `Starten.cmd` und nutzt die exe und das Daten-pck aus `build/main`.
- Bestandteile:
  - `BaustellenManager.exe` ändert sich nur mit der Godot-Version.
  - `BaustellenManager.pck` (Code, ~1 MB) ändert sich bei jedem Fix.
  - `BaustellenManager-Daten.pck` (~230 MB) wird nur neu gebaut, wenn sich Assets oder Demokarte ändern (`daten.hash`).
- Die Version kommt aus `git describe` und erscheint im Menü und in jeder Meldung.

## 6. Auf Jonathans PC liefern

Details und Stolperfallen stehen in [pc-bruecke.md](pc-bruecke.md). Kurz:
- **Testversion:** nach `build/issue-<n>/` auf dem PC (`BaustellenManager.pck`, `Starten.cmd`, `LIESMICH.txt`, `portable.txt`).
- **Stand von main:** nach `build/main/`, nur aus main und nur nach erfolgreichem Zusammenführen.
  - Das Daten-pck nur übertragen, wenn sich `daten.hash` unterscheidet und die eigenen Assets nicht älter sind (Lektion daten-pck-aelter).
- Spielstände, Karten, Meldungen und Logs liegen in `Tiefbau Tycoon/userdata/` und werden nie überschrieben.

## 7. Abschluss

Definition of Done steht in `CLAUDE.md`. Danach den Skill `lernen` ausführen.
