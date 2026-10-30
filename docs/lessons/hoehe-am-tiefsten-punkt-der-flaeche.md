---
titel: Ob eine Fläche angehoben ist, misst sich an ihrem tiefsten Punkt, nicht an ihrer Mitte – Höhen an der Naht vergleichen
bereich: karte
datum: 2026-10-30
pruefung: e2e:bruecken
---

**Was passiert ist:** Meldung #32. `BridgeHeights` hielt eine Kreuzung für „nicht angehoben“, solange ihre Höhe höchstens 5 cm über dem Boden an ihrem Knoten (Mitte) lag. Eine solche Kreuzung folgt dem Gelände. Die Rampe begann aber am Rand der Kreuzungsfläche mit der Knotenhöhe – am Hang lag der Boden dort 0,78 m tiefer (Dradenaustraße, Testdaten Waltershof). Ergebnis: eine Stufe zwischen Fahrbahn und Kreuzung. Auf der flachen Karte gab es sie nicht (größte Stufe 3,5 cm), erst mit echten Höhen.
**Ursache:** Zwei Flächen treffen sich an einer Naht (Ende der Fahrbahn = Rand der Kreuzungsfläche), die Höhe wurde aber an einem anderen Ort (Knotenmitte) bestimmt.
**Regel:**
- „Angehoben“ heißt über dem tiefsten Boden der Fläche (hier: Minimum aus Knotenmitte und den Rändern, an denen die Straßen die Kreuzung verlassen). Ist die Fläche nicht angehoben, folgt das Anschlussstück dort dem Boden, nicht der Knotenhöhe.
- Tests vergleichen die Höhe beider Flächen genau an der Naht (`bridge_test.gd`: `deck_at` am Fahrbahnende gegen `node_height` am selben Punkt) und laufen mit echten Geländehöhen und flach. Flache Tests finden Fehler dieser Art nicht.

**Nachtrag (unabhängige Prüfung):** Die Naht hat auch eine Breite. Auf Querneigung lag der Fahrbahnrand an einer nicht angehobenen Kreuzung 0,57 m über ihr (Finkenwerder Straße), weil das Deck quer nur nach oben dem Boden folgte und die Tests nur die Mittellinie verglichen. Jetzt: Deck und Kreuzungsfläche haben dieselbe Regel – eben auf der geforderten Höhe, nie unter dem Boden (`max(lv, Boden)`, `lv` je Station im Deck); der tiefste Boden einer Kreuzung zählt auch an den Rändern ihrer Fahrbahnen; der Test vergleicht Mitte und beide Ränder.
