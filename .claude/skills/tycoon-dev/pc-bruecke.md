# Jonathans PC über die Geräte-Brücke

Die Brücke funktioniert nur, wenn die Claude-Desktop-App auf dem PC läuft und dieser Chat verbunden ist. Prüfen mit `get_device_info`. Geht das nicht: Jonathan Bescheid geben und ohne PC weiterarbeiten. Es gibt keine Meldungen, keine Assets und keine Lieferung, Code und Tests gehen trotzdem.

## Ordner

| Auf dem PC | In der Geräte-Shell (`device_bash`) |
|---|---|
| `C:\Users\Jonathan\Documents\Tiefbau Tycoon` | `$HOME/mnt/Tiefbau Tycoon` |
| `…\build\main\` | aktuelles Spiel (exe, pck, Daten-pck, `portable.txt` → `../../userdata`) |
| `…\build\issue-<n>\` | Testversionen (Code-pck + `Starten.cmd`) |
| `…\userdata\` | Spielstände, Karten, `extracts/`, `issues/`, `logs/spiel.log` – **nie löschen/überschreiben** |
| `…\private\assets.tar` | private Modelle für neue Sessions |
| `%APPDATA%\Godot\app_userdata\Baustellen Manager` | alter Datenordner (vor v1.7, nicht portabel) |
| `C:\Program Files (x86)\Steam\steamapps\common\Construction Simulator` | **tabu, nie schreiben** |

Der PC-Ordner ist ein Git-Klon (Branch main). Dort wird **nicht** entwickelt und nicht committet. Ohne Löschrecht hinterlässt git `.lock`-Dateien. Für ein Update des Klons einmal Löschrecht anfragen und `git pull --ff-only` ausführen. Das ist selten nötig, denn nur `build/` und `userdata/` müssen aktuell sein.

## Dateien übertragen (Container → PC)

1. Datei nach `/mnt/user-data/outputs/<name>` kopieren.
2. Bis ~10 MB: `device_commit_files` mit `stagedPath` und `devicePath`.
3. Größer: zuerst `SendUserFile` (liefert `fileUuid`), dann `device_commit_files` mit `fileUuid`. Grenze 30 MB pro Datei (Lektion pc-grosse-dateien).
4. Über 30 MB (Daten-pck, exe):
   - `split -b 25M -d datei datei.part`, Teile einzeln übertragen nach `build/_transfer/`.
   - Auf dem PC: `cat datei.part* > ziel`.
   - Mit `sha256sum` vergleichen. Relativ erzeugen: erst `cd` in den Ordner (Lektion pruefsummen-relativ).
5. Vorhandene Dateien ersetzen: Schreiben geht, Löschen nicht ohne `device_request_delete_permission`. Den Ordner `Tiefbau Tycoon` einmal pro Session anfragen, wenn aufgeräumt werden muss.
6. Läuft das Spiel gerade, sperrt Windows `BaustellenManager.pck`. In diesem Fall Jonathan bitten, es zu schließen, oder die Testversion in einen neuen Ordner legen.

## build/main aktualisieren (nur nach Zusammenführen)

1. Prüfen, was auf dem PC liegt: `cat "$HOME/mnt/Tiefbau Tycoon/build/main/VERSION.txt" build/main/daten.hash`.
2. Liegt dort schon ein neuerer main-Stand, nichts tun. Das prüft `git merge-base --is-ancestor <pc-commit> HEAD`.
3. `BaustellenManager.pck`, `LIESMICH.txt`, `portable.txt` und `VERSION.txt` übertragen, das Daten-pck nur bei geändertem `daten.hash`.
4. `VERSION.txt` zuletzt schreiben, denn sie markiert den vollständigen Stand.

## Lesen (PC → Container)

- Logs und Meldungen direkt in der Geräte-Shell lesen (`cat`, `tail`, `python3 tools/agent/issues.py show <n>`).
- Bilder und Spielstände für eigene Tests: `device_stage_files` (bis 50 Dateien, je 400 MB). Sie landen unter `/mnt/user-data/uploads/Tiefbau Tycoon/…`.
- Die Geräte-Shell hat python3.10 und git, aber kein Godot. Spieltests laufen immer im Container.
