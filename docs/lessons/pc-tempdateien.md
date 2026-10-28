---
titel: Hilfsdateien der Geräte-Shell nach /tmp schreiben, nie in den verbundenen Ordner
bereich: pc-bruecke
datum: 2026-10-29
pruefung: manuell: nach Arbeiten in der Geräte-Shell `git status --short` im PC-Klon ist leer
---

**Was passiert ist:** Meldung #24. Zum Vergleichen der Assets lief in der Geräte-Shell `cd "$HOME/mnt/Tiefbau Tycoon" && find … | xargs sha256sum > userdata_tmp_sha.txt`. Die Datei landete im Hauptordner von Jonathans Git-Klon. Ein anschließendes `mv … /tmp/` meldete `mv: cannot remove 'userdata_tmp_sha.txt': Operation not permitted`, weil Löschen im verbundenen Ordner ohne Freigabe verboten ist. Die Datei liegt jetzt in `private/_to_delete/` und muss von Jonathan gelöscht werden.

**Ursache:** Ein relativer Ausgabepfad nach `cd` in den verbundenen Ordner. Schreiben geht dort, Löschen nicht.

**Regel:**
- Zwischenergebnisse der Geräte-Shell immer mit absolutem Pfad nach `/tmp/…` schreiben (`> /tmp/x.txt`). `/tmp` liegt außerhalb von `mnt/` und darf beliebig beschrieben werden.
- In den verbundenen Ordner nur, was dort bleiben soll (Builds, Assets, Meldungen über `issues.py`).
- Ist doch etwas falsch gelandet: innerhalb desselben Ordners nach `private/_to_delete/` verschieben (Umbenennen geht) und Jonathan Bescheid geben.
