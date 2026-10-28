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

1. Datei nach `/mnt/user-data/outputs/<ordner>/` kopieren.
2. Bis 10 MB direkt: `device_commit_files` mit `stagedPath` und `devicePath`. Bis 50 Dateien und 100 MB pro Aufruf.
3. Größer: `split -b 10M -d -a 2 datei datei.part` und die Teile nach `build/_transfer/` übertragen, dann auf dem PC `cat datei.part?? > ziel`. Eine einzelne Datei über ~25 MB mit `stagedPath` scheiterte mit HTTP 400 (Lektion pc-grosse-dateien).
4. Prüfen: `sha256sum` im Container (mit relativen Namen, Lektion pruefsummen-relativ) und auf dem PC vergleichen. Danach `build/_transfer/` löschen.
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
