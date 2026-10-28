---
titel: Fremde Bibliotheken vorher auf erreichbare Quellen prüfen – gitlab.com ist gesperrt
bereich: werkzeuge
datum: 2026-10-28
pruefung: manuell: cargo fetch / npm install / pip download einmal im Container laufen lassen, bevor man auf die Bibliothek baut
---

**Was passiert ist:** Für die osm2streets-Probe (#5) brach `cargo build` ab: `failed to get muv-osm … CONNECT tunnel failed, response 403`. `muv-osm` liegt nur auf gitlab.com. Der Proxy des Containers erlaubt GitHub und die Paketregister (crates.io-Index, npm, PyPI), aber nicht gitlab.com. Die Geräte-Shell auf Jonathans PC hat dieselbe Sperre (`git ls-remote https://gitlab.com/…` → 403). Die GitHub-Suche (`gh search`) ist in Sessions ebenfalls gesperrt. Ausweg war der letzte Commit vor der Umstellung auf muv (`e277778`, März 2024).

**Ursache:** Die Netzwerkfreigabe gilt pro Host. Git-Abhängigkeiten außerhalb von GitHub tauchen erst beim ersten Bauen auf.

**Regel:**
- Bevor man eine fremde Bibliothek einplant: `Cargo.toml`/`Cargo.lock`, `package.json` oder `requirements` nach `git = "https://…"` durchsehen. Alles außer github.com und den Paketregistern gilt als nicht erreichbar.
- Für so eine Abhängigkeit braucht es einen Plan: älteren Stand ohne sie nehmen, das Paket aus einem Register beziehen oder Jonathan um eine Kopie bitten. Den Plan in die Meldung schreiben.
- Lange Builds von fremdem Code nicht mit `&` im Hintergrund starten, sondern als eigenen Befehl im Vordergrund mit großem Timeout. Die gemischte Variante wurde einmal von der Rechteprüfung abgelehnt.
