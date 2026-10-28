---
name: lernen
description: Use this skill at the end of every Tiefbau Tycoon task, and whenever a mistake, detour, surprising engine behaviour or user correction happened. It turns the experience into a lesson file in docs/lessons and, where possible, a lint rule or test so the next session does not repeat it. Also use it before starting work, to read the lessons for the area.
---

# Lernen – jede Session macht die nächste klüger

Das Gedächtnis dieses Projekts besteht aus drei Teilen:
- `docs/lessons/*.md`: eine Datei pro Lektion. Die Titel erscheinen beim Sitzungsstart.
- `tools/lint.py`: Lektionen, die sich maschinell prüfen lassen.
- Tests (`tools/test.sh`, e2e-Szenarien): Lektionen über Spielverhalten.

## Vor der Arbeit

- Die Lektionen des Bereichs lesen: `grep -l "bereich: <bereich>" docs/lessons/*.md`.
- Bei GDScript zusätzlich den Skill `godot-fallen`.

## Nach der Arbeit (Pflicht, dauert 2 Minuten)

Frage dich ehrlich:
1. Was hat länger gedauert als nötig? Warum?
2. Welche Annahme war falsch? Woran hätte ich es früher merken können?
3. Hat Jonathan etwas korrigiert oder nachgefragt, weil etwas fehlte?
4. Welches Engine- oder Werkzeugverhalten hat überrascht?
5. Gibt es einen Fehler, den ein Test hätte fangen müssen?

Für jeden Punkt mit einer **allgemeinen Regel**:

1. **Gibt es schon eine Lektion dazu?** (`grep -ri "<stichwort>" docs/lessons`)
   - Ja: diese ergänzen oder präzisieren, kein Duplikat anlegen.
   - Nein: neue Datei `docs/lessons/<kurzer-slug>.md` nach `docs/lessons/README.md`. Darin konkret beschreiben: was passiert ist, mit Datei und Fehlertext, die Ursache und die Regel.
2. **Prüfbar machen**, wenn es geht:
   - Ein Muster im Code: Regel in `tools/lint.py` mit `[Lektion: <slug>]` ergänzen und gegen eine absichtliche Verletzung testen. Dann `pruefung: lint:<slug>`.
   - Spielverhalten: Assertion oder Szenario im e2e-Treiber, dann `pruefung: e2e:<szenario>`.
   - Sonst `pruefung: manuell: <wie man es prüft>`.
3. **Skill anpassen**, wenn die Lektion einen Ablauf ändert, z. B. einen neuen Schritt in issue-ablauf oder eine neue Falle in godot-fallen. Skills kurz halten; Details gehören in die Lektion.
4. Mit der eigentlichen Arbeit committen und zusammenführen. Lektionen sind normale Repo-Dateien, so bekommen alle Sessions sie.

## Was keine Lektion ist

- Einmalige Tippfehler ohne Muster.
- Der Inhalt der Änderung selbst. Der steht in Commit und Meldung.
- Vermutungen, die nicht geprüft wurden. Eine Lektion beschreibt, was wirklich passiert ist.

## Ehrlichkeit

Jonathan will keine Schönfärberei. Wenn etwas nicht getestet werden konnte (z. B. Windows-spezifisch), gehört das in den Bericht und, falls es ein Muster ist, als Lektion festgehalten.
