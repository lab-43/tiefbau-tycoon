---
titel: Eine Karte ohne Geländehöhen liegt als baked_v<N>_flach.bin – nach Änderungen am Aufbereiten beide Dateien löschen
bereich: werkzeuge
datum: 2026-10-29
pruefung: manuell: der Repro-Lauf druckt „E2E HINWEIS: gespeicherte Karte … wird benutzt“ mit dem Dateinamen
---

**Was passiert ist:** Meldung #31. Nach einer Änderung an `TunnelPortals` (Bäume auf Portalen entfernen) wurde `baked_v10.bin` gelöscht und Hamburg neu gerendert. Die Bilder zeigten trotzdem den alten Stand. Im Ladeprotokoll stand „Gespeicherte Karte lesen“. Im Container sind Mapterhorn und AWS nicht erreichbar, die Karte bleibt flach und wird als `baked_v10_flach.bin` gespeichert. Der Repro-Hinweis prüfte nur `baked_v10.bin` und meldete „Karte fehlt“, obwohl die flache Datei benutzt wurde.

**Ursache:** `MapService.prepare` liest `baked_v<N>.bin` oder, wenn keine Höhen zu bekommen sind, `baked_v<N>_flach.bin`. Wer bei gleicher `BAKE_VERSION` am Aufbereiten ändert, muss beide Dateien löschen.

**Regel:**
- Nach Änderungen am Aufbereiten (Mesher, RoadNet, Portale …) ohne Versionssprung: `rm "<maps>/<karte>"/baked_v*.bin` – alle Varianten.
- Der Repro-Lauf nennt jetzt die benutzte Datei („gespeicherte Karte … wird benutzt“). Steht das da, zeigt das Bild nicht den neuen Code.
- Im Ladeprotokoll (`laden.log` im Kartenordner) steht „Karte aufbereiten“ (neu) oder „Gespeicherte Karte lesen“ (alt).
