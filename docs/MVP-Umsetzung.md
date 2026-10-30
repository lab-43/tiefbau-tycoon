# Baustellen Manager – Umsetzungsstand MVP (v1.7.1)

Stand: 28.10.2026 · Ergänzt die Spezifikation „Baustellen-Manager-Konzept-MVP“. Wo die Umsetzung von der Spezifikation abweicht, steht es hier mit Begründung.

## Was im MVP drin ist

| Mindestanforderung | Umsetzung |
|---|---|
| Firma gründen und Standort wählen | Gründungsbildschirm: Firmenname, Stadtsuche (Nominatim), Klick auf die OSM-Karte setzt die Zentrale. Kartengröße 4, 6 (Standard) oder 10 km. Zusätzlich gibt es eine **Offline-Demokarte (Utrecht)**, falls Overpass nicht erreichbar ist. |
| 3D-Welt aus Kartendaten | Overpass-Download in 2-km-Kacheln mit Wiederholungen und Prüfung auf unvollständige Antworten. Straßengraph mit Kreuzungsflächen, Bordsteinen, Gehwegen, deutscher Markierung, Fahrstreifen und Abbiegebeziehungen. Die OSM-Knoten einer echten Kreuzung werden zu einer Kreuzung zusammengefasst, Übergänge laufen in der Breite aus, Abbiegewege sind Bögen mit größtem Radius, Verkehrsinseln bleiben frei (#5). Markierung nach RMS: Leit-, Warn- und Mittellinien (auch durch Übergänge), Halt- und Wartelinien, Fußgängerfurten und Zebrastreifen, Richtungspfeile auf mehrstreifigen Zufahrten, Leitlinien im Knotenpunkt und Sperrflächen an Inseln. Gebäude als weiße Blöcke, Flächen, Wasser, Bäume, Laternen und Ampeln. Die aufbereitete Karte wird zwischengespeichert. |
| Auftragssystem (1 Art) | „Leitung erneuern“ (Trinkwasser DN 150–300, Gas DN 200, Kanal DN 300–400). Graben 3,5–4,4 m lang, 1,5–2,1 m tief. Angebote laufen nach 22 h ab und werden auf passenden Straßen mit Platz für die volle Standard-Absperrung erzeugt. Im Debug-Menü lässt sich ein Auftrag fast überall platzieren, es zählt nur die Grube (#33). |
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
| Gelände | Höhenmodell | Im MVP flach, seit #8 mit Geländehöhen (Mapterhorn), seit #32 Brücken mit lichter Höhe und Rampen. | Die Höhen-API war anfangs aus der Build-Umgebung nicht erreichbar. |
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
  - „Auftrag platzieren“: Die Grube hängt als Vorschau am Mauszeiger (orange = passt, rot = passt nicht, mit Grund, #33). Ein Linksklick setzt den Graben dorthin, auf Wunsch gleich angenommen. Ist die Stelle ungeeignet, bleibt der Modus an. Rechtsklick oder Esc bricht ab.
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
- **Leiste unten rechts:** Markierungen an/aus (H), Fahrzeuge, Baustellen, Ausschreibungen, Zentrale, Gebäude an/aus (B), Untergrund-Ansicht (U, #31). Gebäude aus blendet die Ebene `building` aller Kartenkacheln aus; die Halle der Zentrale bleibt. Die Einstellung steht in `<Daten>/ansicht.json` (ohne die Untergrund-Ansicht, die immer aus startet).
- Test: `tools/test.sh markierungen` (Zentrale mit gezählten Fahrzeugen, Randmarkierung mit Pfeil und Entfernung, Klick fliegt hin, Rechtsklick schickt den Kolonnenbus, Gebäude und Markierungen an/aus).

## Absperrung selbst planen (Meldung #9)
- **Öffnen:** Im Schritt „Absperrung aufbauen“ zeigt das Baustellenfenster „Absperrung planen“ (danach „Plan ändern“). „Standard-Absperrung aufbauen“ baut wie bisher das feste Schema.
- **Planungsmodus:** Kamera senkrecht von oben (orthografisch), Straße liegt waagerecht, Verkehr des gesperrten Streifens fährt von links nach rechts. Das Spiel ist pausiert, das Licht steht auf Mittag, Bäume sind ausgeblendet. Alles kommt beim Schließen zurück.
- **Bauteile:** Leitbake, Leitkegel, Absperrschranke, Absperrgitter, gelbe Markierung, Z 123, Z 208, Z 308, Z 274, Z 250 (Tasten 1–9, 0).
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
- **Verkehr:** Die Verschwenkung beginnt 8 m vor dem ersten Teil im gesperrten Fahrstreifen und ist voll, wo der Plan den Streifen bis zur Verkehrsseite schließt. Grenzen: der ganze Straßenabschnitt bis zur Kreuzung, hinten bleibt Platz zum Rückwärts-Einfahren (#33; vorher höchstens 15 m früher und später als beim Standard). Beginnt sie früher, parkt der Kolonnenbus vorher um, notfalls in der Nachbarstraße.
- **Eigene Fahrspuren (#19):** Nur für die Dauer der Baustelle (Teil des Plans, nach dem Abbau fährt der Verkehr wieder wie vorher). Jede Fahrspur sind Stützpunkte `(s, seitlicher Versatz)` auf ihrem Fahrstreifen, dazwischen ein weicher Übergang (wie die automatische Verschwenkung). Die Spur der Baustellenseite beginnt vor und endet hinter dem gesperrten Bereich und bleibt innerhalb der roten Grenzen. Liegen beide Spuren überall mindestens 2,5 m auseinander, gibt es keine Engstelle mehr: Beide Richtungen fahren gleichzeitig (bei gleicher Richtung kein Reißverschluss), Z 208/308 sind dann nicht nötig. Wohin die Spur führt (z. B. über den Gehweg), entscheidet der Spieler; geprüft wird nur, dass sie den Arbeitsbereich meidet.
- **Bewusst noch nicht:** Material ist unbegrenzt und kostet nichts, Verstöße haben keine Folgen, eigene Vorlagen lassen sich nicht speichern, nicht ändern lässt sich der Plan, während die Kolonne gerade auf- oder umbaut. Rückfragen dazu stehen in Meldung #9.
- **Stellplätze (#22):** Werkzeug „Stellplätze“ (oder rechts „Verschieben“): Bagger, Kipper (Ladeplatz), Haufen (dort kippt der Kipper Material ab), Kolonnenbus und Warteplatz ziehen. Bagger, Kipper und Haufen dürfen auch neben der Fahrstreifenmitte stehen, vom äußeren Fahrbahnrand bis 1,5 m auf den Bordstein; Kolonnenbus und Warteplatz gleiten am Bordstein entlang. Reihenfolge bleibt Bagger → Kipper (der Kipper setzt von hinten zurück). Die Fahrzeuge setzen mit einem weichen seitlichen Versatz auf ihren Platz zurück und fahren so wieder heraus. Der Baggerarm folgt den Plätzen von selbst (Ziele kommen aus Graben, Kipper und Haufen). Prüfung (Pflicht): Der Bagger erreicht das vordere Grabenende (höchstens 7,4 m bis zum Grabenboden, mit dem echten Gestänge gemessen), Kipper und Haufen (höchstens 8,2 m); auf Stellplätzen steht nichts; kein Stellplatz im Fahrweg des Verkehrs. Kreise im Werkzeug zeigen die Reichweite. Werden Plätze während der Arbeiten geändert (#21), parken die Maschinen innerhalb der Absperrung direkt um. „Automatisch“ verwirft die eigenen Plätze. Grenzen: Fahrzeuge stehen immer längs zur Fahrbahn; dass sich Maschinen beim Umparken gegenseitig im Weg stehen, prüft das Spiel nicht.
- **Umbau während der Arbeiten (#21):** Von „Graben ausheben“ bis „Maschinen abziehen“ zeigt das Baustellenfenster „Absperrung ändern“ (auch während ein Schritt läuft). Nach „Übernehmen und umbauen“ pausiert die Arbeit: Ein laufender Arbeitsgang (Baggerspiel, Verdichten) wird noch fertig, ein Rohrtausch ganz; erst dann gilt der neue Plan (Verkehrsführung sofort, Kolonnenbus parkt bei Bedarf um). Die Kolonne sammelt, was nicht mehr im Plan ist, und stellt die neuen Teile auf. Danach geht der Schritt von selbst weiter. Solange der Umbau ansteht, sind die Arbeitsschritte gesperrt. Ist die Kolonne nicht vor Ort, wartet der Umbau auf sie (die Arbeit bleibt pausiert). Wartender Plan und Umbau stehen im Spielstand.
- **Vollsperrung (#20):** Schalter „Vollsperrung“ unter Verkehrsführung. Dann fährt kein Durchgangsverkehr mehr durch die Straße (der ganze Abschnitt zwischen zwei Kreuzungen, bei getrennten Richtungsfahrbahnen beide). Der Hintergrundverkehr biegt nicht mehr ein und sucht sich an der Kreuzung einen anderen Weg; Autos, die beim Sperren schon in der Straße sind, fahren noch hinaus (auf der Baustellenseite am Arbeitsbereich vorbei) oder verschwinden nach kurzer Zeit, wenn sie vor der Absperrung warten. Firmenfahrzeuge planen außen herum, außer die Fahrt beginnt oder endet auf der gesperrten Straße – die eigenen Baustellenfahrzeuge kommen also hinein (sie fahren dabei optisch durch die Schranken). Prüfung: Schranken quer über die ganze Fahrbahn vor dem Graben (bei Gegenverkehr auch hinter dem Maschinenplatz), Graben gesichert, Maschinenplatz frei; empfohlen Z 250 und Z 123. „Standard-Vorlage“ lädt bei eingeschalteter Vollsperrung eine fertige Vollsperrung. Die Umleitung ist automatisch; eine eigene Umleitungsstrecke mit Schildern kommt später (Antwort von Jonathan: „Erst automatisch, später selbst“).
- **Technik:** `src/site/closure_plan.gd` (Plan, Ketten, Prüfung, Speichern, `traffic`, `full`), `src/ui/closure_designer.gd` (Planungsmodus), `SiteLayout.extent_for` / `_finish_extent` (Verkehr aus dem Plan, Fahrspuren als Stützpunkte `k_ctrl`/`k2_ctrl`, `two_way`), `CameraRig.enter_topdown`. `TrafficSim.close_edges` (Vollsperrung). Tests: `tools/test.sh absperrung vollsperrung`.

## Geländehöhen (Meldung #8)
- **Datenquelle:** Mapterhorn (`tiles.mapterhorn.com`, Open-Data-Projekt von Oliver Wipfli u. a., Schweiz, gehostet bei Cloudflare, gefördert von NLnet/NGI0).
  - Höhenkacheln im Terrarium-Format (Höhe = R·256 + G + B/256 − 32768 m), verlustfreies WebP, 512 px.
  - Für Deutschland stecken die amtlichen **DGM1** aller 16 Länder drin (1 m, nackter Boden ohne Gebäude und Bäume). Hamburg: „Digitales Höhenmodell Hamburg DGM 1“, © FHH, LGV, Datenlizenz dl-de/by-2.0. Außerhalb: Copernicus GLO-30 (30 m).
  - Kostenlos, ohne Konto. Nutzungsregeln für den öffentlichen Kachel-Endpunkt nennt die Seite keine; das Spiel lädt pro Karte einmal 20–64 Kacheln mit eigenem User-Agent (ohne Mail-Adresse) und speichert sie.
  - Zoomstufe 13 (5,7 m pro Pixel in Hamburg). Die Höhen sind dort in 25-cm-Stufen gerundet (z12: 50 cm, z14: 12,5 cm) – deshalb wird geglättet.
  - Rückfall: AWS Terrain Tiles (Mapzen, SRTM-basiert, gröber). Ohne Netz (oder wenn statt Kacheln Webseiten kommen, z. B. von einem WLAN-Anmeldeportal) bleibt die Karte flach und das Spiel versucht es beim nächsten Start noch einmal (`baked_v<BAKE_VERSION>_flach.bin`). Gespeichert werden nur echte PNG-/WebP-Dateien.
  - Geprüft am PC (eingebauter Browser, 28.10.): Elbe 0 m, Alster 3 m, Geest bis 40 m, Michel und Elbphilharmonie fehlen (nackter Boden).
- **Aufbereitung** (`src/map/terrain_bake.gd`, im Worker-Thread):
  - Kacheln → 10-m-Raster in lokalen Metern → Land weichgezeichnet (Gauß, ~15 m), Wasserflächen dabei ausgenommen → 5-m-Raster.
  - Jede Wasserfläche liegt flach auf ihrer Höhe (Median der Höhen darin), der Boden darunter 1 m tiefer. Knoten am Ufer behalten die Landhöhe, die Böschung liegt im Wasser.
  - Der Hof der Zentrale wird eben gemacht und läuft über 30 m ins Gelände aus.
  - Aufwand (Hamburg 10 × 10 km, im Container gemessen am 28.10.): Laden mit Aufbereitung 67 s statt 45 s (ohne Grafik), gespeicherte Karte 210 MB statt 117 MB ohne Höhen.
  - Brücken: Höhen, Rampen und Böschungen siehe „Brücken“ (#32). Das Deck liegt nie unter dem Gelände, Brückendecks liegen in eigenen Ebenen (`asphalt_deck`, `sidewalk_deck`, `mark_deck`), deren Shader sie nur anhebt.
  - Bekannte Reste (gesehen an der Lombardsbrücke): An Brückenenden auf steilen Ufern kann die Fahrbahn quer geneigt sein (sie folgt dem Ufer quer zur Straße), und dort liegen vereinzelt helle Flächenstücke über der Fahrbahn. Uferwege, die laut OSM in der Wasserfläche liegen, werden an der Uferlinie zackig vom Wasser abgeschnitten. Eigene Meldung dafür.
- **Darstellung:**
  - Das Raster ist eine globale Shader-Textur (`terrain_tex`, `terrain_rect`, `terrain_size`). Boden, Flächen, Straßen, Wege und Markierungen berechnen pro Pixel die genaue Höhe und schreiben sie als Tiefe (`terrain_depth` in `common.gdshaderinc`), auch in der orthografischen Draufsicht der Absperrungs-Planung (#9). Die Ebenen bleiben deshalb in ihrer Reihenfolge, auch wenn ihre Dreiecke den Hang nur grob nachbilden.
  - Auf der CPU hebt `MeshLayer` jeden Punkt aufs Gelände (`terrain` gesetzt), große Flächen werden in 20-m-Zellen geschnitten. Gleise (ohne Tiefenkorrektur) bestehen aus 5-m-Stücken, damit sie auf Kuppen nicht im Schotter verschwinden.
  - Gebäude: Dach h über der mittleren Geländehöhe des Umrisses, Wände bis unter den tiefsten Punkt.
  - Der flache Boden ist durch Gitter-Kacheln ersetzt (Ebene `ground`, 20 m), mit einem groben Rand bis zum Horizont.
- **Spiel:** `Terrain.at(p)`, `Terrain.near(p, y)` (Boden oder Brücke), `Terrain.piece_y(...)` für Routen. Verkehr und Firmenfahrzeuge neigen sich am Hang, Anhänger folgen. Kamera, Mausklick (Strahl aufs Gelände oder die Brücke), Zentrale, Baustellen, Arbeiter, Ampeln und Laternen stehen auf dem Gelände. Der Bagger bekommt die Abwurfhöhe als Welthöhe und rechnet sie selbst auf seine Höhe um.
- **Tests:** `tools/test.sh gelaende` (Testgelände mit künstlichen Hügeln, dazu Download von einem lokalen Kachelserver als PNG und WebP: `game/test/mock_terrain.py`). `gelaende-html` prüft einen Server, der Webseiten statt Kacheln liefert, und dass der nächste Start die flache Karte ersetzt. Schalter: `--terrain=synthetic`, `--terrain-url=<Vorlage mit {z}/{x}/{y}>`, `--no-terrain`. Jeder Schalter hat seine eigene gespeicherte Karte (`baked_v<BAKE_VERSION>_syn.bin`, `_test`, `_aus`), damit ein Testlauf nie die echte Karte ersetzt.

## Neue Maschinen (Meldung #24)
- **Im Fuhrpark kaufbar** (Startfuhrpark unverändert):
  - *Raupenbagger 39 t* (Liebherr R 938, `excavator_r938`): 430.000 €, 5,3 km/h, nicht für Autobahnen. Baggert mit demselben Gestänge-Rig wie der Mobilbagger (Monoausleger, ohne boom2). Der Löffel folgt der Weltlage (`bucket_world_zero_deg`), weil der Arm länger ist und die Ruhelage anders.
  - *Sattelzug mit Nooteboom-Tieflader* (`tractor_nooteboom`: MAN TGX 8x4 + Nooteboom MCOS-58-04): 335.000 €, 42 t Nutzlast, trägt den Raupenbagger. Zweiter Tieflader-Stellplatz in der Zentrale.
  - *Kipper mit Ladekran* (MAN TGS 6x4, Meiller-Dreiseitenkipper, Palfinger PK 27002, `truck_tipper_crane`): 235.000 €, 6 m³ Mulde (mit Kran weniger Nutzlast), Rolle Kipper. Der Kran ist modelliert (gleiche Knotennamen wie die Pritsche), im Spiel noch ohne Aufgabe.
  - *Kompaktlader* (Bobcat S550, `loader_s550`): 62.000 €, 2,8 t, 11,9 km/h, Fähigkeit `load` (noch ohne Aufgabe auf der Baustelle).
- **Tieflader allgemein:** Jedes Fahrzeug mit der Fähigkeit `lowbed`. Deckhöhe, Standplatz, Deckende und Rampenende kommen aus der Anhänger-JSON (`deck`), Klapprampen aus `ramp_open_deg`. Vor dem Aufladen prüft das Spiel `weight_t` der Maschine gegen `load_t` (32 t-Tieflader lehnt den R 938 ab). Der Auflieger neigt sich, bis der Königszapfen auf der Sattelkupplung liegt. Nach dem Abladen an der Baustelle fährt die Maschine direkt rückwärts in ihren Platz (vorher: Umweg über das Straßennetz, beim R 938 1,2 km).
- **Werte:** recherchiert (Hersteller- und Händlerangaben), Preise sind Schätzungen für Neumaschinen; Quellen und Begründung in `balance.gd`.
- **Ersatzmodelle** ohne private Assets (CI): Raupenbagger mit zwei Kettenblöcken, Kompaktlader, Semi-Tieflader, Kipper mit Kranblock, schwerer Sattelschlepper.
- **Test:** `tools/test.sh fahrzeuge` (kaufen, Räder/Ketten am Boden, Lichtmarker an der Oberfläche, Gelenkgrenzen, R 938 und S550 auf den Nooteboom und zurück, 32-t-Tieflader lehnt ab, R 938 wird per Tieflader zur Baustelle gebracht und hebt den Graben aus, Bilder bei Tag und Nacht). `rig` und `schaufel` prüfen auch den R 938.
- **Bewusst noch nicht:** Ketten ohne Animation, Rohrtausch mit dem Kran (Meldung #16), Kompaktlader beim Verfüllen, neue Auftragsarten (eigene Meldungen).

## Bäume und Laternen neben der Fahrbahn (#30)

- Echte Bäume (Hamburg: Straßenbaumkataster in OSM) standen oft auf der gezeichneten Fahrbahn, weil das Spiel Parkstreifen als Asphalt zeichnet und Breiten schätzt. Beim Aufbereiten rückt `CityMesher` jeden echten Baum, der auf Fahrbahn oder Kreuzungsfläche steht, auf kürzestem Weg 1 m hinter die Bordsteinkante (höchstens 5 m weit), sonst fällt er weg. Zufällige Park-, Wald- und Straßenbäume und die Laternen landen gar nicht erst auf Asphalt; erfundene Straßenbäume halten 6 m Abstand zu echten. Grundlage ist `AsphaltIndex` (`src/map/asphalt_index.gd`).
- Hamburg (6 × 6 km um die Zentrale): 18 309 echte Bäume, 1664 an den Rand gerückt, 125 weggelassen (meist in großen zusammengefassten Kreuzungen oder zwischen zwei parallelen Straßen, deren gezeichnete Fahrbahnen den Grünstreifen überdecken). Danach steht kein Baum mehr auf Asphalt. Das Ladeprotokoll zeigt die Zahlen.
- Kartenversion 10 (`BAKE_VERSION`): Gespeicherte Karten werden einmal neu aufbereitet.
- Test: `tools/test.sh baeume` (auch bei `pbf`).

## Tunnel und Untergrund-Ansicht (Meldung #31)
- **Was als „unter der Oberfläche“ gilt** (`RoadNet.is_under`): Straßen mit `tunnel=yes` (jetzt auch Autobahn- und Bundesstraßentunnel, die vorher ganz fehlten), `indoor=yes` sowie Garagengassen und überdachte Zufahrten mit `layer<0`. Kürzere Tunnelketten als 25 m bleiben oben. `tunnel=building_passage` (Durchfahrt durch ein Gebäude, in Hamburg ~14 km) und Unterführungen ohne Tunnel-Tag bleiben an der Oberfläche – das Gebäude bzw. der freie Himmel passt dort. Gleise mit Tunnel-Tag oder `layer<0` waren schon bisher nicht zu sehen und erscheinen jetzt in der Untergrund-Ansicht; Gleise durch Gebäude (`building_passage`) liegen jetzt an der Oberfläche.
- **Normale Ansicht:** Über Tunneln keine Fahrbahn, kein Gehweg, keine Markierung, keine Laternen, Straßenbäume oder Ampeln. Fahrzeuge verschwinden im Portal (sobald die Fahrzeugmitte eine halbe Länge drin ist) und tauchen am anderen Ende wieder auf; Firmenfahrzeuge samt Anhänger und Ladung ebenso. Baustellen, Klicks und Fahrziele beziehen sich auf die Straße an der Oberfläche.
- **Portale** (`src/map/tunnel_portals.gd`): Betonrahmen mit dunkler Öffnung (lichte Höhe 4,8 m Straße, 5,2 m Bahn), Flügelmauern zur Zufahrt, oben Erde mit Böschung nach hinten. Röhren nebeneinander (zwei Richtungsfahrbahnen, zwei Gleise) bekommen ein gemeinsames Bauwerk, wenn zwischen ihren Öffnungen weniger als 4 m liegen. Die überdeckte Länge endet vor Straßen, Kreuzungsflächen und Gleisen, die über den Tunnel laufen (mindestens 1,5 m Stirnwand; ohne Platz für die Böschung eine Rückwand aus Beton). Bäume und Laternen auf dem Bauwerk entfallen. Hamburg 10 × 10 km: 73 Tunnelabschnitte (6,7 km), 436 Gleisabschnitte im Tunnel, 140 Portale.
- **Untergrund-Ansicht** (Taste U oder Ebenen-Schalter unten rechts, startet immer aus): Die Stadt wird abgedunkelt, darüber liegen Straßentunnel (orange), U-Bahn (blau) und S-Bahn-/Fernbahn-Tunnel (grün), ohne Tiefentest – also auch unter Gebäuden sichtbar. Fahrzeuge in Tunneln erscheinen als Kästen (weiß, Firmenfahrzeuge türkis). Leitungen kommen später als weitere Ebene dazu.
- **Bewusst so / Grenzen:**
  - Die Fahrbahn senkt sich nicht ab: Fahrzeuge fahren auf Bodenhöhe in das Portal, das deshalb als Bauwerk über dem Boden steht (wie ein Tunnelmund im Hang). Echte Trogportale mit Rampe hätten Löcher in Boden und Flächen gebraucht.
  - Tunnel liegen in der Untergrund-Ansicht auf Bodenhöhe übereinander, nicht in ihrer echten Tiefe.
  - Gleise im Einschnitt mit `layer<0` ohne Tunnel-Tag zählen auch als Untergrund (vorher gar nicht gezeichnet). Züge gibt es keine.
- **Technik:** `edge.under`, `node.under`, `OsmData.under_rails`, Ebenen `under_road`/`under_subway`/`under_rail` und `portal`/`portal_dark`/`portal_green`, `UndergroundView` (Schleier, Kästen), `TrafficSim.in_tunnel`, `Router.nearest_lane(…, under)`. Kartenversion 11 (Karten werden neu aufbereitet). Test: `tools/test.sh tunnel` (Deichtorplatz: kein Asphalt über Tunneln, Portale, Ebenen, Verkehr versteckt, Klick über dem Tunnel).

## Aufträge fast überall platzieren (Meldung #33)
- **Vorher:** Ein Auftrag brauchte rund 114 m freie Straße (34 m bis zur Kreuzung vorn, 80 m dahinter), keinen Zebrastreifen und keine Haltestelle im Bereich und 160 m Abstand zu jedem anderen Auftrag. Auf der Hamburg-Karte (4 × 4 km um 53,520° N, 9,925° O) ließen sich nur 34 % der Straßenpunkte belegen.
- **Jetzt zählt die Grube** (`JobManager.check_spot`, `SiteLayout.setup`):
  - Sie liegt im rechten Fahrstreifen der angeklickten Richtung, nicht in der Kreuzungsfläche, nicht auf einer Brücke oder im Tunnel und nicht in einer engen Kurve (12° über die Grubenlänge).
  - Dahinter müssen rund 32 m desselben Abschnitts frei sein: Bagger und Kipper stehen dort und fahren von hinten rückwärts hinein. Das ist die einzige große Bedingung, die noch übrig ist.
  - Was zwei Baustellen auf einem Fahrstreifen belegen, darf sich nicht überschneiden: Umleitung mit dem Platz zum Rückwärts-Einfahren, Gegenrichtung und Parkplätze.
  - Die Fahrzeuge müssen von der Zentrale hin- und zurückkommen. Manche Fahrstreifen einer Karte erreicht man nicht, z. B. bei Einbahn-Ketten, Sackgassen oder Lücken in den Daten. Dort blieb früher ein Kipper mit „Keine Route“ stehen, und die Baustelle hing. Geprüft wird einmal pro Karte über das ganze Netz (`JobManager._build_reach`). Das gilt auch für Ausschreibungen und betrifft wahrscheinlich die Ursache von Meldung #10.
  - Zebrastreifen, Haltestellen und kurze Straßen sind nur noch Hinweise.
  - Klickt man neben eine passende Stelle, rückt die Grube bis 25 m entlang der Straße.
  - Ergebnis: 69 % aller Straßenpunkte, 82 % ohne Brücken. Die Brücken machen im Hafengebiet 15 % aus.
- **Die Vorlage staucht sich:** Ist wenig Platz, werden Verziehung, Rückverziehung und Umleitung gekürzt. Bei weniger als 3 m Verziehung gibt es keine Leitbaken, und die Querabsperrung steht dort, wo der Verkehr schon verschwenkt ist. Schilder stehen am Anfang des Abschnitts hintereinander.
- **Parkplätze auf den Nachbarstraßen** (`SiteLayout.plan_kerb`): Kolonnenbus, sechs Warteplätze und der Tieflader stehen am Bordstein vor bzw. hinter der Absperrung. Passt es dort nicht, stehen sie auf dem geraden Zulauf bzw. Ablauf des Abschnitts. Die Kolonne läuft von dort zur Baustelle, der Planer zeigt den Bus, wo er wirklich steht.
  - Nachbarstraßen, aus denen man nur über die Baustellenstraße herauskommt, zählen nicht. Bei einer Vollsperrung säßen die Fahrzeuge dort fest.
  - Der Tieflader steht nur hinter der Baustelle, nie davor. Sonst müsste der Bagger beim Aufladen falsch herum durch die Absperrung fahren. Gibt es hinten keinen Platz, bleibt der Tieflader in der Zentrale, und die Maschine fährt selbst.
  - Findet ein wartendes Fahrzeug keinen Platz, wartet es in der Zentrale, bis die Baustelle es ruft.
  - Lässt ein eigener Plan dem Bus nirgends Platz, meldet der Planer das als Pflichtpunkt.
- **Planer:** Absperrung, Umleitung und Fahrspuren reichen über den ganzen Abschnitt, nicht mehr nur bis 15 m vor die Vorlage. Die roten Grenzlinien „frühestens ab / höchstens bis hier“ stehen jetzt am Abschnittsanfang bzw. vor dem Platz zum Wenden.
- **Debug-Menü, „Auftrag platzieren“:** Die Grube hängt am Mauszeiger, aufgesprüht wie auf dem Asphalt. Orange heißt: passt. Rot heißt: passt nicht, mit dem Grund. Dahinter ist gestrichelt der Platz für Bagger und Kipper eingezeichnet, dazu Größe, Tiefe und Hinweise. Ein Klick auf ein Brückendeck meint die Brücke, nicht die Straße darunter.
- **Ausschreibungen** entstehen auch auf kürzeren Straßen (Abschnitte ab 95 m statt 135 m), behalten aber die volle Standard-Absperrung (Bus davor, drei Warteplätze und Tieflader dahinter auf derselben Straße) und den Abstand zur Zentrale und zueinander. Gestauchte Stellen an Kreuzungen entstehen nur, wenn du sie selbst platzierst.
- **Grenzen (bewusst noch nicht):**
  - Die Grube liegt immer im rechten Fahrstreifen ihrer Richtung.
  - Einbahnstraßen mit nur einem Fahrstreifen gehen nicht (Hamburg 2 %, Utrecht 23 % der Punkte). Dort ginge nur eine Vollsperrung, und die Maschinen müssten von hinten über die nächste Straße hineinfahren.
  - Der Verkehr reagiert nur auf Teile im eigenen Abschnitt: Die Verschwenkung beginnt frühestens am Abschnittsanfang, Kreuzungen und Seitenstraßen lassen sich nicht absperren.
  - Abschnitte unter rund 38 m gehen nicht, auch wenn die Straße hinter einem Übergang (Knoten mit zwei Straßen) weiterläuft.
  - Liegt die Grube direkt hinter einer Kreuzung und gibt es Gegenverkehr, warten die Autos vor der Engstelle in der Kreuzung, weil vor der Verschwenkung kaum Fahrstreifen bleibt. Eine Baustellenampel kommt später.
- **Unabhängige Prüfung:** Ein frischer Prüf-Agent hat den Umbau durchgesehen und mit eigenen Testskripten nachgerechnet. Gefunden hat er unter anderem:
  - Ohne freien Parkplatz lag das Ersatzziel mitten in der Umleitung.
  - Der Tieflader stand auf dem Platz des Busses.
  - Der Platz zum Rückwärts-Einfahren war 2,6 m zu kurz, der Kipper stand in der Kreuzung.
  - Ältere eigene Pläne hätten sich beim Laden leicht verschoben (Schilder 2 m, Beginn der Verschwenkung).

  Alles davon ist behoben. Offen bleibt das Warten in der Kreuzung (siehe Grenzen).
- **Test:** `tools/test.sh platzieren`:
  - Statistik über die Straßenpunkte (mindestens 55 % ohne Brücken; Hamburg 82 %, Utrecht 59 % wegen vieler einspuriger Einbahnstraßen und einiger unerreichbarer Fahrstreifen).
  - Vorschau orange und rot.
  - Planer an beiden Stellen.
  - Zwei echte Aufträge ohne Überspringen bis zur Abnahme: Grube 3,5 m hinter einer Kreuzung (Bus auf dem Zulauf) und Grube knapp vor der nächsten Kreuzung (Warteplatz und Tieflader auf dem Ablauf, Bagger per Tieflader).
  - Unterwegs wird nach NaN-Positionen gesucht.
  - Läuft auch auf Hamburg: `--autostart --map=<karten-id>` mit einer vom PC geholten Karte.

## Brücken – Etappe 1: Höhen (Meldung #32)
- **Was eine Brücke hoch macht** (`src/map/bridge_heights.gd`, beim Aufbereiten nach dem Straßennetz): Für jede Brücke sucht das Spiel, was darunter liegt – Straßen, Gleise, Wege (Kreuzung der Mittellinien, oben ist, wer in OSM die höhere `layer` hat, sonst die Auffahrt über der Hauptstraße) und Wasserflächen. Daraus folgt die nötige Höhe: lichte Höhe plus Bauhöhe des Decks (Straße 1,3 m, Bahn 1,6 m, Weg 0,8 m).
  - Lichte Höhen: Straße 4,70 m (oder `maxheight` + 10 cm, wenn kleiner), Fernbahn 5,90 m, U-/S-Bahn und Straßenbahn 4,80 m, Weg 2,50 m. Über Wasser je nach Spannweite 1 / 2,5 / 4 / 6 m.
  - Schrägseil- und Hängebrücken über breitem Wasser (Umriss `man_made=bridge` mit `bridge:structure`) bekommen 50 m Durchfahrt – oder so viel, wie ihre Rampen mit der erlaubten Steigung hergeben. Die Köhlbrandbrücke liegt damit 55 m über Grund (echt: 53 m Durchfahrtshöhe).
- **Rampen:** Von jeder Brücke aus wird das Netz mit der erlaubten Steigung angehoben, auch über benachbarte Abschnitte und Kreuzungen hinweg (Kreuzungen auf Rampen und Brücken liegen eben auf ihrer Höhe), bis es den Boden erreicht. Oben ist die Kuppe gerundet. Steigungen: Autobahn/Kraftfahrstraße 4 %, Auf- und Abfahrten 6 %, Bundes-/Landesstraße 5 %, sonst 7 %; Fernbahn 2 %, andere Bahnen 4 %; Wege 10 %. Brücken, die übereinander liegen, werden mehrmals durchgerechnet, bis sich nichts mehr ändert (meist 3 Runden). Gehwege, die als eigene Wege neben einer angehobenen Straße laufen, folgen ihr (nicht unter Viadukten).
- **Darstellung:** Rampen ohne Brückentag stehen auf grünen Böschungen (1 : 1,5, Ebene `embankment`), auch unter angehobenen Kreuzungen und bei Bahnrampen. Bahn- und Fußbrücken haben Seitenwände. Auch Karten ohne Geländehöhen bekommen jetzt Brückenhöhen (vorher lag dort alles flach).
- **Spiel:** Baustellen-Aufträge gibt es nur auf Straßen am Boden, nicht auf Brücken und Rampen. Verkehr, Klicks und Fahrzeuge nutzen die Deckhöhe wie bisher (`Terrain.decks`).
- **Zahlen** (Jonathans Karte Waltershof, 4 × 4 km, 30.10.): 221 Kreuzungen unter Brücken, 235 Abschnitte angehoben (38 km, davon 22 km Rampen), höchster Punkt 55 m. Rechenzeit beim Aufbereiten etwa 1,3 s.
- **Grenzen (bewusst für später):**
  - Es gibt noch kein Bauwerk: keine Pfeiler, keine sichtbare Deckunterseite, keine Widerlager (Etappe 2). Pylone und Seile der Köhlbrandbrücke kommen in Etappe 3.
  - Böschungen werden nicht mit der Umgebung abgeglichen; sie können über Wege, Flächen oder Gebäudeecken daneben laufen.
  - Bahnrampen sind wegen 2 % lang (6,5 m Höhe brauchen 325 m Rampe). Wo OSM eine Bahnbrücke ohne Grund hoch legt, steigt die Bahn deshalb weit vorher an.
  - Ein Knick bleibt dort, wo eine Rampe auf eine ebene Kreuzungsfläche trifft, und am Rampenfuß.
- **Technik:** `BridgeHeights` (Netze Straße/Bahn/Weg, Kreuzungen, Höchstwert-Dijkstra mit freier Länge zwischen den Kreuzungsflächen, Herkunft je Höhe gegen Selbstanhebung), `Terrain.decks[edge]` als Höhenprofil (`make_deck`, `deck_at`), `Terrain.node_decks` für angehobene Kreuzungen, `CityMesher.rail_decks`/`path_decks`, `OsmData.bridge_areas` (`man_made=bridge`), `maxheight` am Abschnitt. Kartenversion 12 (Karten werden neu aufbereitet). Test: `tools/test.sh bruecken` (Waltershof/Köhlbrandbrücke aus `testdata/bruecken`, mit und ohne Geländehöhen: lichte Höhe an allen Kreuzungen, Steigung, keine Stufe zur Kreuzung, Köhlbrandbrücke über 40 m, Rampen mit Böschung).
