---
titel: Godot folgt nur 301/302 – andere Weiterleitungen selbst verfolgen
bereich: netz
datum: 2026-10-27
pruefung: manuell: lokaler Redirect-Server (siehe geofabrik.gd _download)
---

**Was passiert ist:** Der Geofabrik-Download scheiterte. Der Server antwortet mit HTTP 307, und Godot meldete das als Fehler.

**Regel:**
- Downloads gehen über die Weiterleitungsschleife in `src/map/geofabrik.gd`: REDIRECTS 301/302/303/307/308 und `_location()`.
- Das gilt auch für HEAD und die MD5-Datei.
- Bei jeder neuen Datenquelle mit `curl -sSIL <url>` prüfen, welche Weiterleitungen kommen.
