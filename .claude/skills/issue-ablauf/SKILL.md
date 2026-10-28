---
name: issue-ablauf
description: Use this skill for the in-game issues ("Meldungen") Jonathan reports with F8 in Tiefbau Tycoon. It covers finding the next one, claiming it, reading all data, reproducing, fixing, asking questions, handing over a test build and closing. Also use it when a task comes from chat and needs to be registered so parallel sessions see it.
---

# Meldungen abarbeiten

Jonathan meldet im Spiel mit **F8**. Eine Meldung ist ein Ordner `Tiefbau Tycoon/userdata/issues/<nnnn>-<slug>/` auf seinem PC:

| Datei | Inhalt |
|---|---|
| `issue.json` | Titel, Text, Art (fehler/wunsch/verbesserung/aufgabe), Bereich, Priorität, Herkunft (welt/ladebildschirm/menue/agent), Kamera, Auswahl, Spielzustand, Build-Version, Markierungen (Pins mit Weltposition), Systeminfo |
| `beschreibung.md` | lesbare Fassung |
| `bild_N.png`, `bild_N_markiert.png` | Screenshots, markierte Stellen als Kreise |
| `spielstand.sav` | Spielstand im Moment der Meldung (falls angehakt) |
| `zustand.json` / `zustand.txt` | Zustand von Baustellen, Fahrzeugen und Verkehr |
| `logs/` | Ende von `spiel.log` (mit GDScript-Backtraces), `meldungen_im_spiel.txt`, `laden.log` |
| `verlauf.jsonl` | **nur anhängen**: Rückfragen, Antworten, Pläne, Status. Status = letzter Eintrag mit `status` |
| `claims/<n>/` | wer gerade daran arbeitet: `owner.json` (Session, Branch, Bereiche), `herzschlag`, `freigegeben` |

Status: `offen` → `in_arbeit` → (`rueckfrage` ↔ Antwort) → `bitte_pruefen` → `erledigt` (oder `abgelehnt`). „Behoben“/„Nicht behoben“ klickt Jonathan im Spiel. Das Spiel zeigt `rueckfrage` und `bitte_pruefen` als Zähler an der Fahne in der linken Leiste.

## Werkzeug

Alles läuft über `tools/agent/issues.py` **in der Geräte-Shell** (`device_bash`, Python 3.10 auf dem PC), denn nur dort sind Übernahmen atomar. Der PC-Klon wird selten aktualisiert. Deshalb gibt es eine Agentenkopie unter `userdata/.agent/issues.py`, die jede Session aktuell hält. Sie wird nur durch eine **neuere** Fassung ersetzt (`VERSION` im Skript):

```
# einmal pro Session: Fassung auf dem PC prüfen (gibt die VERSION aus)
cd "$HOME/mnt/Tiefbau Tycoon"; I=tools/agent/issues.py; [ -f userdata/.agent/issues.py ] && I=userdata/.agent/issues.py; python3 $I --version
# Ist die Container-Fassung (python3 tools/agent/issues.py --version) höher: per device_commit_files
# nach userdata/.agent/issues.py schreiben. Niedriger oder gleich: nichts tun.
# danach immer:
cd "$HOME/mnt/Tiefbau Tycoon"; I=tools/agent/issues.py; [ -f userdata/.agent/issues.py ] && I=userdata/.agent/issues.py; python3 $I next
```

- Der Meldungsordner wird automatisch gefunden (`userdata/issues`) und auf stderr ausgegeben. Im Container gibt es keinen. Dort `issues.py` nicht verwenden, denn die Meldungen liegen nur auf dem PC.
- Wer an `issues.py` etwas ändert, erhöht `VERSION`.
- Die Session-ID (`--session S`) ist eine kurze eindeutige Kennung, z. B. die letzten 8 Zeichen der Claude-Session-URL. Sie bleibt während der ganzen Session gleich.
- Das Datenformat bleibt abwärtskompatibel, weil andere Sessions mit älteren Fassungen gleichzeitig arbeiten können. Betroffen sind `verlauf.jsonl` (nur anhängen), `claims/<n>/` und `.ids/`. Das Spiel liest dieselben Regeln (`IssueStore`).
- `ask`, `plan`, `fix`, `status` und `release` gehen nur mit eigener Übernahme (sonst Exit 2). `comment` darf jede Session.

## Ablauf

1. **Auswählen:** `issues.py next` zeigt die nächste freie Meldung nach Priorität und welche Bereiche andere gerade bearbeiten. Hat Jonathan eine Nummer genannt, nimm diese.
2. **Übernehmen:** `issues.py claim <n> --session S --branch <branch> --areas <bereiche>`
   - Branch nach Skill parallel-arbeiten: `issue/<n>-<kurz>` oder der Branch, den die Umgebung vorgibt (`claude/…`). In der Übernahme steht der tatsächliche Name.
   - Exit 2 bedeutet: gehört schon jemandem. Dann eine andere nehmen und nie die fremde überschreiben. Exit 3: knapp verloren, neu schauen.
   - Bei einer Warnung wegen eines überlappenden Bereichs geht es trotzdem weiter: klein committen und früh zusammenführen (Skill parallel-arbeiten).
3. **Verstehen:**
   - `issues.py show <n>`: Text, Kontext, Dateiliste, Verlauf.
   - Den ganzen Meldungsordner holen:
     - Dateien auflisten mit `device_list_dir` (rekursiv),
     - alle mit `device_stage_files` holen (`issue.json`, Bilder, `spielstand.sav`, `zustand.*`, `logs/*`). Sie landen unter `/mnt/user-data/uploads/Tiefbau Tycoon/userdata/issues/<ordner>/`.
     - Bilder mit Read **ansehen**, besonders die markierten.
   - Logs lesen (Lektion log-zuerst).
   - Die Build-Version der Meldung mit dem aktuellen main vergleichen. Vielleicht ist es schon behoben.
4. **Reproduzieren:**
   ```
   tools/gd.sh run -- --e2e=repro --issue="/mnt/user-data/uploads/Tiefbau Tycoon/userdata/issues/<ordner>" \
       --watch=60 --out=/tmp/repro-<n>
   ```
   - Das lädt `spielstand.sav`, stellt die Kamera wie in der Meldung, macht `repro_kamera.png` und je Pin `repro_stelle_N.png` und schreibt alle 10 s den Zustand nach `repro.log`.
   - Headless (ohne `run`, mit `godot --headless --path game -- …`) entstehen keine Bilder, nur `repro.log`.
   - Kein `--autostart` verwenden, denn der Spielstand bringt Firma und Karte mit (Lektion load-ohne-autostart).
   - **Echte Karten (Hamburg …):** Der Container erreicht weder Geofabrik noch Overpass. Deshalb die fertige Karte vom PC holen:
     - `userdata/maps/<map-id>/baked_v3.bin` und `map.json` per `device_stage_files` holen (`<map-id>` steht in `issue.json` → `map.id`),
     - nach `~/.local/share/godot/app_userdata/Baustellen Manager/maps/<map-id>/` kopieren.
     - Ohne diese Dateien bricht das Laden ab.
   - Ohne Spielstand: mit `--autostart --fixture=utrecht` an der Stelle nachstellen und, wenn sinnvoll, ein neues e2e-Szenario schreiben.
5. **Unklar? Fragen statt raten:**
   - `issues.py ask <n> --session S --text "…"` setzt den Status `rueckfrage`. Jonathan sieht die Frage im Spiel unter „Meldungen“ und antwortet dort.
   - Konkrete, beantwortbare Fragen stellen, mit Optionen.
   - In der Zwischenzeit etwas anderes machen, nicht blockieren. Die Antwort kommt als Eintrag `answer` in `verlauf.jsonl`.
6. **Plan festhalten:** `issues.py plan <n> --session S --text "Ursache: … Plan: … Betroffene Dateien: …"`. Bei größeren Änderungen zuerst den Plan schreiben.
7. **Beheben:** Code ändern, Lektionen des Bereichs beachten, testen (Skill tycoon-dev). Möglichst einen Test ergänzen, der den Fehler gefangen hätte.
8. **Zusammenführen:** `tools/agent/merge.sh` (Skill parallel-arbeiten).
   - Exit 5 heißt: an die CI übergeben. Dann `tools/agent/merge.sh --wait`, bis main den Fix enthält.
9. **Testversion liefern:**
   - `tools/build.sh build/issue-<n> --test-build` bauen und nach `Tiefbau Tycoon/build/issue-<n>/` übertragen.
   - Danach `build/main` aus dem neuen main aktualisieren, unter der Sperre `issues.py lock build-main` (tycoon-dev/pc-bruecke.md).
   - Dann `issues.py fix <n> --session S --build "build/main" --commit <hash> --text "Was geändert wurde, wie man es prüft"`. Das setzt `bitte_pruefen`.
   - Bilder anhängen mit `--file <pfad> --file <pfad>`. Die Pfade müssen auf dem PC liegen: erst per `device_commit_files` nach `Tiefbau Tycoon/build/issue-<n>/` übertragen. `issues.py` kopiert sie in den Meldungsordner und überschreibt dabei nie Jonathans Bilder.
10. **Freigeben:** `issues.py release <n> --session S --note "…"`. Jonathan schließt mit „Behoben“. Bei „Nicht behoben“ steht die Meldung wieder auf `offen` und wird erneut übernommen.
11. **Herzschlag:** Jeder eigene Eintrag (`plan`, `ask`, `fix`, `status`) zählt als Lebenszeichen. Bei langer Arbeit ohne Einträge alle 1–2 h `issues.py heartbeat <n> --session S`. Nach 6 h ohne Lebenszeichen gilt die Übernahme als verwaist.

## Aufgaben aus dem Chat

Gibt Jonathan eine Aufgabe direkt im Chat, wird sie trotzdem eine Meldung, damit parallele Sessions sie sehen:

```
issues.py create --session S --type aufgabe --area <bereich> --title "…" --text "<Auftrag in Jonathans Worten>"
```

Danach übernehmen (Schritt 2). Ohne PC-Verbindung den Branch sofort pushen (`git push -u origin HEAD`). Dann sehen andere Sessions ihn im Lagebericht.

## Regeln

- In Meldungsordnern nur über `issues.py` schreiben und nichts löschen oder umbenennen. `issue.json` und die Bilder gehören Jonathan.
- Antworten an Jonathan auf Deutsch, kurz und ohne Code-Jargon. Er liest sie im Spiel.
- Ehrlich bleiben: „bitte prüfen“ nur, wenn der Fehler reproduziert und mit Test oder Bild als behoben gezeigt wurde. Sonst sagen, was unsicher ist.
