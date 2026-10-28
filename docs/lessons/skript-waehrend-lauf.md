---
titel: Ein laufendes Shell-Skript nicht ändern – Bash liest es während der Ausführung weiter
bereich: werkzeuge
datum: 2026-10-28
pruefung: manuell: lange Testläufe aus einer Kopie starten (cp tools/test.sh /tmp/…) oder erst nach dem Lauf editieren
---

**Was passiert ist:** Meldung #24. `tools/test.sh smoke issue lowbed` lief im Hintergrund, währenddessen kam ein neuer `case`-Zweig in dieselbe Datei. Der Lauf endete nach dem grünen lowbed-Test mit `line 75: syntax error near unexpected token ';;'` und Exit 2, obwohl `bash -n tools/test.sh` die neue Fassung für fehlerfrei hielt.

**Ursache:** Bash liest ein Skript nicht vorab ein, sondern während der Ausführung an der jeweiligen Byte-Position weiter. Ändert sich die Datei, liest es ab der alten Position in den neuen Inhalt hinein.

**Regel:**
- `tools/test.sh`, `tools/agent/merge.sh` und andere Skripte nicht bearbeiten, solange sie laufen (auch `git rebase` ändert sie!).
- Für lange Hintergrundläufe eine Kopie starten oder den Lauf vorher abwarten.
- Ein Syntaxfehler mitten in einem Testlauf, den `bash -n` nicht bestätigt, ist dieser Fall: Lauf wiederholen, nicht den Code „reparieren“.
