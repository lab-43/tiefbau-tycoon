# Baustellen Manager – Umsetzungsstand MVP (v1.7.1)

Stand: 28.10.2026 · Ergänzt die Spezifikation „Baustellen-Manager-Konzept-MVP“. Wo die Umsetzung von der Spezifikation abweicht, steht es hier mit Begründung.

## Was im MVP drin ist

| Mindestanforderung | Umsetzung |
|---|---|
| Firma gründen und Standort wählen | Gründungsbildschirm: Firmenname, Stadtsuche (Nominatim), Klick auf die OSM-Karte setzt die Zentrale. Kartengröße 4, 6 (Standard) oder 10 km. Zusätzlich gibt es eine **Offline-Demokarte (Utrecht)**, falls Overpass nicht erreichbar ist. |
| 3D-Welt aus Kartendaten | Overpass-Download in 2-km-Kacheln mit Wiederholungen und Prüfung auf unvollständige Antworten. Straßengraph mit Kreuzungsflächen, Bordsteinen, Gehwegen, deutscher Markierung, Fahrstreifen und Abbiegebeziehungen. Die OSM-Knoten einer echten Kreuzung werden zu einer Kreuzung zusammengefasst, Übergänge laufen in der Breite aus, Abbiegewege sind Bögen mit größtem Radius, Verkehrsinseln bleiben frei (#5). Gebäude als weiße Blöcke, Flächen, Wasser, Bäume, Laternen und Ampeln. Die aufbereitete Karte wird zwischengespeichert. |
| Auftragssystem (1 Art) | „Leitung erneuern“ (Trinkwasser DN 150–300, Gas DN 200, Kanal DN 300–400). Graben 3,5–4,4 m lang, 1,5–2,1 m tief. Angebote laufen nach 22 h ab und werden auf passenden Straßen erzeugt (rechter Fahrstreifen, genug Abstand zur Kreuzung, kein Zebrastreifen und keine Haltestelle im Bereich). |
| Absperren | Absperrplan nach RSA-Art wird automatisch erzeugt:<br>• Z 123 und Z 208/308 in beiden Richtungen<br>• Leitbaken-Verziehung mit Lauflicht<br>• Absperrschranke mit Warnleuchten<br>• Längsbaken, Rückverziehung<br>• Absperrgitter um die Grube<br>• gelbe Markierung<br>Die Kolonne trägt jedes Teil einzeln vom Bus zur Position. Die gelbe Folie wird abgerollt, während ein Arbeiter die Linie entlangläuft. |
| Fahrzeuge und Maschinen zur Baustelle | Rechtsklick auf die Baustelle oder Button im Fahrzeugfenster. Jedes Fahrzeug bekommt seinen Platz:<br>• Bus am Bordstein vor der Absperrung<br>• Bagger und LKW stoßen von hinten in die Absperrung<br>• wer warten muss, parkt hinter der Baustelle<br>Der Tieflader lädt den Bagger auf, fährt hin, lädt über die Rampe ab und holt ihn wieder ab. |
| Baggern | Echtes Höhenraster (10 cm) mit Schichten (Asphalt, Tragschicht, Boden). Der Bagger gräbt mit IK über die echte Gelenkkette (Ausleger, Verstellausleger, Stiel, Löffel) und Viergelenk am Löffel. Hydraulikzylinder folgen. Er lädt direkt auf den Kipper. Der Kipper pendelt automatisch zur Zentrale (Entsorgungskosten). |
| Rohr austauschen | Die Kolonne steigt in die Grube und trennt das Altrohr. Der Bagger hebt das Altrohr auf die Pritsche und das neue Rohr von der Pritsche in die Grube, dann verbindet die Kolonne. |
| Loch auffüllen | Der Kipper holt Sand, Schotter und Asphalt aus den Lagerboxen der Zentrale. Er kippt an der Baustelle ab, der Bagger baut lagenweise ein, die Kolonne verdichtet mit der Rüttelplatte. Danach wird der Asphalt eingebaut, verteilt und verdichtet. Es bleibt ein frischer Asphaltflicken mit Fuge. |
| Maschinen zurück, Absperrung abbauen | Button „Maschinen zur Zentrale“, danach baut die Kolonne in umgekehrter Reihenfolge ab. Gelbe Folie wird abgezogen. |
| Abnahme und Geld | Vergütung, Vertragsstrafe je Tag Verspätung, 5 % Bonus bei schneller Fertigstellung. Bericht mit Kosten der Baustelle, Ergebnis und Stauzeit. |
| Dynamischer Verkehr | Mikrosimulation (IDM, Ampeln, Vorfahrt, rechts vor links, Busse an Haltestellen). Die Autos bremsen vor engen Bögen und fahren ohne Zucken (Kurs aus der Sehne, #5). An der Baustelle folgt der Verkehr der gelben Markierung in den Gegenfahrstreifen. Die Engstelle wird nach Z 208/308 geregelt, mit Fairness-Regel. Bei mehrstreifigen Straßen gilt das Reißverschlussprinzip. |
| UI | Schwarz/weiß mit orangem Akzent:<br>• Obere Leiste mit Zeit, Geschwindigkeit und Geld<br>• Linke Leiste mit Aufträgen, Fuhrpark und Kauf, Finanzen, Hilfe<br>• Kontextfenster für Fahrzeug (Werte, Befehle, Lichtschalter) und Baustelle (Ablauf, Status, Material, Fahrzeuge)<br>• Meldungen, Menü, Abnahmebericht |
| Tag/Nacht | Sonnenstand aus Breitengrad und Datum. Nachts gibt es:<br>• Scheinwerfer mit echten Lichtkegeln, Rundumleuchten mit drehendem Spot<br>• Warnleuchten blinkend (Lauflicht in der Verziehung)<br>• Straßenlaternen über einen Lichter-Pool<br>• Baustellenbeleuchtung. Nachts wird gearbeitet (Nachtzuschlag). |

Fahrzeuge (Kolonnenbus, Pritsche, Kipper, Sattelzug mit Tieflader, Mobilbagger):
- Sie fahren selbstständig durch den Verkehr und blinken vor dem Abbiegen und beim Spurwechsel.
- Die Lichter schalten automatisch: Abblendlicht, Bremslicht, Rückfahrlicht und Rundumleuchte.
- Lichtschalter im Panel überstimmen die Automatik.
- Rückwärtsfahren gibt es beim Einfahren in die Absperrung und in die Lagerboxen. Dabei halten Sicherungsbereiche den Verkehr an.

## Abweichungen von der Spezifikation (bewusst)

| Thema | Spezifikation | Umsetzung | Grund |
|---|---|---|---|
| Sprache | C# | **GDScript** | In der Build-Umgebung gibt es keinen NuGet-Zugang, ohne den sich das .NET-Windows-Export nicht bauen lässt. Wechsel zu C# später möglich. |
| Gelände | Höhenmodell | **flach** | Die Höhen-API war aus der Build-Umgebung nicht erreichbar. Brücken haben noch keine Höhe. |
| Testkarte | Hamburg | Hamburg live per Overpass. Getestet wurde mit einem Utrecht-Ausschnitt aus OSM-Daten im Overpass-Format. | Overpass war aus der Build-Umgebung gesperrt. **Hamburg ist daher noch nie aufbereitet worden. Das passiert erst beim ersten Start auf deinem PC.** |
| Fräse und Walze | im Ablauf | Asphalt öffnet der Bagger, verdichtet wird mit der Rüttelplatte. Fräse und Walze sind als Modelle vorhanden, aber nicht im Startfuhrpark. | Hält den MVP-Ablauf schlank und robust. Kommt mit der nächsten Auftragsart. |
| Absperrwerkzeug | Linie ziehen, einzeln setzen | Automatischer RSA-Plan, die Kolonne stellt auf. | Kein freies Platzieren im MVP. Nächster Schritt: Plan anpassen (Länge, Variante). |
| Abnahme-Bewertung 0–100 | Punkte | Bonus/Strafe nach Termin, Ruf ± | Die Regelprüfung entfällt, weil der Plan immer regelkonform erzeugt wird. |
| Grubenwände | Schichttextur | Farbe nach Tiefenband im Shader | Gleiches Ergebnis, einfacher |
| Druckprobe | Wartezeit | entfällt | |

## Robustheit (v1.3, nach Code-Review)
- Fahrzeuge, die eine Baustelle verlassen, bekommen jetzt immer einen passenden Ausfahrweg:
  - Der Kolonnenbus fädelt vor der Verziehung in den Fahrstreifen ein.
  - Bagger und LKW fahren vorwärts durch die Absperrung zum Ende hinaus.
  - Die Baustelle vergisst das Fahrzeug erst, wenn die Route wirklich geplant ist.
- „Maschinen abziehen“ prüft, ob noch ein Fahrzeug **tatsächlich** in der Absperrung steht. Steht ein leerer Tieflader bereit, holt er den Bagger ab.
- Materialbestellungen zählen auch Ladungen, die noch unterwegs sind. Dadurch gibt es keine Doppelbestellungen bei mehreren Kippern. Restmengen werden gehalten oder zurückgefahren.
- Unterbrechungen (Bagger fährt weg, Spiel speichern/laden) setzen den Arbeitsschritt sauber fort. Das gilt auch für den Rohrtausch, wenn das Altrohr schon draußen oder das neue Rohr schon drin ist.
- Nach dem Laden werden Fahrzeuge erst wieder an die Baustelle gehängt und danach die Abläufe fortgesetzt.
- Abgeschlossene Baustellen werden stillgelegt statt sofort gelöscht, damit späte Rückmeldungen von Fahrzeugen nicht ins Leere laufen.

## Weiterentwicklung mit mehreren Sessions (v1.7)
- **v1.7.1, unabhängige Prüfung:** Ein frischer Prüf-Agent fand 20 Probleme, alle sind behoben. Die wichtigsten:
  - Eine Datei fehlte im Git.
  - Eine private Git-Adresse stand in der Repo-Konfiguration; sie war in keinem Commit gelandet.
  - Doppelte Übernahmen waren möglich, wenn zwei Sessions gleichzeitig übernahmen.
  - Gleiche Meldungsnummern waren möglich.
  - Die CI-Datei war ungültig.

  Übernahmen, Nummern und Sperren sind jetzt mit `tools/agent/test_issues.sh` getestet, auch direkt auf Jonathans PC mit acht gleichzeitigen Sessions.
- **Hamburg unter Windows bestätigt (v1.6-Build, Log vom 28.10.):**
  - Die 6-km-Karte war nach 62 s fertig, inklusive 51 MB Geofabrik-Download.
  - Die 10-km-Karte war nach 27 s fertig, weil der Auszug schon da war: 23.615 Straßenzüge, 46.081 Gebäude, 2.120 Ampeln.
- **Git-Repository:**
  - Das Projekt ist ein Git-Repo für Jonathans GitHub.
  - Private Modelle, Extraktionswerkzeuge und Builds sind ausgeschlossen (`.gitignore`, geprüft von `tools/lint.py`).
  - Neue Sessions holen die Modelle aus `Tiefbau Tycoon/private/assets.tar` auf dem PC.
- **Meldungen aus dem Spiel (F8):**
  - Im Spiel, im Ladebildschirm und im Menü.
  - Mit Bild, Markierungen, weiteren Bildern, Spielstand, Zustand, Protokollen und Build-Version.
  - Rückfragen und Testbitten der Agenten erscheinen unter „Meldungen“ (Zähler an der Fahne). Jonathan antwortet und bestätigt dort.
  - Ablage: `userdata/issues/<nr>-<titel>/`. Der Verlauf wird nur angehängt.
- **Agentenwerkzeuge:**
  - `tools/agent/issues.py`: holen, übernehmen (atomar, mit Herzschlag), fragen, Plan, behoben.
  - Repro-Szenario: lädt den Spielstand einer Meldung und fotografiert die markierten Stellen.
  - `tools/agent/merge.sh`: rebase, Tests, dann automatisch nach main, nur vorwärts.
  - CI auf GitHub.
- **Gemeinsamer Datenordner:** Alle Builds (`build/main`, `build/issue-<n>`) nutzen `Tiefbau Tycoon/userdata` (`portable.txt`). Die Protokolle schreibt das Spiel selbst nach `userdata/logs/spiel.log`, inklusive GDScript-Fehlerdetails.
- **Getrennter Build:**
  - Code-pck (~1 MB) und Daten-pck (~230 MB, nur bei geänderten Modellen neu).
  - Testversionen sind dadurch winzig und starten über `Starten.cmd` mit der exe aus `build/main`.
- **Lernen:**
  - `docs/lessons/` enthält eine Datei pro Lektion aus echten Fehlern.
  - `tools/lint.py` prüft die maschinell prüfbaren davon.
  - Skills in `.claude/skills/` beschreiben die Abläufe; `CLAUDE.md` ist der Einstieg.

## Hänger und Weiterleitung behoben (v1.6)
- **Hänger („Keine Rückmeldung“):**
  - Ursache: Godots HTTPRequest mit `use_threads = true` arbeitet mit blockierenden Sockets.
  - Beim Abbrechen einer Anfrage, auf die der Server nicht antwortet (overpass.private.coffee), wartet der Hauptthread, bis der Server sich meldet. Im Test auf Jonathans PC waren das bis zu 4 Minuten, mehrfach hintereinander.
  - Lösung: Alle Anfragen laufen ohne Threads (nicht blockierend, Abbruch sofort). Für große Downloads ist der Lesepuffer auf 1 MB vergrößert.
- **Geofabrik:**
  - Der Download scheiterte an HTTP 307, weil Godot nur 301/302 folgt.
  - Weiterleitungen (301/302/303/307/308) werden jetzt selbst verfolgt, auch für die Größenabfrage und die Prüfsumme.
- **Overpass:** Ein Server, der den Statuscheck nicht besteht, gilt als „nicht erreichbar“. Er bekommt keine Teile mehr, bis eine neue Prüfung (alle 60 s) gelingt.
- **Portabler Modus:**
  - Liegt `portable.txt` neben der exe, landen Spielstände, Karten, Auszüge und Protokolle in `userdata/` daneben.
  - Das Engine-Protokoll schreibt seit v1.7 das Spiel selbst (`userdata/logs/spiel.log`). `override.cfg` entfällt, weil der feste Windows-Pfad auf anderen Rechnern Godot abbrechen ließ.
- **Arbeitsordner auf Jonathans PC:** `Documents\Tiefbau Tycoon` ist seit v1.7 ein Git-Klon. Der spielbare Stand liegt in `build/main/`.

## Kartenquelle Geofabrik (v1.5)
- **Warum:** Beim ersten echten Hamburg-Test waren die öffentlichen Overpass-Server überlastet oder nicht erreichbar:
  - overpass-api.de: HTTP 502 „at capacity“
  - private.coffee: keine Antwort
  - maps.mail.ru: langsam, HTTP 504
- **Neu:** Quelle 1 ist ein fertiger OpenStreetMap-Auszug von Geofabrik, Quelle 2 bleibt Overpass.
  - Das Spiel wählt den kleinsten Auszug, der die ganze Karte samt 1 km Rand abdeckt. Dazu dient das Verzeichnis `index-v1.json` mit den Umrissen; es wird 30 Tage aufbewahrt.
  - Für Hamburg ist das eine Datei mit 51 MB.
  - Die Datei wird per MD5 geprüft und 30 Tage aufbewahrt. Neue Karten in derselben Gegend laden nichts nach.
  - Auszüge über 160 MB oder Karten über eine Regionsgrenze hinweg nutzen Overpass.
- **Einlesen** (`src/map/pbf_reader.gd`): Das .osm.pbf-Format wird in GDScript gelesen, die Blöcke entpackt Godots zlib.
  - Drei Durchläufe: Relationen, Wege der Flächen, Knoten und Wege.
  - Behalten werden nur Knoten im Kartenbereich plus 800 m. Flächen-Relationen bekommen ihre vollständigen Ränder.
  - Test mit dem Utrecht-Auszug (11 MB): 9–15 s. Das Ergebnis deckt sich mit den Overpass-Daten: 81126 Gebäude, 6541 statt 6519 Straßenzüge.
  - Hamburg (51 MB) braucht hochgerechnet etwa 30–60 s.
- **maps.mail.ru entfernt:**
  - Das ist ein Overpass-Server von VK (Russland), der im OSM-Wiki als öffentlicher Server geführt wird.
  - Er war langsam, und Anfragen nach Russland sind unerwünscht.
  - Overpass-Fallback jetzt: overpass-api.de und overpass.private.coffee.
- **Overpass robuster:**
  - Server, die den Statuscheck nicht bestehen, geben ihre Teile sofort ab.
  - Verbindungsaufbau länger als 20 s gilt als Fehler.
  - Bei Überlastung wartet ein Server exponentiell länger (15, 30, 60, 120 s).
  - Fehlertexte stehen einzeilig im Protokoll.
- **Getestet** mit einem lokalen Geofabrik-Ersatz:
  - Auswahl des kleinsten Auszugs, Download mit Prüfsumme, Wiederverwendung
  - Rückfall auf Overpass bei zu großem Auszug
  - kompletter Ladevorgang bis zur Welt, auch aus dem exportierten Windows-Paket

## Kartendownload und Ladebildschirm (v1.4)
- **Kleinere Stücke:**
  - 1-km-Kacheln statt 2 km.
  - Ist eine Kachel für einen Server zu groß (Zeit- oder Speicherlimit), wird sie automatisch in vier Teile geteilt, bis hinunter auf 250 m.
  - Flächen-Relationen (Wasser, Parks, große Gebäude) werden erst als ID-Liste abgefragt und dann gezielt in Paketen zu 40 Stück geladen. So kommt jede nur einmal.
- **Drei Server gleichzeitig:**
  - overpass.private.coffee (2 Anfragen parallel), overpass-api.de und maps.mail.ru (je eine).
  - Ein fehlgeschlagenes Teil geht an einen anderen Server.
  - Ein Server mit Fehler macht Pause: nach HTTP 429 mindestens 30 s, wie es die Nutzungsregeln von overpass-api.de verlangen.
- **Fortsetzen:** Fertige Teile bleiben gespeichert. Ein Neustart oder „Erneut versuchen“ lädt nur den Rest.
- **Abbruch mit Diagnose:** Kommt 150 s lang von keinem Server eine Antwort, hält der Download an und sagt, woran es vermutlich liegt (Internet/Firewall, HTTPS-Prüfung durch Virenscanner, Server überlastet).
- **Ladebildschirm:**
  - Ablauf mit Schritten und Zeiten
  - Kachelkarte (offen / lädt / fertig / Fehler)
  - Server mit Live-Zustand („rechnet 12 s“, „lädt 1,2 MB“, „Pause 20 s – HTTP 429“)
  - Laufzeit, Restzeit-Schätzung und drehendes Symbol
  - Protokoll mit Kopieren-Knopf
  - Protokolldatei `laden.log` im Kartenordner
- **Aufbereitung:** Lesen, Straßennetz, Straßen und Gebäude melden Fortschritt und Zwischenergebnisse. Speichern und Laden der fertigen Karte laufen im Hintergrund, die Anzeige friert nicht ein.
- **Getestet** mit einem lokalen Overpass-Ersatz (`test/mock_overpass.py`), der normale, langsame, überlastete (504), gesperrte (429), abbrechende (Zeitlimit) und nicht erreichbare Server spielt:
  - Download, Teilen und Fortsetzen
  - „Erneut versuchen“
  - Offline-Demokarte und gespeicherte Karte

## Bedienung in Kürze
1. Aufträge (links) → Ausschreibung annehmen → Baustelle erscheint.
2. Fahrzeug wählen → Rechtsklick auf die Baustelle (oder „→ Auftrag …“ im Fahrzeugfenster). Die Erkundung erledigt sich mit dem ersten Fahrzeug, das ankommt.
3. Im Baustellenfenster die Schritte starten. Mit dem Schalter „Arbeitsschritte automatisch fortsetzen“ läuft es durch, sobald alles vor Ort ist.
4. Der Kipper pendelt selbstständig: Aushub weg, Material her. Der Pendelbetrieb ist im Kipperfenster abschaltbar.
5. Kamera: WASD, rechte Maus ziehen, mittlere Maus drehen, Mausrad zoomen, F folgen. Leertaste/1/2/3 für die Geschwindigkeit, F5 speichern.

## Technik
- Godot 4.5.1, Forward+, GDScript. Hauptszene `scenes/main.tscn`.
- Wichtige Ordner:
  - `src/site/`: Baustelle, Layout, Gelände, Arbeiter, Requisiten, Aufträge
  - `src/vehicles/`: Fahrzeug, Bagger-IK, Fuhrpark
  - `src/traffic/`: Verkehr
  - `src/nav/`: Routing
  - `src/map/`: Karte
  - `src/ui/`: Oberfläche
- Tests: `tools/test.sh [smoke issue job lowbed save+load pbf rig]`. Der Treiber ist `test/e2e_driver.gd` und startet mit `--autostart --fixture=utrecht --e2e=<szenario>`. `load` läuft ohne `--autostart`.
  - `job` spielt einen kompletten Auftrag automatisch durch.
  - `lowbed`: Bagger per Tieflader hin und zurück.
  - `rig`: Bagger-Gestänge über alle Stellungen – Viergelenk am Löffel bleibt geschlossen und auf der richtigen Seite, alle 5 Zylinder zielen aufeinander (#3). Braucht das private Modell, ohne wird übersprungen. Mit `-- --shots=<dir>` (gerendert) entstehen Seitenansichten.
  - `save`/`load`: speichern mitten im Graben, laden und bis zur Abnahme weiterspielen.
  - Letzter Stand (v1.3):
    - `job` bestanden (Jan van Foreeststraat). Zwei Läufe davor haben drei Fehler aufgedeckt, die behoben sind: eigener Sicherungsbereich blockierte die Ausfahrt, kleine Kippmengen gingen verloren, Route zu einem Ziel hinter dem Fahrzeug fehlte.
    - `lowbed` bestanden.
    - `save` + `load` bis zur Abnahme bestanden.
    - Der Windows-Export bootet die Demokarte samt Fuhrpark, Ausschreibungen und Verkehr.
- Assets (nur privat): Construction-Simulator-Modelle in `assets/consim/` (40 GLBs mit JSON zu Gelenken und Lichtern), FS25-Absperrset in `assets/barriers/`.

## Debug-Menü (F3, Meldung #6)
- **Öffnen:** mit **F3** oder dem Schraubenschlüssel in der linken Leiste. Das Menü steht rechts, neben dem Baustellen- oder Fahrzeugfenster.
- **Zeit und Licht:**
  - Zur nächsten Uhrzeit vorspulen (06–23 Uhr), +1 h, +6 h, +1 Tag. Die Zeit läuft nur vorwärts, damit Fristen und Ausschreibungen stimmig bleiben.
  - Licht festhalten (Tag, Abend, Nacht), während die Uhr weiterläuft.
  - Jahreszeit wählen.
  - Tempo 30× und 60×. Mit 1, 2, 3 oder der Leertaste geht es zurück auf normales Tempo.
- **Aufträge:**
  - Neue Ausschreibung sofort.
  - „Auftrag platzieren“: Ein Linksklick auf eine Straße setzt den Graben dorthin, auf Wunsch gleich angenommen. Ist die Stelle ungeeignet, bleibt der Modus an. Rechtsklick oder Esc bricht ab.
- **Baustelle:**
  - „Schritt sofort erledigen“ hinterlässt den Endzustand der echten Arbeit: Absperrung steht, Graben ausgehoben, Rohr getauscht, verfüllt, Asphalt usw. Das klappt auch mitten in einem laufenden Schritt.
  - „Bis zur Abnahme“ erledigt alle restlichen Schritte samt Bezahlung.
  - Außerdem: Fahrzeuge hinschicken und Automatik ein- und ausschalten.
- **Fahrzeug:** das gewählte Fahrzeug sofort auf einen Stellplatz der Zentrale setzen, z. B. wenn es feststeckt.
- **Sonstiges:**
  - Geld +10.000 € oder +100.000 €.
  - Verkehrsdichte 0–200 % und Verkehr leeren.
  - Leistungsanzeige mit FPS, Draw-Calls, Objekten und Verkehr.
- **Technik:**
  - Die Logik steckt in `src/debug/debug_tools.gd`, die Oberfläche in `debug_panel.gd`.
  - Getestet mit dem e2e-Szenario `debug` (`tools/test.sh debug`, 32 Prüfungen).
  - Neue Arbeitsschritte brauchen einen Eintrag in `DebugTools.finish_step`.

## Markierungen und Gebäude ausblenden (Meldung #7)
- **Markierungen über der Karte** (`src/ui/world_markers.gd`, liegt unter allen HUD-Fenstern):
  - Zentrale (weiß), laufende Baustellen (orange), Ausschreibungen (dunkel mit Vergütung) und Fahrzeuge (Farbe des Symbols: fährt = weiß, arbeitet/lädt = orange, steht = grau).
  - Im Bild erscheinen Zentrale, Baustellen und Fahrzeuge erst beim Rauszoomen (ab ca. 280 m Kameraabstand, voll ab 480 m). Ausschreibungen haben kein 3D-Objekt und sind immer markiert.
  - Außerhalb des Bildes klebt die Markierung am Rand des freien Bereichs (neben den Fenstern) mit Pfeil und Entfernung.
  - Fahrzeuge, die in der Zentrale oder an ihrem Platz auf der Baustelle stehen, zählt die Markierung dort mit (Zahl oben rechts), das gewählte Fahrzeug bleibt immer einzeln. Nahe beieinander liegende Fahrzeuge oder Ausschreibungen werden zu einer Markierung mit Zahl zusammengefasst; verdeckte Markierungen im Bild stapeln sich nach oben.
  - Klick: hinfliegen und auswählen (Ausschreibung: Auftragsliste öffnen). Rechtsklick mit gewähltem Fahrzeug: dorthin schicken (Baustelle, Zentrale, Tieflader).
- **Leiste unten rechts:** Markierungen an/aus (H), Fahrzeuge, Baustellen, Ausschreibungen, Zentrale, Gebäude an/aus (B). Gebäude aus blendet die Ebene `building` aller Kartenkacheln aus; die Halle der Zentrale bleibt. Die Einstellung steht in `<Daten>/ansicht.json`.
- Test: `tools/test.sh markierungen` (Zentrale mit gezählten Fahrzeugen, Randmarkierung mit Pfeil und Entfernung, Klick fliegt hin, Rechtsklick schickt den Kolonnenbus, Gebäude und Markierungen an/aus).

## Absperrung selbst planen (Meldung #9)
- **Öffnen:** Im Schritt „Absperrung aufbauen“ zeigt das Baustellenfenster „Absperrung planen“ (danach „Plan ändern“). „Standard-Absperrung aufbauen“ baut wie bisher das feste Schema.
- **Planungsmodus:** Kamera senkrecht von oben (orthografisch), Straße liegt waagerecht, Verkehr des gesperrten Streifens fährt von links nach rechts. Das Spiel ist pausiert, das Licht steht auf Mittag, Bäume sind ausgeblendet. Alles kommt beim Schließen zurück.
- **Bauteile:** Leitbake, Leitkegel, Absperrschranke, Absperrgitter, gelbe Markierung, Z 123, Z 208, Z 308, Z 274 (Tasten 1–9).
- **Werkzeuge:**
  - Einzeln: ein Teil pro Klick, R/Umschalt+R dreht in 15°-Schritten. Baken und Schilder schauen automatisch zum Verkehr des nächsten Fahrstreifens, Schranken stehen quer.
  - Gerade: Kette von Klick zu Klick, weiterklicken setzt den nächsten Abschnitt an. Liegen beide Enden am gesperrten Streifen, folgt die Kette dessen Krümmung. Abstand je Bauteil einstellbar, die Kette hält ihn höchstens ein (nie weiter auseinander). Gitter und Schranken stehen Stoß an Stoß (#17).
  - Kurve (#18): Anfang klicken, dann die Richtung, dann das Ende – wie in Cities: Skylines (quadratische Bézierkurve, der mittlere Klick ist der Kontrollpunkt). Weiterklicken setzt die nächste Kurve an.
  - Fahrspur (#19): verlegt die blauen Fahrwege beider Richtungen. Punkte ziehen, Klick auf die Linie setzt einen Punkt, Rechtsklick/Entf löscht ihn. Anfang und Ende gleiten am Fahrstreifen entlang. Einrasten an den Fahrstreifenmitten. „Automatisch“ verwirft die eigenen Fahrspuren.
  - Auswählen (Klick, Umschalt, Rahmen), verschieben, drehen, Entf löscht. Radierer. Strg+Z / Strg+Y. Einrasten an Fahrstreifenkanten und -mitten (Alt = frei).
  - Standard-Vorlage laden, Leeren.
- **Eingezeichnet:** Graben, Arbeitsbereich, Platz für Bagger und Kipper, Stellplatz Kolonnenbus, Fahrweg des Verkehrs nach dem aktuellen Plan, Grenzen der Sperrung auf dieser Straße (rot), Planungsrahmen.
- **Planungsrahmen (#18):** Teile lassen sich im Umkreis von 500 m um den Graben setzen, auch an anderen Straßen (z. B. Vorwarnschilder an der Einmündung). Baken und Schilder dort schauen zum Verkehr ihres eigenen Fahrstreifens.
- **Prüfung** (warnt nur, Übernehmen geht immer): Pflicht sind Querabsperrung vor dem Graben, Längsabsicherung zum Verkehr ohne Lücke, Gitter an beiden Grabenseiten, nichts im Fahrweg, keine Fahrspur durch den Arbeitsbereich, Maschinenplatz frei. Empfohlen: Verschwenkung mit mindestens 3 Baken, Z 123, bei einer Engstelle mit Gegenverkehr Z 208 und Z 308. Die Standard-Vorlage erfüllt alles.
- **Aufbau:** Die Kolonne baut den Plan genau so auf: Schilder zuerst, dann von vorne nach hinten, gelbe Markierungen zuletzt; der Abbau läuft rückwärts. Steht schon ein Teil der alten Absperrung, bleibt, was auch im neuen Plan steht; der Rest wird eingesammelt.
- **Verkehr:** Die Verschwenkung beginnt 8 m vor dem ersten Teil im gesperrten Fahrstreifen und ist voll, wo der Plan den Streifen bis zur Verkehrsseite schließt. Grenzen: höchstens 15 m früher und 15 m später als beim Standard, damit Stellplätze und Wartepositionen passen. Beginnt sie früher, parkt der Kolonnenbus vorher um.
- **Eigene Fahrspuren (#19):** Nur für die Dauer der Baustelle (Teil des Plans, nach dem Abbau fährt der Verkehr wieder wie vorher). Jede Fahrspur sind Stützpunkte `(s, seitlicher Versatz)` auf ihrem Fahrstreifen, dazwischen ein weicher Übergang (wie die automatische Verschwenkung). Die Spur der Baustellenseite beginnt vor und endet hinter dem gesperrten Bereich und bleibt innerhalb der roten Grenzen. Liegen beide Spuren überall mindestens 2,5 m auseinander, gibt es keine Engstelle mehr: Beide Richtungen fahren gleichzeitig (bei gleicher Richtung kein Reißverschluss), Z 208/308 sind dann nicht nötig. Wohin die Spur führt (z. B. über den Gehweg), entscheidet der Spieler; geprüft wird nur, dass sie den Arbeitsbereich meidet.
- **Bewusst noch nicht:** Material ist unbegrenzt und kostet nichts, Verstöße haben keine Folgen, eigene Vorlagen lassen sich nicht speichern, geplant wird nur vor dem Aufbau (nicht während die Kolonne baut). Rückfragen dazu stehen in Meldung #9.
- **Technik:** `src/site/closure_plan.gd` (Plan, Ketten, Prüfung, Speichern, `traffic`), `src/ui/closure_designer.gd` (Planungsmodus), `SiteLayout.extent_for` / `_finish_extent` (Verkehr aus dem Plan, Fahrspuren als Stützpunkte `k_ctrl`/`k2_ctrl`, `two_way`), `CameraRig.enter_topdown`. Test: `tools/test.sh absperrung`.
