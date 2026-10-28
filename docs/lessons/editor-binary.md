---
titel: Mit dem Editor-Binary lässt sich kein Export-Verhalten testen
bereich: build
datum: 2026-10-27
pruefung: manuell: Release-Vorlage wie unten; e2e:altstand prüft Skriptfehler im Log
---

**Was passiert ist:** Der Test des portablen Modus war ungültig. Das Linux-Binary ist der Editor und hat das Feature „editor“, deshalb läuft er andere Pfade als die exportierte Windows-exe. Ein Linux-Export-Template ist nicht vorhanden.

**Regel:**
- Exportpfade über Schalter testbar machen (`--data-pack=`, `--main-pack`).
- Den Windows-Build auf Jonathans PC als „noch nicht unter Windows geprüft“ kennzeichnen, bis er es bestätigt.

**Noch einmal (Meldung #23, Absturz beim Laden):** Jonathans Spiel stürzte beim Laden eines Spielstands ab („Godot Engine funktioniert nicht mehr“). Im Container war es nur ein `SCRIPT ERROR: Out of bounds get index '122657'` in `SiteLayout.setup`, danach lief alles weiter. Die Release-Vorlagen prüfen solche Fehler nicht: Ein fehlgeschlagener Zugriff liefert dort stillschweigend `null`, und der nächste typisierte Zugriff darauf stürzt nativ ab.

**Regel (ergänzt):**
- Jeder `SCRIPT ERROR` im Editor-Log ist bei Jonathan ein möglicher Absturz. Nicht als harmlos abtun.
- Release-Verhalten im Container nachstellen: die Linux-Release-Vorlage holen (wie `tools/agent/fetch_templates.py`, nur mit `templates/linux_release.x86_64` statt der Windows-Dateien, per Range-Request). Das Code-pck mit `test/` exportieren (in `export_presets.cfg` für den Lauf `test/*` aus `exclude_filter` von „Windows Desktop“ nehmen, `--export-pack "Windows Desktop" x.pck`, danach die Datei zurücksetzen). Starten mit `linux_release.x86_64 --headless --main-pack x.pck -- --data-pack=build/main/BaustellenManager-Daten.pck --e2e=repro --issue=<ordner>`. Ausgabe mit `stdbuf -oL` umleiten, sonst geht sie beim Absturz verloren. Bei #23: alter Code „Segmentation fault“ direkt nach „Karte bereit“, mit Fix lädt alles.

