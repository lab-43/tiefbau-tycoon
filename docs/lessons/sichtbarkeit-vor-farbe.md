---
titel: Bei „falscher Farbe“ erst prüfen, ob das Objekt überhaupt gerendert wird
bereich: ablauf
datum: 2026-10-28
pruefung: manuell: Pixelfarbe im Meldungsbild mit der Materialfarbe vergleichen, Verdecker testweise ausblenden
---

**Was passiert ist:** Meldung #4 wünschte hellblaues Wasser. Naheliegend wäre gewesen, nur die Farben in `water.gdshader` zu ändern. Die Pixel im Meldungsbild (166/164/167) passten aber weder zum Shader (Petrol) noch zu einer Spiegelung. Ein Test mit abgesenkter Bodenfläche zeigte: Das Wasser lag darunter und war nie zu sehen (Lektion kartenebenen-ueber-boden).
**Ursache:** Die Meldung beschreibt, was Jonathan sieht, nicht welches Objekt es ist.
**Regel:**
- Bei Farb- oder Aussehenswünschen erst im Meldungsbild die Pixelfarbe messen und mit dem Material vergleichen.
- Passt sie nicht, testweise den möglichen Verdecker ausblenden oder verschieben (nur lokal, nicht committen) und neu rendern.
- Erst ändern, wenn klar ist, welches Objekt man sieht.
