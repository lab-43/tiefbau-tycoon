---
titel: Ein Ort für einen Auftrag taugt nur, wenn die Flotte von der Zentrale hin- und zurückkommt – einmal pro Karte per Breitensuche prüfen
bereich: baustelle
datum: 2026-10-30
pruefung: e2e:platzieren (Stelle B wird nur unter erreichbaren Fahrstreifen gesucht; die Statistik zählt „nicht erreichbar“)
---

**Was passiert ist:** Im Szenario `platzieren` auf Utrecht lag Stelle B auf der Croeselaan. Die Kolonne kam hin, der Kipper auch: Er wartete auf der Nachbarstraße und fuhr über die Abkürzung rückwärts in die Absperrung, ganz ohne Routing. Nach der ersten Fahrt zur Zentrale fand er keinen Weg zurück („Kipper 1: keine Route nach Auftrag 8“). Der Bagger wartete danach für immer auf einen leeren Kipper. Der Router kennt von der Zentrale aus keinen Weg auf diesen Fahrstreifen (Einbahn-Kette bzw. Lücke im Netz). Die Meldung #10 („Auftrag ohne Route“) beschreibt vermutlich dasselbe bei Ausschreibungen.

**Ursache:** Weder Ausschreibungen noch das Platzieren prüften die Erreichbarkeit. Ein A* pro Fahrstreifen unter der Maus wäre zu langsam gewesen: 60 ms je Prüfung auf Utrecht.

**Regel:**
- Jeder Ort, an den Firmenfahrzeuge müssen, wird gegen die Erreichbarkeit geprüft, und zwar hin und zurück. Das gilt für den Fahrstreifen der Baustelle und die Fahrstreifen der Parkplätze.
- Die Erreichbarkeit wird einmal pro Karte berechnet: Breitensuche über die Kantenrichtungen des Routers, vorwärts von der Zentrale und rückwärts zu ihr (`JobManager._build_reach`). Danach kostet eine Prüfung praktisch nichts.
- Ein Szenario, das einen Ablauf ohne Routing beginnt (Abkürzungen, direktes Setzen), muss ihn auch einmal mit echtem Routing zu Ende spielen. Erst die zweite Fahrt deckt so etwas auf.
