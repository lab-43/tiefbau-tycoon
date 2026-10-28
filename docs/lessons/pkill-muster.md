---
titel: pkill -f mit [x]-Muster
bereich: werkzeuge
datum: 2026-10-27
pruefung: lint:pkill-muster
---

**Was passiert ist:** `pkill -f "http.server 8770"` beendete die eigene Shell (exit 144), weil deren Kommandozeile das Muster enthält.

**Regel:** `pkill -f "http[.]server 8770"` schreiben. Die Klammer verhindert, dass das Muster sich selbst trifft.

**Nochmals (#8):** Ein Einzeiler `pkill -f "_tmp_probe" ; rm …; tools/test.sh …` beendete sich selbst (exit 144), die Tests liefen nie. Die Regel gilt auch für Befehle, die man in der Session tippt, nicht nur für Skripte.
