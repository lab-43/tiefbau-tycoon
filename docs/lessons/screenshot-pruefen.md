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
- Die Renderer-Zeile direkt nach dem Godot-Banner muss `Vulkan … Forward+` zeigen.
  - Fehlt der Mesa-Vulkan-Treiber (`/usr/share/vulkan/icd.d/lvp_icd*.json`), fällt Godot auf den Kompatibilitäts-Renderer (gles3) zurück.
  - Das fällt leicht durch: Es gibt nur eine Warnung „switching to OpenGL 3“, die in der Ausgabe untergeht. Fehler kommen dann aus `drivers/gles3/…`.
  - Die Bilder weichen dann von Jonathans PC ab: Bei #4 war der Boden beige statt grau.
  - `setup_env.sh` installiert den Treiber. `session_start.sh` und `gd.sh run/shot` melden, wenn er fehlt (2026-10-28).
