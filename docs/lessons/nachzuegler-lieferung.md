---
titel: Endet ein Arbeitsschritt, seinen offenen Bedarf schließen – eine Lieferung, die noch unterwegs ist, darf den nächsten Schritt nicht blockieren
bereich: baustelle
datum: 2026-10-28
pruefung: e2e:job
---

**Was passiert ist:** Beim Zusammenführen von #19 lief das Szenario `job` in die Zeitgrenze (`E2E TIMEOUT at sim t=14984`). Die Baustelle stand im Schritt „Asphalt einbauen“, der Kipper mit Asphalt wartete für immer auf dem Warteplatz, auf dem Kippplatz lagen 0,3 m³ Schotter.
- Kurz vor Ende des Verfüllens fehlte etwas Schotter. `_tick_refill` bestellte 0,3 m³ nach (`mat_need.m3` erhöht).
- Das Verfüllen wurde trotzdem fertig (Restmenge unter 0,45 m³ wird verdichtet). `_finish_refill` räumte den Haufen ab.
- Der Kipper mit der Nachbestellung kam erst im Asphaltschritt an. `_tipper_arrived` fand den Schotterbedarf noch offen und kippte ab.
- Asphalt darf nur auf einen leeren oder Asphalt-Haufen. Der Asphaltkipper wartete deshalb ohne Ende.

**Ursache:** Der Bedarf eines Schritts (`needs`) blieb nach dessen Ende offen. Ob der Fehler auftritt, hängt nur davon ab, ob die Nachbestellung vor oder nach dem Schrittende ankommt – also vom Verkehr. Deshalb lief das Szenario vorher meist grün.

**Regel:**
- Endet ein Schritt, der Material verbraucht, wird sein offener Bedarf geschlossen (`m3 = delivered`, `ordered = 0`).
- Ein Fahrzeug, das mit einer nicht mehr gebrauchten Ladung an seinem Platz ankommt, bekommt sofort einen neuen Auftrag (`_tipper_next`), statt dort stehen zu bleiben.
- Bei einem Fehler, der nur manchmal auftritt, zuerst nach Wettläufen zwischen Schrittende und Fahrzeugen suchen, die noch unterwegs sind.
