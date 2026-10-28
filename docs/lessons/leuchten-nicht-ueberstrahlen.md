---
titel: Leuchtende Teile mit wenig Emission und ohne eigenes Licht auf sich selbst
bereich: godot
datum: 2026-10-28
pruefung: manuell: tools/gd.sh run -- --autostart --fixture=utrecht --e2e=leuchten --shots=<dir> – Bilder *_an / *_aus und leuchten_nacht_* ansehen
---

**Was passiert ist:** Meldung #1, zweite Runde. Die neuen LED-Rundumleuchten blitzten fast weiß statt orange, ausgeschaltet waren sie grau, und das Dach darunter wurde stark angestrahlt. Jonathan: „Das Leuchten ist zu hell. Die Rundumleuchten sollten orange sein (auch aus, aber dunkler).“ Gemessen im Screenshot: Kuppel an (255, 204, 164).

**Ursache:**
- Emission 6 × (1, 0.55, 0): Das AgX-Tonemapping (`day_night.gd`) macht aus so hohen Werten fast Weiß.
- Das OmniLight saß in der Kuppel, 5 cm vom Glas und vom verchromten Reflektor entfernt. Aus der Nähe beleuchtet es beides extrem stark, das wäscht die Farbe aus.
- Das Glasmaterial der Construction-Simulator-Leuchte ist grau-durchsichtig (0.25, 0.27, 0.29, α 0.35), also ohne Emission nicht orange.

**Regel:**
- Emission für farbige Lampen bei etwa 1–2.5 halten und die Farbe satt wählen (Orange: 1, 0.3, 0). Bei Werten darüber wird es weiß.
- Eine Lichtquelle in oder an einem leuchtenden Teil darf das Teil selbst nicht beleuchten: die Meshes auf einen eigenen Render-Layer legen und ihn aus `light_cull_mask` des Lichts nehmen (`Vehicle.BEACON_LAYER`).
- Die Farbe im ausgeschalteten Zustand über die Albedo setzen (`BEACON_GLASS`), nicht über Emission.
- Für Bilder den Zustand festhalten (`Vehicle.beacon_freeze`), sonst erwischt der Screenshot einen Blitz nur zufällig. Immer „an“ und „aus“ und einmal bei Nacht ansehen und die Pixelfarbe messen.
