---
titel: Testerwartungen nicht mit dem Code ausrechnen, der geprüft wird – jede neue Prüfung einmal gegen einen absichtlichen Fehler laufen lassen
bereich: ablauf
datum: 2026-10-30
pruefung: e2e:bruecken
---

**Was passiert ist:** Meldung #32. Der Brückentest prüfte die Steigung der Rampen gegen `BridgeHeights.descent(l, …)` – also gegen die Funktion, die die Rampen baut. Die unabhängige Prüfung fand einen echten Fehler darin (Rampen auf leicht fallendem Gelände 9 % statt 6 %, 331 m auf dem Testgelände), der Test war grün. Gegenprobe in einer Wegwerf-Kopie (`git clone . /tmp/t32/sens`, alter Fehler wieder eingebaut): Klick- und Stufenprüfung schlugen an, die Steigungsprüfung meldete „0 zu steile Stücke“. Erst als der Test die erlaubte Steigung selbst aus Klasse und Bodengefälle ausrechnete, fand er 251 Stellen.
**Ursache:** Erwartung und Ergebnis kamen aus derselben Quelle; ein Fehler dort ändert beide gleich.
**Regel:**
- Ein Test rechnet seine Erwartung selbst aus (eigene Formel aus den Eingangsdaten) oder vergleicht mit einem gemessenen Wert, nicht mit einer Hilfsfunktion des geprüften Codes.
- Jede neue Prüfung läuft einmal gegen einen absichtlich eingebauten Fehler (in einer Wegwerf-Kopie, nicht im Arbeitsbaum) und muss dort anschlagen. Mehrere Fehler auf einmal gehen, wenn jede Prüfung eine eigene Meldung hat.

**Nachtrag (#32, Etappe 2):** Die unabhängige Prüfung fand im Brückentest weitere Prüfungen, die nicht scheitern konnten: „Pfeiler reicht bis ans Deck“ verglich mit derselben Formel, mit der der Code die Pfeilerhöhe berechnet; „Deck unten geschlossen“ war schon mit einem einzigen nach unten zeigenden Dreieck erfüllt; Gleise auf Dämmen wurden wie der Code als „kein Hindernis“ ausgenommen. Jetzt: Pfeilerkopf gegen die gezeichnete Unterseite, Unterseite als Anteil abgedeckter Punkte entlang jeder hohen Brücke, Hindernisse aus OSM-Daten und gezeichneten Flächen. Gegenprobe in einer Wegwerf-Kopie (Hindernisprüfung, Einmündungen und Unterseite absichtlich kaputt): alle drei schlagen an. Eine Prüfung, die nur „mindestens eins“ verlangt, ist keine.
