---
titel: Externe Server erst prüfen, dann einbauen
bereich: netz
datum: 2026-10-27
pruefung: manuell: Betreiber und Nutzungsregeln in docs nennen
---

**Was passiert ist:** Jonathan fragte, warum eine .ru-Domain im Spiel steckt. maps.mail.ru stand als öffentlicher Overpass-Server im OSM-Wiki, wird aber von VK (Russland) betrieben. Außerdem war der Server langsam.

**Regel:**
- Vor dem Einbau eines externen Dienstes klären: Betreiber, Land, Nutzungsregeln (Rate-Limits, User-Agent).
- Das Ergebnis kurz in `docs/MVP-Umsetzung.md` vermerken.
- Keine persönlichen Daten an Dienste schicken; der User-Agent nennt keine Mail-Adresse.
