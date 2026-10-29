---
titel: Abdunkeln mit einer durchsichtigen Fläche wirkt unter AgX viel schwächer als die Deckkraft verspricht – am Bild einstellen
bereich: godot
datum: 2026-10-29
pruefung: manuell: Repro-Ansicht mit „unter“ (`--views=…,unter`) ansehen, die Stadt muss deutlich dunkler sein als ohne
---

**Was passiert ist:** Meldung #31, Untergrund-Ansicht. Ein Schleier (unbeleuchtet, schwarz-blau, Alpha 0,6, ohne Tiefentest) über der ganzen Stadt sollte sie stark abdunkeln. Im Bild war die Stadt nur wenig dunkler, die Tunnelbänder hoben sich kaum ab. Erst mit Alpha 0,8 sah es nach „Untergrund“ aus.

**Ursache:** Der Schleier wird vor dem Tonemapping im linearen HDR-Raum gemischt. AgX staucht helle Werte stark; 60 % weniger Licht sehen danach eher wie 25 % aus.

**Regel:**
- Deckkraft von Abdunklungen, Hervorhebungen und Ghosts im Bild einstellen, nicht nach Zahl. Ausgangswert für deutliches Abdunkeln: Alpha um 0,8.
- Überlagerungen ohne Tiefentest gehören in den transparenten Durchgang (`TRANSPARENCY_ALPHA`). Die Reihenfolge regelt `render_priority`: höher wird später, also obenauf, gezeichnet (Schleier 1, Bahnen 10–12, Fahrzeuge 20).
