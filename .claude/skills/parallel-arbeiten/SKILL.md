---
name: parallel-arbeiten
description: Use this skill before changing anything in the Tiefbau Tycoon repo. Several Claude sessions work in parallel on different areas. It covers claiming the work, branching, committing small, rebasing, auto-merging into main with tests, conflict handling, and the shared PC folders (build/, userdata/).
---

# Parallel arbeiten – mehrere Sessions, ein Repo

Jonathan lässt mehrere Sessions gleichzeitig laufen, meist in verschiedenen Bereichen. Jede Session hat ihren eigenen Klon im eigenen Container. Gemeinsam genutzt werden:
- **GitHub `main`**: wird automatisch zusammengeführt, nur getestet und nur vorwärts.
- **Jonathans PC**:
  - `userdata/issues`: Meldungen und Übernahmen,
  - `build/main`: das Spiel, das er startet,
  - `build/issue-<n>`: Testversionen.

## Die Regeln

1. **Erst schauen, dann anfangen.**
   - `bash tools/agent/session_start.sh` zeigt neue Commits auf main und andere Branches.
   - `issues.py claims` in der Geräte-Shell zeigt, wer welche Bereiche bearbeitet.
2. **Jede Arbeit ist eine übernommene Meldung**, auch Aufträge aus dem Chat (Skill issue-ablauf, Abschnitt „Aufgaben aus dem Chat“). Die Übernahme nennt Branch und Bereiche. So sieht jede Session, was läuft.
3. **Eigener Branch:** `issue/<n>-<kurz>` von aktuellem `origin/main`.
   - Gibt die Umgebung einen Branch vor (z. B. `claude/…`), diesen nehmen und in der Übernahme angeben.
   - Nie direkt auf main committen.
4. **Klein und oft:** Ein Commit pro logischem Schritt, jeder Commit kompiliert (`tools/check.sh`). Teilergebnisse, die grün sind, früh zusammenführen. Ein großer Merge am Ende provoziert Konflikte.
5. **Hotspots schonen.** `site.gd`, `vehicle.gd`, `traffic_sim.gd`, `hud.gd`, `e2e_driver.gd`, `balance.gd`, `project.godot` und `export_presets.cfg` fassen fast alle an. Dort gilt:
   - nur die nötigen Zeilen ändern,
   - nichts umformatieren, umsortieren oder umbenennen, was nicht zur Aufgabe gehört,
   - neue Funktionen an das Ende ihres Abschnitts setzen,
   - neue Systeme lieber in neue Dateien legen.
6. **Zusammenführen nur mit `tools/agent/merge.sh`** (Option `--e2e=job` usw. für die passenden Tests). Das Skript macht:
   - fetch,
   - rebase auf origin/main,
   - lint, check und Tests (smoke + issue + die gewählten Szenarien),
   - fast-forward-Push nach main,
   - wenn main sich inzwischen bewegt hat: alles wiederholen,
   - wenn der direkte Push hier nicht erlaubt ist: Branch mit `Automerge: ja` pushen. Die CI führt dann nach grünen Tests zusammen.
7. **Konflikt beim Rebase:**
   - Die andere Änderung ist schon getestet auf main, also beide Absichten erhalten.
   - Danach müssen die vollen Tests laufen.
   - Wenn unklar ist, was die andere Session wollte: `git log origin/main -p -- <datei>` und deren Meldung lesen (`issues.py show`).
   - Immer noch unsicher? `git rebase --abort` und im eigenen Meldungsverlauf beschreiben, was kollidiert.
8. **Verboten:**
   - `git push --force` auf main,
   - fremde Branches umschreiben,
   - fremde Übernahmen freigeben,
   - `git reset --hard origin/...` mit eigener, nicht gesicherter Arbeit.
   - Den eigenen Branch nur mit `--force-with-lease` überschreiben.
9. **PC-Ordner:**
   - Nur in das eigene `build/issue-<n>/` schreiben.
   - `build/main` nur nach erfolgreichem Merge und nur mit einem Stand, der neuer ist als der dort liegende (`VERSION.txt`, siehe tycoon-dev/pc-bruecke.md).
   - `userdata/` nur über `issues.py` (Meldungen) beschreiben, sonst nur lesen.
10. **Gemeinsame Dateien im Repo:** Lektionen sind eine Datei pro Lektion, also gibt es keine Konflikte. Bei `docs/MVP-Umsetzung.md` nur den eigenen Abschnitt anhängen.

## Wenn etwas schiefgeht

- **Tests auf main rot nach fremdem Merge:**
  - Nicht auf main reparieren, sondern eine Meldung anlegen (`issues.py create --type fehler --area werkzeuge`).
  - Ist sie klein und eindeutig, selbst übernehmen.
  - Die Session des verursachenden Commits steht in der Commit-Nachricht (`Claude-Session:`).
- **Verwaiste Übernahme** (Herzschlag > 6 h): gilt automatisch als frei. Vor dem Übernehmen den Branch der alten Session anschauen (`git log origin/<branch>`) und Brauchbares weiterverwenden.
- **PC offline:** Übernahmen gehen nicht. Branch früh pushen (`git push -u origin HEAD`), damit andere Sessions ihn im Lagebericht sehen. Bereich und Ziel in die erste Commit-Nachricht schreiben.

## Commit-Nachrichten

```
<Bereich>: <was> (#<meldung>)

<warum, was getestet>

Co-Authored-By: …            (Zeilen laut Session-Vorgabe)
Claude-Session: …
```
