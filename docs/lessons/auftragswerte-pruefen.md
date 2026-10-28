---
titel: Zahlen und Annahmen aus einem Auftrag gegen echte Daten prüfen und Abweichungen begründet umsetzen
bereich: ablauf
datum: 2026-10-28
pruefung: manuell: Werte in balance.gd mit Quelle oder als „geschätzt“ kommentieren
---

**Was passiert ist:** Meldung #24. Der Auftrag nannte den Nooteboom MCOS-48-03 als zweiten Tieflader für den 39-t-Raupenbagger. Recherche (Händlerangaben): 48 t zulässig, 11,5 t leer, also rund 36,5 t Nutzlast – zu wenig. Der im Auftrag als Alternative genannte MCOS-58-04 (58 t, 15,6 t leer, ≈ 42 t) trägt ihn. Ohne Prüfung wäre entweder ein unrealistischer Wert in `balance.gd` gelandet oder die Nutzlastprüfung hätte den Transport verhindert.

**Regel:**
- Werte für Fahrzeuge (Gewicht, Nutzlast, Tempo, Preis) recherchieren; Quelle oder „Schätzung“ als Kommentar in `balance.gd`.
- Widerspricht eine Annahme im Auftrag den Daten: die realistische Variante umsetzen, wenn der Auftrag sie zulässt, und Jonathan die Abweichung mit Begründung nennen (CLAUDE.md, Regel „Ehrlich bleiben“). Sonst fragen.
