---
titel: Neben einem gerenderten Lauf läuft kein zweites Godot, auch nicht check.sh
bereich: werkzeuge
datum: 2026-10-29
pruefung: manuell: vor jedem Godot-Aufruf `pgrep -af "godot.*vulkan"` – läuft einer, warten
---

**Was passiert ist:** Meldung #24. Der gerenderte Lauf `tools/gd.sh run -- … --e2e=fahrzeuge --shots=…` belegte nach 30 Minuten 5,4 GB Speicher (Container: 8 GB, kein Swap). Ein nebenbei gestartetes `tools/check.sh` meldete „Klassen-Cache veraltet – importiere …“ und startete einen vollständigen Import. Der Kernel beendete daraufhin den gerenderten Lauf: `Memory cgroup out of memory: Killed process … (godot) … anon-rss:3002660kB, shmem-rss:2463872kB`. Die Bilder waren da, die Schlussprüfungen fehlten, der Lauf musste komplett wiederholt werden. Schon vorher war ein gerenderter Lauf neben einem Headless-Test abgebrochen.

**Ursache:** Vulkan/Mesa unter xvfb hält Texturen und Puffer im Arbeitsspeicher (shmem). Ein zweites Godot, besonders mit Import, braucht weitere 1–2 GB.

**Regel:**
- Während ein gerenderter Lauf (`gd.sh run`, `xvfb-run … vulkan`) läuft, kein weiteres Godot starten: kein `check.sh`, kein `test.sh`, kein Import, kein `render_all.py` (Chromium/SwiftShader).
- Code darf man in der Zeit ändern (das laufende Spiel hat seine Skripte schon geladen), aber nicht prüfen. Bash-Skripte, die gerade laufen, nicht ändern (Lektion skript-waehrend-lauf).
- Lange gerenderte Läufe in den Hintergrund legen und die Zeit für Arbeit ohne Godot nutzen (Übertragungen, Doku, Commits).
