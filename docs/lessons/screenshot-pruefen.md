---
titel: Sichtbare Änderungen mit Screenshot prüfen
bereich: ui
datum: 2026-10-27
pruefung: manuell: tools/gd.sh shot / e2e --shots
---

**Regel:**
- Jede Änderung an Oberfläche oder Grafik wird gerendert (xvfb + Vulkan/Mesa) und angesehen, bevor sie als fertig gilt.
- Auch Abschneiden, Überlappen und Kontrast prüfen.
- Bei Meldungen das Repro-Bild neben das Bild aus der Meldung legen.
