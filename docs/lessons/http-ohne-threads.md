---
titel: HTTPRequest nie mit use_threads = true
bereich: netz
datum: 2026-10-27
pruefung: lint:http-ohne-threads
---

**Was passiert ist:** Beim Hamburg-Test hing das Spiel minutenlang mit „Keine Rückmeldung“, mehrfach hintereinander (Log: 00:20 → 04:15).

**Ursache:** Mit `use_threads = true` arbeitet HTTPRequest mit blockierenden Sockets. `cancel_request()` und das Timeout warten auf den Thread. Dieser hängt, bis der Server antwortet, und so lange steht der Hauptthread.

**Regel:**
- Immer `use_threads = false`, also den Standard.
- Für große Downloads `download_chunk_size` erhöhen (1 << 18 bis 1 << 20).
- Getestet wird mit einem Server, der die Verbindung annimmt und nie antwortet.
