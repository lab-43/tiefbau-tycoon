---
titel: Neue e2e-Szenarien in eine eigene Datei, im Treiber nur eine Zeile
bereich: werkzeuge
datum: 2026-10-28
pruefung: manuell: git diff von game/test/e2e_driver.gd bleibt bei neuen Szenarien klein
---

**Was passiert ist:** Drei Sessions haben am selben Nachmittag je ein e2e-Szenario angelegt (leuchten, verkehrslichter, debug). Alle hängten ihren `match`-Zweig in `game/test/e2e_driver.gd` an dieselbe Stelle und erweiterten dieselbe Kopfzeile in `tools/test.sh`. Beim Rebase gab es deshalb zweimal Konflikte. Sie waren leicht zu lösen, kosteten aber eine zusätzliche Testrunde von etwa 15 Minuten.

**Regel:**
- Die Logik eines neuen Szenarios kommt in `game/test/e2e_<name>.gd` (RefCounted mit `tick(delta)`, Vorbild `e2e_debug.gd`).
- Im Treiber stehen nur der `match`-Zweig und eine kleine Startfunktion.
- In `tools/test.sh` die Zeile ans Ende der `case`-Liste setzen, nicht in die Mitte.
- Bei einem Konflikt beide Zweige behalten.
