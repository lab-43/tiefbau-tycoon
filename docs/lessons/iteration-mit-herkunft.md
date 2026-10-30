---
titel: Wer Höhen iterativ aus Abständen zu anderen Höhen rechnet, merkt sich die Herkunft – sonst hebt sich ein Bauwerk über sich selbst hinweg
bereich: karte
datum: 2026-10-30
pruefung: e2e:bruecken
---

**Was passiert ist:** Meldung #32. Brücken müssen lichte Höhe über dem halten, was darunter liegt – und das kann selbst angehoben sein. Ich habe deshalb mehrere Runden gerechnet, bis sich nichts mehr ändert. Auf Jonathans Karte blieb die Änderung bei 1,43 m stehen (6 Runden, keine Ruhe): Eine Fußgängerbrücke über einem Weg hob über ihre eigenen Rampen den Weg darunter an, der Weg hob dadurch die Brücke, und so weiter. Gefunden erst, als jede Runde den Abschnitt mit der größten Änderung ausgab (`stats.worst_link`).
**Ursache:** Die Höhe darunter wurde genommen, ohne zu wissen, woher sie kam.
**Regel:**
- Jede berechnete Höhe trägt ihre Herkunft (hier: Brückenkette, `origins`/`chain`). Stammt die Höhe darunter von derselben Kette, wird ab Boden gemessen.
- Iterationen haben eine Obergrenze und melden pro Runde, wo sich am meisten geändert hat. Der Test prüft, dass die Lösung zur Ruhe kommt (`bridge_test.gd`: weniger als 6 Runden).
