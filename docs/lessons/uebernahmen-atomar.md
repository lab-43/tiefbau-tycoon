---
titel: Übernahmen und Sperren – eine Verzeichnisliste, nichts umschreiben
bereich: werkzeuge
datum: 2026-10-28
pruefung: e2e: tools/agent/test_issues.sh (CI und merge.sh)
---

**Was passiert ist:** Die erste Fassung von `issues.py claim` hatte zwei Fehler.
- Sie prüfte „frei?“ und die nächste Nummer aus zwei verschiedenen Verzeichnislisten. Zwei Sessions bekamen beide „OK“.
- Herzschlag und Freigabe schrieben `owner.json` neu. Ein Leser, der die Datei mitten im Schreiben traf, sah eine freie Übernahme.

Dazu kamen:
- Freigabe und Rückfrage gingen ohne eigene Übernahme.
- Zwei gleichzeitige `create` konnten dieselbe Nummer bekommen.

**Regel:**
- Frei-Prüfung und neue Generation kommen aus **einer** Liste. `mkdir <n+1>` ist der atomare Schritt; wer verliert, bekommt FileExistsError.
- Einmal geschriebene Dateien werden nicht umgeschrieben. Lebenszeichen werden angehängt (`herzschlag`), die Freigabe ist eine neue Datei (`freigegeben`). Löschen geht auf dem PC-Mount ohnehin nicht.
- Nummern werden mit `mkdir .ids/<n>` reserviert, im Spiel genauso.
- Verlaufszeilen haben eine `eid`. Wer anhängt, prüft, dass seine Zeile angekommen ist.
- Jede Änderung an `issues.py` braucht einen grünen Lauf von `tools/agent/test_issues.sh`.
