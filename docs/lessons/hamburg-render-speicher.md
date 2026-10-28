---
titel: Hamburg im Container nur aus der gespeicherten Karte und mit kurzen Blickweiten rendern
bereich: werkzeuge
datum: 2026-10-28
pruefung: manuell: dmesg | tail nach „Killed“
---

**Was passiert ist:** Meldung #8. `tools/gd.sh run -- --e2e=repro … --views=…` wurde mehrmals mit „Killed“ beendet (dmesg: `Memory cgroup out of memory … godot anon-rss:4013536kB, shmem-rss:2051584kB`). Der Container hat 8 GB. Der Software-Renderer (Mesa/lavapipe) braucht für Hamburg schon ohne Gelände 5,9 GB, sobald fast die ganze Karte im Bild ist (Übersicht aus 5 km). Direkt nach dem Aufbereiten liegen die Bake-Daten zusätzlich im Speicher.
**Regel:**
- Erst einmal aufbereiten lassen (Lauf darf danach abbrechen), dann einen zweiten Lauf aus der gespeicherten Karte rendern.
- Blickweiten bis etwa 700 m und Neigung ab etwa 12°, keine Übersicht aus mehreren Kilometern.
- Ein Abbruch mit „Killed“ ist der Container, kein Spielfehler. Auf Jonathans PC (GTX 1080 Ti) gilt das nicht.
