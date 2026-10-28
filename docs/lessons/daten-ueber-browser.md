---
titel: Externe Testdaten über den eingebauten Browser holen und Jonathan die Datei verschieben lassen
bereich: pc-bruecke
datum: 2026-10-28
pruefung: manuell: curl im Container und in der Geräte-Shell probieren, bevor man auf einen Server baut
---

**Was passiert ist:** Meldung #8. Weder der Container noch die Geräte-Shell auf dem PC erreichten tiles.mapterhorn.com, s3.amazonaws.com oder download.geofabrik.de (curl: `000`). Das Spiel unter Windows erreicht sie. Der eingebaute Browser der Claude-App (`mcp__remote-devices__Claude_Browser__*`) erreichte sie ebenfalls. Per `javascript_tool` ließen sich die Kacheln laden, im Browser auswerten (Höhenprofile) und als eine Datei herunterladen. Die Datei landet im Download-Ordner. Die Freigabe für diesen Ordner lehnte die Rechteprüfung ab, Jonathan hat die Datei nach `private/` verschoben.
**Regel:**
- Erreichbarkeit zuerst prüfen: `curl -sS -o /dev/null -w "%{http_code}"` im Container und in der Geräte-Shell.
- Wenn nur der Browser durchkommt: im Browser laden, mit JavaScript auswerten (kleine Ergebnisse kommen direkt zurück) und große Daten als eine Datei herunterladen. Jonathan bitten, sie nach `Tiefbau Tycoon\private\` zu verschieben, dann per `device_stage_files` holen.
- Keine großen Binärdaten über die Rückgabe von `javascript_tool` schicken, das kostet den ganzen Kontext.
