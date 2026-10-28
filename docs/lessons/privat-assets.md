---
titel: Private Assets nie ins Git, nie in den Spielordner schreiben
bereich: ablauf
datum: 2026-10-28
pruefung: lint:privat-assets
---

**Hintergrund:** Die Modelle stammen aus Jonathans Construction-Simulator-Installation und einem FS25-Mod. Sie sind nur für den privaten Gebrauch.

**Regel:**
- `game/assets/consim/`, `game/assets/barriers/`, `tools/consim_extract/` und `tools/fs-i3d/` sind in `.gitignore`. Die beiden Werkzeuge enthalten Schlüssel-Konstanten.
- Neue Sessions holen die Assets aus `Tiefbau Tycoon/private/assets.tar` auf dem PC (Skill `tycoon-dev`).
- Builds (.pck/.exe) kommen nicht ins Git, weil sie die Modelle enthalten.
- In den Steam-Spielordner wird nie geschrieben.
- `tools/lint.py` prüft das.
