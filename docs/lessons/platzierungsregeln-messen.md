---
titel: Regeln, die Spieleraktionen verbieten, an der echten Karte messen – wie viele Stellen gehen und warum nicht
bereich: baustelle
datum: 2026-10-30
pruefung: e2e:platzieren (Statistik: mindestens 60 % der Straßenpunkte ohne Brücken nehmen einen Auftrag; Hamburg 87 %, Utrecht 65 %)
---

**Was passiert ist:** Jonathan konnte mit dem Debug-Werkzeug „dauerhaft“ keinen Auftrag platzieren (#33). Die Regeln stammten aus der festen Absperr-Vorlage:
- 34 m Abstand zur Kreuzung vorn und 80 m hinten,
- kein Zebrastreifen und keine Haltestelle im Bereich,
- 160 m Abstand zu anderen Aufträgen,
- höchstens 35° Kurve über die ganze Umleitung.

Einzeln wirkte jede Regel vernünftig. Gemessen auf Jonathans Hamburg-Karte ließen sie nur 34 % der Straßenpunkte zu. Der mittlere Straßenabschnitt ist dort 51 m lang, die Regeln verlangten mindestens 114 m.

**Ursache:** Die Regeln schützten die Annahmen der Vorlage (immer gleich lang, Bus immer davor, Warteplatz immer dahinter). Sie beschrieben nicht das, was physisch nötig ist. Niemand hatte gezählt, wie viele Stellen sie übrig lassen.

**Regel:**
- Jede Bedingung, die eine Spieleraktion ablehnt, wird an einer echten Karte gemessen: Anteil der Stellen, die gehen, und Rangliste der Gründe (`e2e_platzieren.gd`, `_statistics`). Die Zahlen gehören in die Meldung.
- Bedingungen, die nur eine Vorlage schützen, werden zu Hinweisen, und die Vorlage passt sich an (stauchen, ausweichen). Verbieten darf nur, was das Spiel wirklich nicht kann. Der Grund muss dann konkret dastehen („Hinter der Grube fehlen 12 m: …“).
- Hamburg-Karten vom PC lassen sich mit `--autostart --map=<karten-id>` direkt testen (Karte nach `maps/<id>/` im Container kopieren, siehe Skill issue-ablauf).
