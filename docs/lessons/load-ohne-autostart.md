---
titel: Das Lade-Szenario ohne --autostart starten
bereich: werkzeuge
datum: 2026-10-28
pruefung: e2e: save+load (tools/test.sh)
---

**Was passiert ist:** `tools/test.sh save+load` meldete „E2E FAIL: no active job after load“, obwohl der Spielstand den Auftrag enthielt. `--autostart` gründete parallel eine neue Firma und überschrieb den geladenen Stand.

**Regel:**
- Szenarien, die einen Spielstand fortsetzen (`load`, `repro`), laufen ohne `--autostart`. Die Karte kommt aus dem Spielstand (`dev_utrecht`).
- Bevor ein Testfehler als Spielfehler gilt, erst den Spielstand mit einem kleinen Leseskript prüfen. Das bestätigt oder widerlegt die Vermutung in Sekunden.
