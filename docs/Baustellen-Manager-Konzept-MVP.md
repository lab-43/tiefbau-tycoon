# Baustellen Manager – Konzept & MVP-Spezifikation (v1)

Stand: 27.10.2026 (v1.1: Absperrtechnik aus FS25-Mod) · Arbeitstitel: **Baustellen Manager** · Zielplattform: Windows (GTX 1080 Ti) · Nur für den persönlichen Gebrauch

---

## 0. Kurzfassung

Ein Tycoon-/Simulationsspiel für Tiefbau und Straßenbau auf **echten Stadtkarten** (OpenStreetMap). Du gründest eine Firma, setzt die Zentrale auf eine echte Fläche in Hamburg und bekommst Aufträge in der Umgebung. Du **fährst nicht selbst**, sondern gibst Befehle wie in einem RTS. Die Fahrzeuge fahren allein und regelkonform (Blinker, Licht) durch den simulierten Stadtverkehr.

Spannend ist der **realistische Ablauf einer Baustelle**: erkunden, absperren (RSA-artig, mit gelber Markierung, der der Verkehr folgt), fräsen, graben, Rohr tauschen, verfüllen, verdichten, Asphalt, räumen, Abnahme, Geld. Gebäude sind nur weiße bzw. graue Blöcke. **Maschinen, Absperrung, Straßen und Gelände sind detailliert.**

Optisches Vorbild: **Lumion-Rendering mit Kartendaten**. Also helle, weißgraue Gebäudeblöcke, weiche Schatten und Umgebungsverdeckung, dazu realistische Straßen mit vollständiger deutscher Markierung und detaillierte deutsche Absperrtechnik.

---

## 1. Entscheidungen

| Thema | Entscheidung | Warum |
|---|---|---|
| Engine | **Godot 4 (aktuelle stabile Version, .NET/C#)**, Renderer Forward+ (Vulkan/D3D12) | Performance wie eine echte Engine, kommt mit vielen Lichtern gut klar (Nacht: Rundumleuchten, Scheinwerfer), Szenen sind Textdateien und alles läuft per Kommandozeile. Claude Code kann so bauen, testen und Screenshots machen. Three.js scheidet wegen der Leistungsgrenze aus, Unity wegen der grafischen Editor-Bedienung. |
| Sprache Code | C# für alles (Simulation, Verkehr, Gelände, UI-Logik) | Typsicher, schnell, gut für große Simulationen |
| Plattform | Windows 10/11, Referenz-Hardware GTX 1080 Ti | Vorgabe |
| Kartendaten | **OpenStreetMap** über die Overpass-API, in 2×2-km-Kacheln geladen | Google und Bing liefern keine Straßengeometrie. OSM hat Fahrstreifen, Abbiegespuren, Breiten, Tempo, Ampeln, Gebäude mit Stockwerken und Buslinien. |
| Höhendaten | AWS Terrain Tiles (Terrarium-Format, weltweit frei). Für Hamburg später optional DGM1 aus dem Transparenzportal. | Weltweit verfügbar, kein API-Schlüssel |
| Boden | **Prozedural aus OSM-Flächen** (Wiese, Park, Wald, Wasser, Gleise, Gehweg). **Keine Satellitenbilder** im MVP. | Satellitenbilder zeigen eingebrannte Autos und Schatten und passen nicht zu Straßen, die du aufgräbst. Hamburg hat offene 20-cm-Luftbilder (DOP20), die als optionale Ebene später möglich sind. |
| Kartengröße | Architektur für 30 × 30 km, **MVP lädt 10 × 10 km** um die Zentrale | Streaming erst stabil bekommen, dann vergrößern |
| Teststadt | **Hamburg** (viele Brücken und Wasser, das wird mitgedacht) | Vorgabe |
| Laden | Einmaliger Download und Aufbereitung bei Firmengründung, danach lokal zwischengespeichert und offline | Ladezeit danach unter 10 s |
| Steuerung | Nur Befehle, keine Direktsteuerung. Baggern läuft automatisch mit hochwertiger Animation (IK). | Vorgabe |
| Absperren | Linie ziehen mit automatischem Abstand **plus** freies Einzelsetzen. Ein Schema-Vorschlag nach RSA wird automatisch erzeugt. Die gelbe Markierung ist eine eigene Fahrspurlinie, der der Verkehr folgt. | Vorgabe |
| Personal | Kolonnen als Einheit („2 Mann“), einfache Figuren, die mitfahren und sichtbar arbeiten | Vorgabe |
| Graben | **Echtes Gelände** mit Schichtmodell und Mengen in m³. Aushub muss weg, Füllmaterial muss angeliefert werden. | Vorgabe |
| Material | Erst einmal **nur aus der Zentrale** (Lagerboxen mit unbegrenztem Zukauf) | Vorgabe |
| Verkehr | Nur **PKW, LKW, Busse**. Keine Fußgänger oder Radfahrer. | Vorgabe |
| Zeit | Pause / 1× / 3× / 10×. **1 Spieltag = 48 min Echtzeit bei 1×.** **Nachts wird gearbeitet.** | Vorgabe (Zeitmaßstab siehe Abschnitt 10) |
| UI | Minimal, Schwarz/Weiß mit **einem** Orange-Akzent, Sprache Deutsch | Vorgabe |
| Assets | Fahrzeuge, Rohre, Tieflader, Verkehrsautos und Ampeln aus Construction Simulator (nur privat). **Deutsche Absperrtechnik aus dem FS25-Mod „Deutsches Verkehrssicherungspaket“** (nrxEcki, nur privat), bereits nach `.glb` umgewandelt. Selbst gebaut werden nur noch Z 208/308, Bauzaun und Betonleitwand (siehe Abschnitt 12). Später schrittweise durch eigene Modelle ersetzen. | Bestandsaufnahme vom 27.10. |
| Repo | Privates GitHub-Repo `baustellen-manager`. Umgewandelte Modelle per Git LFS **nur im privaten Repo**, Rohdaten aus dem Spiel nie. Das Repo wird nie öffentlich. | Persönliches Projekt |

---

## 2. Spielablauf im MVP

1. **Neues Spiel:** Firmenname eingeben, Stadt suchen (Nominatim), auf der Karte den Standort der Zentrale anklicken.
2. **Welt bauen:** Download, Aufbereitung, Kacheln. Fortschrittsanzeige mit Schritten. Danach steht die Zentrale (Halle, Lagerboxen, Stellplätze) auf dem gewählten Grundstück.
3. **Start-Fuhrpark und Kolonne** stehen auf dem Hof (siehe Abschnitt 5.1). Startkapital (einstellbar).
4. **Auftragsangebote** erscheinen in der Liste und auf der Karte. Du nimmst einen an.
5. **Erkunden:** Transporter mit Kolonne hinschicken. Die Begehung zeigt den genauen Grabenverlauf, die Lage der alten Leitung und einen vorgeschlagenen Absperrplan.
6. **Abarbeiten:** Absperrung, Maschinen anliefern, fräsen, graben, Rohr tauschen, verfüllen und verdichten, Asphalt, walzen (siehe Abschnitt 6).
7. **Räumen:** Maschinen zurück, Absperrung abbauen.
8. **Abnahme:** Der Auftraggeber kommt mit dem Auto. Es gibt eine Bewertung von 0 bis 100 und die Auszahlung, abzüglich einer eventuellen Vertragsstrafe.
9. Mit dem Geld neue Maschinen und Absperrmaterial kaufen, mehrere Aufträge parallel annehmen.

---

## 3. Welt und Karte

### 3.1 Datenquellen und Laden
- **Geokodierung:** Nominatim (höchstens 1 Anfrage pro Sekunde, eigener User-Agent)
- **Standortwahl:** 2D-Karte mit OSM-Kartenbildern, nur wenig Anfragen, User-Agent gesetzt. Klick setzt das Zentrum der Zentrale.
- **Vektordaten:** Overpass-API, Abfrage pro 2×2-km-Kachel mit Wiederholungen und Backoff. Geladen werden:
  - `highway=*` mit allen Tags (lanes, turn:lanes, width, maxspeed, oneway, surface, sidewalk, cycleway, bridge, layer, tunnel)
  - Ampeln und Vorfahrtsknoten (`highway=traffic_signals|give_way|stop|crossing`)
  - `building=*` mit `building:levels` und `height`
  - `landuse`, `leisure`, `natural`, Wasserflächen, `railway`
  - `natural=tree`
  - Buslinien-Relationen (`route=bus`) mit Haltestellen
- **Höhen:** Terrarium-Kacheln (Zoom 13–14), gemittelt und geglättet
- **Cache:** `user://maps/<map-id>/` mit Rohdaten (OSM-JSON, komprimiert), aufbereiteten Kacheln (Binärformat) und `manifest.json` mit Version des Aufbereitungsschritts. Ändert sich der Aufbereitungscode, wird aus den Rohdaten neu gebaut, ohne neu zu laden.

### 3.2 Koordinaten, Kacheln, Detailstufen
- Lokale transversale Mercator-Projektion um das Kartenzentrum, Einheit Meter. X = Ost, −Z = Nord. Höhe aus dem Höhenmodell.
- **Verschiebbarer Ursprung** (Floating Origin), sobald die Kamera mehr als 4 km vom Ursprung entfernt ist. Verhindert Zittern durch Rechenungenauigkeit an den Kartenrändern.
- **Kacheln à 500 m**, bei 10 × 10 km sind das 400 Kacheln.

| Detailstufe | Abstand zur Kamera | Inhalt |
|---|---|---|
| L0 | < 600 m | Volle Straßengeometrie (Bordsteine, Gehwege, Markierungen als Geometrie oder Decals), Ampeln, Laternen, Bäume, Verkehr komplett simuliert |
| L1 | < 2,5 km | Vereinfachte Straßen (Markierung als Textur, keine Bordsteine), Gebäude pro Kachel zusammengefasst, Bäume als Impostor |
| L2 | darüber | Straßen als flache Bänder, Gebäudeblöcke zusammengefasst, Flächen, Wasser |

- Baustellen sind **immer L0**, egal wo die Kamera ist.

### 3.3 Straßengenerierung (der schwierigste Teil)
1. **Graph bauen:** OSM-Wege an gemeinsamen Knoten in Abschnitte zwischen Kreuzungen teilen. Abschnitt = Kante, Kreuzung = Knoten.
2. **Querschnitt pro Abschnitt:**
   - Fahrstreifenzahl aus `lanes` oder abgeleitet aus Straßenklasse und `oneway`
   - Fahrstreifenbreite: Standard 3,25 m (Wohnstraße 2,75–3,0 m, Hauptstraße 3,25–3,5 m), `width` überschreibt
   - Gehwege aus `sidewalk=*` (Standard in der Stadt: beidseitig, 2,0–2,5 m), Bordsteinhöhe 12 cm
   - Radstreifen aus `cycleway=lane`
3. **Kreuzungen:**
   - Kanten der Fahrbahnen schneiden und eine Kreuzungsfläche mit Eckausrundung bauen (Radius nach Straßenklasse, 6–12 m)
   - Gehwege um die Ecken herumführen, Bordsteinabsenkungen an Übergängen
   - Mehrere sehr nahe OSM-Knoten (getrennte Richtungsfahrbahnen) zu einer Kreuzung zusammenfassen
4. **Fahrstreifen-Graph** (für Verkehr und eigene Fahrzeuge): Mittellinien der Fahrstreifen pro Abschnitt. In Kreuzungen Verbindungskurven gemäß `turn:lanes` oder abgeleitet (Rechtsverkehr!).
5. **Vorfahrt:**
   - Ampeln aus OSM bekommen generierte Phasen
   - `give_way`/`stop` werden ausgewertet
   - Ohne Angaben gilt: höhere Straßenklasse hat Vorfahrt. Wohnstraße auf Wohnstraße ohne Zeichen ist **rechts vor links**.
6. **Brücken** (`bridge=yes`, `layer`): Fahrbahnplatte mit Höhenverlauf zwischen den Endpunkten, einfache Pfeiler und Geländer. Darunter Wasser oder eine andere Straße. **Tunnel:** nicht gerendert, im Graph aber befahrbar.
7. **Gelände:** wird unter Straßen eingeebnet. Die Fahrbahnhöhe folgt dem geglätteten Höhenmodell, Steigungen sind auf plausible Werte begrenzt.

### 3.4 Markierung (deutsche Regeln, angelehnt an die RMS)
- **Innerorts:**
  - Leitlinie 3 m Strich, 6 m Lücke
  - Fahrstreifenbegrenzung durchgezogen
  - Haltlinien an Ampeln
  - Abbiegepfeile aus `turn:lanes`
  - Sperrflächen an Aufweitungen
  - Fußgängerüberwege aus `crossing=*`
- **Außerorts:** Leitlinie 6 m Strich, 12 m Lücke
- **Wohnstraßen und Tempo-30-Zonen meist ohne Mittellinie.** Das ist realistisch, also nicht mit Markierung „auffüllen“.
- Markierung als Geometriestreifen mit leichter Abnutzungstextur. Alles zentral in einer Konfiguration, damit es leicht anzupassen ist.
- **Gelbe Baustellenmarkierung hebt weiße auf (StVO).** Im Baustellenbereich zählt für den Verkehr nur noch Gelb (siehe Abschnitt 8.3).

### 3.5 Gebäude, Flächen, Vegetation, Wasser
- **Gebäude:**
  - OSM-Grundriss hochgezogen. Höhe aus `height`, sonst `building:levels` × 3,2 m, sonst Standard nach Gebäudetyp (Haus 2, Mehrfamilienhaus 4–5, Innenstadt 6–7 Geschosse).
  - Flachdach. Farbe weiß bis hellgrau mit leichter Variation pro Gebäude (wie im Lumion-Vorbild).
  - Pro Kachel zu einem Mesh zusammengefasst.
- **Flächen:** Wiese, Park, Friedhof, Wald, Acker, Gewerbe (Asphalt oder Beton), Gleisbett. Jeweils dezente Materialien.
- **Bäume:**
  - OSM-Einzelbäume, dazu prozedural entlang von Wohnstraßen (Hamburg hat viele Straßenbäume) und gestreut in Parks und Wäldern
  - Baumarten aus dem Bausimulator: Buche, Eiche, Ahorn, Birke, Fichte
  - Instanziert (MultiMesh), in der Ferne als Impostor
- **Wasser:** Elbe, Alster, Kanäle als flache Wasserflächen mit Wasser-Shader (Spiegelung, leichte Wellen)
- **Laternen:** prozedural etwa alle 30 m an Wohn- und Hauptstraßen
- **Ampeln:** EU-Ampelmodelle aus dem Bausimulator, an OSM-Ampelknoten automatisch platziert

### 3.6 Look (Vorbild Lumion)
- Sonne mit 4-stufigen Kaskadenschatten, Himmelslicht, **SSAO**, eventuell SSIL (vorher auf der 1080 Ti messen), leichter Glow, Tonemapping AgX oder ACES, sanfte Farbkorrektur
- Optional leichte Tiefenunschärfe in Straßennähe
- **Kein SDFGI** auf der großen Karte, zu teuer
- Aus der Ferne wirkt es wie ein Architekturmodell (weiße Blöcke, dunkle Straßen, grüne Flächen). Aus der Nähe sind Maschinen, Absperrung und Asphalt realistisch.
- Referenzbilder (aus dem Brainstorming): Lumion OSM, Kartenmodell mit weißen Gebäuden, Straßenmarkierungen à la Cities: Skylines 2, Absperrsatz wie bei den Farming-Simulator- bzw. „German Traffic Signs“-Assets

---

## 4. Kamera und Steuerung (angelehnt an Shapez 2)

| Eingabe | Aktion |
|---|---|
| W A S D / Pfeiltasten | Schwenken (Tempo wächst mit der Höhe), Shift = schneller |
| Rechte Maustaste **gedrückt halten und ziehen** | Karte greifen und verschieben |
| Rechte Maustaste **kurz klicken** | Befehl für die Auswahl (fahre hierhin, arbeite hier, lade auf) |
| Mausrad drücken und ziehen | Drehen (horizontal) und Neigen (vertikal, 25°–85°) |
| Q / E | Drehen |
| Mausrad | Zoom zum Mauszeiger, weich mit Trägheit |
| Linke Maustaste | Auswählen, Shift + LMB für Mehrfachauswahl, Rahmen ziehen |
| Leertaste / 1 / 2 / 3 | Pause / 1× / 3× / 10× |
| F | Kamera folgt dem ausgewählten Fahrzeug |
| Esc | Auswahl aufheben oder Menü |

- Zoombereich: etwa 8 m bis 4.000 m Höhe. Die Neigung geht beim Herauszoomen automatisch Richtung Draufsicht, beim Hineinzoomen Richtung 45°.
- Aus der Ferne erscheinen Fahrzeuge und Baustellen als Symbole bzw. Marker (Orange).

---

## 5. Fahrzeuge

### 5.1 Start-Fuhrpark (MVP)

| Rolle | Modell (Quelle) | Einsatz |
|---|---|---|
| Kolonnen-Transporter | NPV_BigVan aus dem Bausimulator (später eigener VW T5 aus dem Autobahnmeisterei-Projekt) | Erkundung, Kolonne, Kleinmaterial, Schilder |
| Pritschen-LKW | MAN TGS (Bausimulator) | Rohre, Absperrmaterial, Rüttelplatte |
| Kipper | MAN TGS (Bausimulator) | Aushub, Fräsgut, Sand, Schotter, Asphalt |
| Sattelzug + Tieflader | MAN TGX + Lowbed mit Interdolly (Bausimulator) | Fräse, Walze, bei Bedarf Bagger |
| Mobilbagger | Liebherr A918 (Bausimulator), alternativ Atlas 160W | Graben, Verfüllen, Rohre heben. Fährt selbst auf der Straße. |
| Kaltfräse | Bomag BM 2000/75 (Bausimulator) | Asphalt fräsen, Förderband auf den Kipper |
| Tandemwalze | Bomag BW 141 AD-5 (Bausimulator) | Asphalt walzen |
| Rüttelplatte | eigenes einfaches Modell | Verdichten im Graben (von der Kolonne bedient) |

**Später kaufbar:** Asphaltfertiger (Bomag BF600 oder CAT AP1055F), Minibagger, Radlader (Liebherr L546), weitere LKW.

### 5.2 Fahrverhalten und Lichter
- **Kinematische Bewegung** entlang von Pfadkurven, keine physikalische Fahrzeugsimulation. Dazu Radrotation, Lenkeinschlag, simulierte Federung bzw. Neigung beim Bremsen und in Kurven.
- **Routing:** A* auf dem Fahrstreifen-Graph, gewichtet nach Länge und Tempolimit. Optional später Gewichts- und Höhenbeschränkungen.
- Fahrzeuge außerhalb von L0 bewegen sich nur rechnerisch entlang der Route, ohne Darstellung. Ein Wechsel zwischen den Stufen fällt nicht auf.
- **Automatik:**
  - Blinker rechtzeitig vor Abbiegen und Spurwechsel
  - Abblendlicht bei Dämmerung und Nacht
  - Tagfahrlicht tagsüber
  - Bremslichter
  - Rückfahrlicht und Warnton beim Rückwärtsfahren
  - Rundumleuchte automatisch an, solange auf der Baustelle gearbeitet wird oder bei Schwertransport
- **Manuelle Schalter im Panel:** Abblendlicht, Rundumleuchte, Warnblinker, Arbeitsscheinwerfer. Steht ein Schalter auf manuell, überstimmt er die Automatik.
- **Im Verkehr:** halten an Ampeln, beachten Vorfahrt, fahren an Engstellen der Reihe nach

### 5.3 Auswahl-Panel und Befehle
- **Werte:**
  - Name/Kennzeichen, Status (z. B. „Fährt zur Baustelle Bahrenfelder Str.“), Ziel, Ankunftszeit
  - Geschwindigkeit (km/h), Kraftstoff, Betriebsstunden, Alter, Zustand
  - Ladung (m³ und Materialart, bzw. Stückzahl)
- **Befehle je nach Fahrzeug:**
  - Fahre zu (Klick auf die Karte)
  - Fahre zur Zentrale
  - Arbeite ab (Arbeitsschritt aus der Liste der Baustelle)
  - Auf Tieflader fahren / abladen
  - Laden in der Zentrale (Materialauswahl)
  - Abkippen / hier ablegen
  - Warten / Stopp
- **Mehrfachauswahl:** gemeinsame Befehle (z. B. alle „Fahre zur Zentrale“)

### 5.4 Tieflader
1. Sattelzug parkt am Ladepunkt, Rampen herunter (Animation).
2. Maschine fährt entlang einer berechneten Kurve auf die Ladefläche und wird an der Ladefläche festgemacht. Die Kolonne zurrt fest (kurze Animation, optional).
3. Rampen hoch, losfahren.
4. Prüfung von Gewicht und Länge (Fräse und Walze passen zusammen, falls die Werte es zulassen).
5. Abladen an einem markierten **Abladepunkt** innerhalb der Absperrung oder am Straßenrand.

---

## 6. Auftrag „Wasserleitung erneuern“ (einziger Auftragstyp im MVP)

### 6.1 Erzeugung
- Alle X Spielstunden ein neues Angebot, höchstens 3 offene Angebote
- **Ort:** Abschnitt einer Wohnstraße, mindestens 40 m lang, nicht näher als 15 m an einer Kreuzung, höchstens 6 km von der Zentrale
- **Inhalt:**
  - Auftraggeber: fiktiver Wasserversorger
  - Länge 15–40 m, DN 100–150, Rohrsohle 1,3–1,8 m tief
  - Frist 5–10 Spieltage, Vergütung, Vertragsstrafe pro Tag
- Die **Erkundung** ist Pflicht, bevor gearbeitet werden kann. Erst danach sind genaue Grabenachse, Lage der alten Leitung und Absperrvorschlag sichtbar.

### 6.2 Ablauf Schritt für Schritt

| # | Schritt | Wer | Was passiert | Material |
|---|---|---|---|---|
| 1 | Annehmen | – | Auftrag aktiv, Marker auf der Karte | – |
| 2 | Erkunden | Transporter + Kolonne | Begehung (30 Spielminuten), Plan wird sichtbar | – |
| 3 | Laden | Transporter / Pritsche | Absperrmaterial, Schilder, Rohre aus der Zentrale | Absperrlager, Rohrlager |
| 4 | Absperren | Kolonne | Schilder, Schranken, Baken, Warnleuchten, gelbe Markierung (Folie). Absperrung wird geprüft. | Absperrmaterial |
| 5 | Maschinen anliefern | Sattelzug (Fräse, Walze), Mobilbagger fährt selbst, Kipper | Abladen am Abladepunkt | – |
| 6 | Asphalt fräsen | Fräse + Kipper | Asphalt über Grabenbreite + 0,5 m je Seite abfräsen, Fräsgut aufs Band, Kipper fährt mit | Fräsgut → Kipper |
| 7 | Graben ausheben | Mobilbagger + Kipper / seitliche Ablage | Lagenweiser Aushub bis Rohrsohle + 10 cm | Boden → Kipper oder Ablage |
| 8 | Altes Rohr ausbauen | Kolonne + Bagger | Rohr wird freigelegt, Kolonne trennt, Bagger hebt die Stücke auf die Pritsche | Altrohr → Pritsche |
| 9 | Neues Rohr einbauen | Bagger + Kolonne | Rohrstücke einheben (Gurt), verbinden, **Druckprobe** (Wartezeit, Ergebnis im Panel) | Neue Rohre |
| 10 | Leitungszone | Bagger + Kolonne (Rüttelplatte) | Sand um das Rohr einbauen und verdichten | Sand |
| 11 | Verfüllen | Bagger + Kolonne (Rüttelplatte) | Lagen ≤ 30 cm, jede Lage verdichten | Boden oder Schotter, Schotter-Tragschicht |
| 12 | Asphalt | Kolonne (Handeinbau aus dem Kipper) + Tandemwalze | Asphalt einbauen und walzen. Ebenheit und Verdichtung werden bewertet. | Asphalt |
| 13 | Maschinen abziehen | Sattelzug, Bagger, Kipper | Zurück zur Zentrale, Aushub in die Box „Aushub/Bauschutt“ | – |
| 14 | Absperrung abbauen | Kolonne | Gelbe Folie entfernen, alles zurück ins Lager | – |
| 15 | Abnahme | Auftraggeber (KI-Auto) | Bewertung, Auszahlung | – |

- Schritte hängen voneinander ab. Mancher kann parallel laufen, z. B. darf die Fräse arbeiten, während die Kolonne noch Schilder auf der Gegenseite setzt.
- Jeder Schritt verlangt bestimmte Maschinen, Personal und Material. Fehlt etwas, zeigt die Checkliste der Baustelle das sofort an.

### 6.3 Absperrung (Werkzeuge, Regeln, Prüfung)
**Teile im MVP** (Quelle siehe Abschnitt 12.3 und 12.4):
- Absperrschranke (Zeichen 600) mit Fußplatten und 3 Warnleuchten (gelb, beidseitig oder einseitig) – FS25-Mod
- Leitbake (Zeichen 605, rechts- und linksweisend), Pfeilbake, Schutzbake, je mit Fußplatte und Warnleuchte – FS25-Mod
- Leitkegel (Zeichen 610) 500 und 750 mm, optional mit Warnleuchte – FS25-Mod
- Schilder auf Ständer mit Fußplatten: Zeichen 123 „Arbeitsstelle“, 121 „Einseitig verengte Fahrbahn“, 274 „Tempo“ (5–130), 101, 112, 124, 205, 206, 250, 283/286, 306, Umleitung, Plantafeln (Verschwenkung, Verengung, Vorankündigung 400/800/1000 m) – FS25-Mod
- Faltsignal (Zeichen 123) und LED-Wechselverkehrszeichen – FS25-Mod
- Zeichen 208/308 „Vorrang des Gegenverkehrs“ bzw. „Vorrang vor dem Gegenverkehr“ – selbst (Schildrohling aus dem Mod + eigene Textur)
- Mobiler Bauzaun, transportable Betonleitwand (für spätere größere Aufträge) – selbst
- Gelbe Markierungsfolie (Leitlinie und Begrenzung) – prozedural
- Baustellen-Leuchtmast für die Nacht (Flutlichtmast aus dem Bausimulator oder eigener)

**Werkzeuge:**
- **Linie ziehen:** Typ wählen, Linie auf der Straße ziehen. Teile werden mit Standardabstand gesetzt (in der Konfiguration einstellbar). Vorschau zeigt Stückzahl und Lagerbestand.
- **Einzeln setzen und drehen**
- **Schema-Vorschlag:** Aus dem Grabenumriss wird automatisch eine halbseitige Sperrung erzeugt, die du anpassen oder übernehmen kannst:
  - Querabsperrung mit Schranken und Leuchten
  - Leitbaken-Verziehung
  - Längsabsperrung am Gehweg (Absturzsicherung)
  - Schilder in beiden Richtungen
  - 208/308
  - gelbe Linien
- **Gelbe Linie ziehen:** legt die neue Fahrstreifengeometrie fest (siehe Abschnitt 8.3)
- Ausgeführt wird von der Kolonne. Sie fährt hin, trägt Teile vom Fahrzeug zur Position und stellt sie auf. Die Teile erscheinen also nicht einfach.

**Regelprüfung** (laufend, Ergebnis als Ampel im Baustellenpanel, Werte einstellbar):
- Arbeitsbereich zum Gehweg hin vollständig mit Schranke oder Zaun abgesperrt (Absturzsicherung)
- Querabsperrung mit Warnleuchten zum Verkehr hin vorhanden
- Länge der Leitbaken-Verziehung und Baken-Abstand eingehalten
- Zeichen 123 in jeder Anfahrtsrichtung im Abstand von 30–50 m
- Restfahrbahn unter der Mindestbreite für Begegnungsverkehr: Engstelle mit 208/308 geregelt (Ampel später)
- Restfahrstreifen ≥ Mindestbreite (Start 3,0 m)
- Bei verschwenkten Fahrstreifen ist eine gelbe Markierung vorhanden
- Nachts sind alle Warnleuchten an und ein Leuchtmast steht
- Verstöße kosten Punkte bei der Abnahme. Als **Erweiterung:** zufällige Kontrolle durch das Ordnungsamt mit Bußgeld.

### 6.4 Baugruben-Simulation
- **Lokales Gelände** pro Baustelle als Höhenraster mit **10 cm Auflösung** (z. B. 60 × 15 m = 90.000 Zellen). Es wird nahtlos in die Straßengeometrie eingesetzt: Der Baustellenausschnitt ersetzt dort die normale Fahrbahn.
- **Schichtmodell pro Zelle**, Oberkante jeder Schicht:
  1. Asphalt (Deck- und Binderschicht, zusammen ca. 14 cm, einstellbar)
  2. Schotter-Tragschicht (ca. 40 cm)
  3. Boden (Sand bzw. Lehm, je nach Auftrag) bis ca. 3 m
- Die **Leitung** ist ein Objekt im Boden: Achse, Tiefe, DN, Zustand alt oder neu.
- **Grabenwände zeigen die Schichten** (Shader liest die Schichtgrenzen aus einer Textur). Man sieht also im Graben Asphalt, Schotter und Boden übereinander.
- **Aushub:** Die Baggerschaufel entfernt Volumen entlang ihres Grabwegs. Der Inhalt wird pro Materialart in m³ geführt. Schaufelinhalt nach Löffelgröße, z. B. 0,6 m³.
- **Abkippen:** auf einen Kipper (Ladung nach m³ und Art, maximale Zuladung beachten) oder auf eine **seitliche Ablage** (eigener Haufen mit Schüttwinkel).
- **Verfüllen:** Material lagenweise einbauen. Jede Zelllage hat einen **Verdichtungsgrad von 0–100 %**, Überfahrten mit Rüttelplatte oder Walze erhöhen ihn. Die Abnahme prüft einen Mindestwert pro Lage.
- **Asphalt:** Einbau als Schicht mit Dicke und Temperatur (einfach gehalten: muss innerhalb von X Spielstunden gewalzt werden). Ebenheit wird über die Höhenabweichung im Raster gemessen.
- **Mesh-Aktualisierung** nur für geänderte Teilbereiche (4 × 4 m). Partikel für Erde, Sand, Schotter und Asphalt; die Partikel-Meshes aus dem Bausimulator sind vorhanden.
- **Bagger-Animation:** inverse Kinematik für Ausleger, Stiel und Löffel. Ein Grabzyklus besteht aus Anfahren, Eindringen, Ziehen, Ankippen, Heben, Schwenken, Auskippen und Zurück. Dauer ca. 20–25 s bei 1×. Hydraulikzylinder folgen den Gelenken. Der Unterwagen versetzt den Bagger am Graben entlang.
- **Fräse:** Fräswalze dreht, Förderband läuft, Fräsgut-Partikel aufs Band und in den Kipper. Die Asphaltschicht verschwindet entlang der Fräsbahn.
- **Walze:** Bandagen drehen, Vibration als leichtes Zittern und Geräusch. Erhöht die Verdichtung der überfahrenen Zellen.

### 6.5 Abnahme und Bewertung (0–100)

| Kriterium | Punkte | Messung |
|---|---|---|
| Termin | 30 | Fertig innerhalb der Frist, Abzug pro Tag Verspätung |
| Sicherheit und Absperrung | 30 | Mittelwert der Regelprüfung über die gesamte Bauzeit |
| Qualität | 25 | Verdichtung aller Lagen, Ebenheit des Asphalts, Druckprobe bestanden |
| Verkehrsbehinderung | 15 | Staumenge (Fahrzeug-Minuten in der Warteschlange) |

- Auszahlung = Auftragssumme × Faktor aus der Bewertung (z. B. 0,85–1,05) − Vertragsstrafe
- Der Ruf wird mitgezählt und schaltet später größere Aufträge frei (im MVP nur angezeigt)

---

## 7. Personal
- Start mit **1 Kolonne (2 Mann)**. Weitere Kolonnen einstellen ist eine Erweiterung, kann aber einfach mit rein.
- Die Kolonne fährt in einem Fahrzeug mit (Transporter oder Pritsche) und steigt an der Baustelle aus. Einfache Figuren mit Warnweste und Helm (Charaktermodelle aus dem Bausimulator, falls die Extraktion mit Animationen klappt, sonst einfache eigene Figuren).
- **Tätigkeiten:** Absperrung tragen und stellen, Folie kleben, Rüttelplatte führen, Rohr verbinden, Asphalt verteilen, einweisen beim Rückwärtsfahren.
- Lohn pro Spielstunde, Nachtzuschlag (einstellbar)

---

## 8. Verkehr

### 8.1 Umfang
- PKW (Verkehrsautos aus dem Bausimulator: CityCar, CompactMPV, CompactSUV, Crossover, CoupeGT, EstateWagon, BigVan und weitere, mit Fahrerfiguren)
- LKW (DAF CF/XF, MAN TGS/TGX, Scania P500 aus dem Bausimulator)
- **Busse:** eigenes einfaches Stadtbus-Modell, weil im Bausimulator kein Bus gefunden wurde. Busse fahren die **echten OSM-Buslinien** mit Haltestellen. Ohne Liniendaten fahren sie zufällige Hauptstraßen-Routen.

### 8.2 Simulation
- Aktiver Simulationsradius: ca. 1,5 km um die Kamera plus 300 m um jede aktive Baustelle. Außerhalb wird nicht simuliert; Fahrzeuge entstehen und verschwinden unsichtbar am Rand.
- **Fahrmodell:**
  - IDM (Intelligent Driver Model) für Abstand und Tempo
  - vereinfachtes MOBIL für Spurwechsel
  - Reißverschluss bei Fahrstreifenende
- **Kreuzungen:**
  - Konfliktzonen-Reservierung
  - Ampelphasen
  - Vorfahrt nach Klasse, rechts vor links
  - Abbiegen mit Blinker
- **Nachfrage:** Start- und Zielpunkte nach Gebäudedichte. **Tageskurve:** Spitzen 7–9 und 16–18 Uhr, nachts wenig.
- **Ausfallsicherheit:** Deadlock-Erkennung (steht ein Fahrzeug länger als X s ohne Grund, wird es neu geroutet bzw. entfernt, wenn es unsichtbar ist)

### 8.3 Reaktion auf Baustellen (Kernfeature)
- Die **Absperrfläche** schneidet betroffene Fahrstreifen ab.
- **Gelbe Linien** bilden einen temporären Fahrstreifen-Graph im Baustellenbereich. Weiße Markierung zählt dort nicht mehr.
- Prüfung beim Setzen:
  - Gibt es eine durchgehende Verbindung? Dann Verkehr umleiten.
  - Gibt es keine Verbindung, ist die Straße **gesperrt**, und der Verkehr wird über den Graph umgeleitet.
- **Engstelle mit 208/308:**
  - Steuerung als „Abschnitt belegt / frei“
  - Die Seite mit 208 wartet, solange Gegenverkehr im Abschnitt ist
  - Die Seite mit 308 hat Vorrang, aber ein Fairness-Zeitlimit, damit die andere Seite nicht ewig wartet
- **Später:** Baustellenampel mit Phasen (gleiche Mechanik mit Zeitsteuerung)
- **Stauzähler** pro Baustelle (fließt in die Abnahme ein), sichtbar als Overlay

---

## 9. Wirtschaft (alle Werte in einer Konfigurationsdatei, Startwerte zum Ausbalancieren)
- **Einnahmen:** Aufträge
- **Ausgaben:**
  - Fahrzeugkauf
  - Diesel pro km bzw. Betriebsstunde
  - Löhne pro Spielstunde
  - Material: Rohr pro m, Sand, Schotter, Asphalt pro t, Entsorgung Aushub pro m³
  - Vertragsstrafen
- **Shop:** Liste kaufbarer Fahrzeuge und Absperrsätze. Gekauftes erscheint in der Zentrale.
- **Finanzen-Panel:** Kontostand, letzte Buchungen, Gewinn pro Auftrag
- **Zentrale:**
  - Lagerboxen (Sand, Schotter 0/32, Asphalt, Aushub/Bauschutt), Rohrlager, Absperrlager
  - Tankstelle: Fahrzeuge tanken automatisch auf dem Hof
  - Halle, Stellplätze
  - Beim Platzieren werden OSM-Gebäude auf dem Grundstück entfernt, und eine Zufahrt wird an die nächste befahrbare Straße angebunden.

---

## 10. Zeit, Tag und Nacht
- **Zeitmaßstab:** Die Uhr läuft 30× schneller als Echtzeit (1 Spielstunde = 2 min echt). Fahrzeuge fahren **sichtbar mit echter Geschwindigkeit**.
  - Folge: Eine Fahrt von 4 km dauert bei 1× etwa 6 Echtminuten, also rund 3 Spielstunden.
  - Arbeiten passen dadurch gut: Ein Auftrag dauert etwa 3–5 Spieltage.
  - Für Fahrten gibt es 3× und 10×. Das ist der übliche Kompromiss in Tycoon-Spielen.
- **Sonne und Mond** aus den echten Koordinaten der Stadt und dem Spieldatum (Hamburg im Winter: früh dunkel). Himmels-Shader, Sterne, Dämmerung.
- **Nacht:**
  - Laternen, Fahrzeuglichter, Rundumleuchten, Warnleuchten (blinkend bzw. Dauerlicht), Leuchtmast an der Baustelle
  - Leichter Volumennebel für Lichtkegel (auf der 1080 Ti messen)
- **Lichter-Budget:** Echte Lichtquellen nur im Umkreis von ca. 300 m und über einen Pool verwaltet. Weiter entfernt nur selbstleuchtende Flächen mit Glow. Schatten nur von der Sonne bzw. dem Mond.
- Nachts wird gearbeitet. Mit Nachtzuschlag beim Lohn und strengerer Regelprüfung (Leuchten, Leuchtmast).

---

## 11. Benutzeroberfläche
- **Stil:**
  - Panels schwarz (#0B0B0B, ca. 92 % deckend), Schrift weiß, Linien und Trenner grau
  - **Ein** Akzent: Orange (z. B. #FF6A13) für aktive Zustände, Auswahl, Marker, Warnungen
  - Schrift: klare Grotesk (Vorschlag Inter oder D-DIN), Zahlen mit Tabellenziffern
  - Viel Luft, kantige Ecken (Radius 0–2 px), keine Verläufe
- **Aufbau:**
  - **Obere Leiste:** Firmenname, Kontostand | Datum, Uhrzeit, Tag/Nacht-Symbol | Spielgeschwindigkeit
  - **Linke Leiste (Symbole):** Aufträge, Fuhrpark, Personal, Lager, Finanzen, Shop
  - **Unten rechts:** Karte des ausgewählten Fahrzeugs bzw. der Baustelle (Werte, Befehle, Lichtschalter)
  - **Baustellenpanel:** Checkliste der Schritte (Status, Wer, was fehlt), Ampel der Regelprüfung, Stauzähler, Mengen (Aushub, Material)
  - **Unten links:** Meldungen („Kipper 2 voll“, „Druckprobe bestanden“)
- **Kontextmenü** bei Rechtsklick (nur Klick, nicht Ziehen) mit passenden Befehlen
- **Hauptmenü und Firmengründung** im gleichen Stil, mit großer Kartenansicht zur Standortwahl
- Eigener UI-Design-Schritt (Entwurf), bevor die UI gebaut wird. Siehe M0 bzw. die Reihenfolge der Sessions.

---

## 12. Assets

### 12.1 Pipeline
1. **Bestandsaufnahme (erledigt am 27.10.):**
   - Construction Simulator ist ein Unity-2020.3-Spiel mit HDRP
   - 9.567 Addressable-Pakete (13 GB), unverschlüsselt
   - Die internen Namen sind GUIDs. Die **Mesh-Namen sind lesbar**, darüber wird zugeordnet.
   - UnityPy läuft in der Linux-VM auf dem Windows-PC und liest die Pakete (gesamter Scan ca. 4 min).
2. **Extraktion pro Modell** (Python + UnityPy, auf dem PC): GameObject-Hierarchie mit Transforms, Meshes (LOD0, LOD3 für die Ferne), Materialien und Texturen.
3. **Umwandlung** (Blender headless, angelehnt an die vorhandene Blender-Python-Pipeline aus dem Autobahnmeisterei-Projekt):
   - Hierarchie und Drehpunkte bleiben erhalten (Ausleger, Stiel, Löffel, Räder, Lenkung, Zylinder, Leuchten)
   - **HDRP-Materialien werden umgerechnet:** Grundfarbe bleibt. Die Maske (`_MSK`: R = metallisch, G = AO, A = Glätte) wird zu glTF-ORM (R = AO, G = Rauheit = 1 − Glätte, B = metallisch). Normal-Map bleibt.
   - Export als `.glb`
4. **Godot-Import:** Pro Fahrzeug eine Definitionsdatei (Godot-Resource), die Knotennamen Rollen zuordnet:
   - `wheel_FL`, `steer_L`, `boom`, `stick`, `bucket`, `drum`, `conveyor`
   - `light_head`, `light_brake`, `indicator_L/R`, `beacon_*`
   - Werte wie Leergewicht, Zuladung, Höchstgeschwindigkeit, Löffelvolumen
5. **Asset-Viewer-Szene** zum Prüfen (drehen, Lichter schalten, Gelenke bewegen)

### 12.2 Bestand aus Construction Simulator (nach Mesh-Namen gefunden)
- **Maschinen** (laut Soundbanks und Meshes):
  - Liebherr A918, Atlas 160W, Minibagger, CAT 349F
  - Bomag BM 2000/75 (Fräse, inkl. `Milling_Cutter`), CAT PM620
  - Bomag BF600, CAT AP1055F (Fertiger)
  - Bomag BW 141 AD-5, CAT CB44B (Walzen)
  - Liebherr L546, CAT 950 (Radlader)
  - MAN TGS/TGX, DAF CF/XF, Scania P500
- **Anbauteile:** Tieflöffel 600/900/1000, Grabenräumlöffel 1500/2000
- **Anhänger:** Lowbed (Tieflader) mit Interdolly, ConTrailer
- **Rohre:**
  - `Pipe_10m`, **`Pipe_Old_Interior_10m` / `Pipe_New_Interior_10m`** (passt perfekt zum Rohrtausch), `Pipe_10m_TransportState`
  - Rohrschellen, Gasrohr-T- und -Y-Stücke, Drainagerohre
  - Kabelschacht `Cable_Manhole_2m`, Kabeltrommeln (für spätere Kabelaufträge)
- **Grabenverbau:** `MK_Base_ExcavationSupport*` (für Gräben über 1,25 m, später)
- **Verkehr:** NPV-PKW (siehe Abschnitt 8.1), EU-Polizeiauto, Fahrerfiguren
- **Straßenausstattung:** EU-Ampeln (gerade, links, Fußgänger, Masten kurz, mittel, lang), Straßenlaterne, Flutlichtmast, Baustellenleuchte, Absperrband
- **Vegetation:** europäische Baumarten mit LODs und Impostern
- **Partikel:** Asphalt, Schotter, Sand, Erde
- **Figuren:** Character-Creator-Körper, Warnwesten, Helme (Animationen beim Extrahieren prüfen)
- **Sounds:** FMOD-Banks pro Fahrzeug (Motorsounds extrahierbar, Erweiterung)

### 12.3 Deutsche Absperrtechnik aus dem FS25-Mod (umgewandelt am 27.10.)
- **Quelle:** Farming-Simulator-25-Mod „Deutsches Verkehrssicherungspaket“ (`FS25_GermanRoadSignPack` v1.1.0.0) von **nrxEcki**. Nur privat nutzen, nicht weitergeben; vor einer Veröffentlichung den Autor fragen oder ersetzen.
- **Inhalt (6 Modelldateien, 198 Formen):**
  - Absperrschranke mit Fußplatten und Warnleuchten Typ 1/2 (gelb/rot, ein- und beidseitig)
  - Leit-, Pfeil- und Schutzbaken
  - Leitkegel 500/750 mm
  - Schilderständer mit Schaftrohren 2,7–3,8 m, Klemmen, Fußplattenträgern und allen oben genannten Zeichen
  - Plantafeln, Faltsignal, LED-Wechselverkehrszeichen
- **Konverter `tools/fs-i3d/`** (Python, eigener Port von I3DShapesTool, MIT, erweitert um das FS25-Format Version 10):
  - entschlüsselt `.i3d.shapes`
  - baut die Szene aus `.i3d` nach (Position, Drehung, Skalierung, Materialien aus `colorScale`, Texturen aus DDS)
  - schreibt `.glb`
- Die **Bibliotheks-GLBs** enthalten alle Varianten. Standardmäßig ausgeblendete Varianten tragen `extras.hidden = true`, damit das Spiel sie per Name ein- und ausschaltet.
- Die **Lichtpositionen der Warnleuchten** sind als leere Knoten `light_point`/`light_spot` (mit Farbe und Reichweite) enthalten. Das passt direkt zum Lichter-Pool aus Abschnitt 10.
- Ergebnis geprüft: glTF-Validator ohne Fehler, Maße plausibel (Schranke 2,0 m breit, Leitkegel 0,5 m, Schilder ca. 3 m), Texturen richtig herum.
- **Einschränkung:** Die Detailtexturen von FS25 (`$data/...`) fehlen. Sie werden durch feste PBR-Werte ersetzt (Graphit, verzinkt, Gummi, Reflektor). Reicht für die Draufsicht; Feinschliff in M9.

### 12.4 Selbst bauen
- Zeichen 208/308 (Schildrohling aus dem Mod + eigene Textur), mobiler Bauzaun, transportable Betonleitwand
- Stadtbus (einfach), Rüttelplatte, Gebäude der Zentrale (weiße Halle mit orangen Rolltoren, Lagerboxen)
- **Eigene Autobahnmeisterei-Modelle** (Unimog, Arocs, VW T5, Rundumleuchten): einbinden, sobald sie fertig sind. Damit ersetzt man die kopierten Modelle schrittweise.

---

## 13. Technische Architektur

### 13.1 Projektstruktur (Vorschlag)
```
baustellen-manager/
├─ game/                      # Godot-Projekt (C#)
│  ├─ src/
│  │  ├─ Core/                # GameClock, EventBus, Config, SaveSystem, FloatingOrigin
│  │  ├─ World/               # MapImport (Overpass, Terrain), MapBake, ChunkStreamer
│  │  │  ├─ Roads/            # Querschnitte, Kreuzungen, Markierung, Brücken
│  │  │  ├─ Buildings/  Terrain/  Landuse/  Vegetation/  Water/
│  │  ├─ Navigation/          # RoadGraph, LaneGraph, Pathfinder, LaneOverrides
│  │  ├─ Traffic/             # Spawner, IDM-Fahrer, Kreuzungssteuerung, Engstelle 208/308
│  │  ├─ Vehicles/            # VehicleDefinition, PathFollower, Lights, Rigs (Bagger-IK, Fräse, Walze), Tieflader
│  │  ├─ Site/                # Baustelle, Schichtgelände, Arbeitsschritte, Absperrwerkzeuge, Regelprüfung, Abnahme
│  │  ├─ Crew/                # Kolonnen, Arbeiter-Figuren
│  │  ├─ Economy/             # Firma, Konto, Shop, Auftragsgenerator
│  │  └─ UI/                  # Theme, HUD, Panels
│  ├─ assets/                 # glb (LFS), Texturen, Materialien, Shader
│  ├─ config/                 # balancing.json, markings.json, rsa_rules.json, vehicles/*.tres
│  └─ tests/                  # Unit-Tests + Fixture-Karte (Hamburg-Ottensen 1,5 × 1,5 km als OSM-JSON)
├─ tools/
│  ├─ extract/                # UnityPy-Scan + Extraktion (läuft auf dem PC)
│  ├─ fs-i3d/                 # FS25 .i3d/.i3d.shapes → glb (Absperrtechnik, fertig)
│  ├─ blender/                # Umwandlung zu glb, Materialumrechnung
│  └─ screenshots/            # Skript: Fixture-Karte laden, Kamerapositionen abfahren, PNGs schreiben
└─ docs/                      # diese Spezifikation, Entscheidungen, Asset-Liste
```

### 13.2 Grundsätze
- **Simulation getrennt von der Darstellung:**
  - Verkehr und Fahrzeuge rechnen in festen Takten (20 Hz in der Nähe, 2 Hz in der Ferne), die Darstellung interpoliert
  - Spielzustand ist serialisierbar
- Ein **Ereignisbus** für UI-Meldungen und lose Kopplung
- **Konfiguration statt Konstanten:** Markierungsmaße, RSA-Abstände, Wirtschaft, Fahrzeugwerte in Dateien
- **Speichern:** JSON (komprimiert) für Firma, Fahrzeuge, Aufträge, Baustellen-Geländeänderungen. Im MVP 1 Speicherplatz + automatisches Speichern jeden Spieltag.
- **Tests:**
  - Unit-Tests für Graphbau, Kreuzungsgeometrie, IDM, Volumenrechnung, Regelprüfung
  - Headless-Godot baut die Fixture-Karte
  - **Screenshot-Skript**, damit Claude Code optische Ergebnisse selbst prüfen kann
- **Performance-Ziele (GTX 1080 Ti, 1440p):**
  - 60 FPS in der Übersicht über 10 × 10 km
  - 60 FPS in Straßennähe an einer Baustelle mit ca. 200 sichtbaren Verkehrsfahrzeugen
  - Nachts mit ca. 40 echten Lichtquellen
  - Laden aus dem Cache < 10 s
  - RAM < 6 GB, VRAM < 6 GB
- **Godot-Werkzeuge:**
  - MultiMesh für Bäume, Laternen und Absperrteile
  - Sichtweiten-LOD (`visibility_range`) und zusammengefasste Kachel-Meshes
  - Occlusion Culling testen (Gebäude verdecken bei 45° viel)

---

## 14. Meilensteine (Claude-Code-Sessions)

Realistisch sind **8–10 Sessions**, nicht eine einzige. Absperrung und Baugrube sind zusammen etwa die Hälfte der Arbeit. Jede Session endet mit einem spielbaren Stand, Tests und Screenshots.

| # | Session | Ergebnis | Abnahmekriterien |
|---|---|---|---|
| M0 | **Setup und Assets** | Godot-.NET-Projekt, Repo, LFS, Headless-Build und -Tests; Extraktions- und Umwandlungspipeline; Asset-Viewer | A918, TGX + Lowbed, BM 2000/75, BW 141, TGS (Kipper und Pritsche), 6 Verkehrsautos, EU-Ampel laufen in Godot mit korrekten Materialien und benannten beweglichen Teilen; FS25-Absperrset (glb) importiert, Varianten per Name schaltbar |
| M0b | **UI-Design** | Entwurf (Hauptmenü, Gründung, HUD, Fahrzeug- und Baustellenpanel) | Von dir freigegeben, bevor die UI gebaut wird |
| M1 | **Karte Grundgerüst** | Gründungsablauf (Suche, Standortwahl), Overpass- und Höhen-Download, Aufbereitung, Cache, Kacheln, einfache Straßenbänder, Gebäudeblöcke, Flächen, Wasser; Kamera | Hamburg 10 × 10 km lädt aus dem Cache in < 10 s, 60 FPS in der Übersicht, Kamera fühlt sich an wie Shapez 2 |
| M2 | **Straßen im Detail und Look** | Kreuzungsgeometrie, Bordsteine, Gehwege, deutsche Markierung, Brücken, Ampeln, Laternen, Bäume; Licht und Nachbearbeitung im Lumion-Stil | Screenshot-Satz an 10 festen Orten (Kreuzungen, Brücke, Wohnstraße) sieht aus wie die Referenzbilder; keine Löcher oder Z-Fighting |
| M3 | **Fahrzeuge und Navigation** | Fahrstreifen-Graph, Routing, Pfadfolger, automatische Blinker und Lichter, Auswahl, Panel, Befehle, Zentrale auf dem Grundstück, Tieflader laden und abladen | Fahrzeug fährt von der Zentrale zu beliebigen Adressen auf der richtigen Seite, blinkt, hält an Rot, lädt die Fräse auf den Tieflader und ab |
| M4 | **Verkehr** | Spawner, IDM, Kreuzungen (Ampel, Vorfahrt, rechts vor links), Busse auf OSM-Linien, Tageskurve, Detailstufen | 300 Fahrzeuge bei 60 FPS, 30 min Dauertest ohne Deadlock |
| M5 | **Zeit, Tag und Nacht** | Uhr, Geschwindigkeiten, Sonnenstand aus den Koordinaten, Nachtbeleuchtung, Lichter-Pool | Tag-Nacht-Zyklus flüssig, 60 FPS nachts an einer Kreuzung mit Verkehr |
| M6 | **Auftrag I: Absperren** | Auftragsgenerator, Erkundung, eigene Absperrteile, Werkzeuge (Linie, Einzeln, Schema), Kolonne stellt auf, gelbe Linien mit Fahrstreifen-Überschreibung, Engstelle 208/308, Regelprüfung, Stauzähler | Verkehr fährt wechselweise durch die Engstelle, folgt Gelb, Prüfampel reagiert korrekt auf fehlende Teile |
| M7 | **Auftrag II: Baugrube** | Schichtgelände, Fräse, Bagger-IK und Grabzyklen, Kipper, seitliche Ablage, Rohr aus- und einbauen, Druckprobe, Verfüllen und Verdichten, Asphalt von Hand, Walze | Ein kompletter Graben wird mit stimmigen Mengen ausgehoben und wieder geschlossen; Grabenwände zeigen die Schichten |
| M8 | **Wirtschaft, Abnahme, Speichern** | Konto, Kosten, Shop, Abnahme mit Bewertung, Auszahlung, Speichern und Laden, UI fertig nach Design | Ganzer Ablauf von der Gründung bis zum Geldeingang spielbar, Spielstand lädt korrekt |
| M9 | **Feinschliff und Performance** | Profiling, Fehlerbehebung, Balancing, Sound (optional, FMOD-Extraktion) | Alle Performance-Ziele aus Abschnitt 13.2 erreicht |

---

## 15. Bewusst nicht im MVP
- Weitere Auftragsarten: Kabelverlegung, Kanal, Straßenneubau, Deckenerneuerung, Hausanschlüsse
- Grabenverbau-Pflicht ab 1,25 m, Baustellenampel, Ordnungsamt-Kontrollen
- Weitere Standorte, Karten größer als 10 × 10 km (Architektur ist vorbereitet), Kauf größerer Grundstücke
- Mischwerk, Baustoffhandel und Deponie als Orte auf der Karte (Material kommt erst einmal aus der Zentrale)
- Fußgänger, Radfahrer, Züge, Wetter
- Direktsteuerung von Fahrzeugen
- Satellitenbilder als Boden
- Ersatz aller Bausimulator-Modelle durch eigene

---

## 16. Offene Punkte
1. **Wo wird entwickelt?** Empfehlung: Claude Code direkt auf dem Windows-PC im Projektordner. Dort liegen der Bausimulator und die 1080 Ti, und Godot-Builds und Screenshots laufen ohne Umweg. Alternativ am Mac entwickeln und am PC testen; die Extraktion läuft so oder so auf dem PC.
2. **Arbeitsordner auf dem PC** für Projekt und Extraktion (z. B. `Dokumente\BaustellenManager`). Muss für die Extraktions-Session verbunden werden.
3. **Startwerte der Wirtschaft:** Startkapital, Fahrzeugpreise, Auftragssummen. Werden in M8 ausbalanciert, Vorschläge kommen von Claude.
4. **Autobahnmeisterei-Modelle:** Welche sind fertig und können in M0 gleich mit rein?

---

## Anhang A – Start-Prompt für Session M0

> Lies `docs/Baustellen-Manager-Konzept-MVP.md` (diese Spezifikation) vollständig. Ziel dieser Session ist **M0 – Setup und Assets**.
>
> 1. Lege ein Godot-4-.NET-Projekt (aktuelle stabile Version) unter `game/` an. Ordnerstruktur wie in Abschnitt 13.1, Git mit LFS für `*.glb`/Texturen, Headless-Build und ein erster Unit-Test laufen per Kommandozeile.
> 2. Baue unter `tools/extract/` die Extraktion mit UnityPy für Construction Simulator unter `C:\Program Files (x86)\Steam\steamapps\common\Construction Simulator\ConSim_Data\StreamingAssets\aa`:
>    - einen Index „Mesh-Name → Paket“
>    - danach die Extraktion der Modelle aus Abschnitt 12.2 mit Hierarchie, Transforms, LOD0/LOD3, Materialien und Texturen
> 3. Baue unter `tools/blender/` die Umwandlung zu `.glb` (Drehpunkte erhalten, HDRP-Maske zu glTF-ORM umrechnen, Knoten nach Rollen benennen).
> 4. Übernimm aus `fs25-absperrset.zip` den Konverter nach `tools/fs-i3d/` und die Bibliotheks-GLBs nach `game/assets/absperrung/`. Baue einen Import, der Varianten per Knotenname ein- und ausblendet (`extras.hidden`) und an `light_*`-Knoten Warnleuchten-Lichter setzt.
> 5. Lege pro Fahrzeug eine Godot-Definitionsdatei an und baue eine Asset-Viewer-Szene (drehen, Lichter schalten, Gelenke bewegen, Absperrvarianten durchschalten).
> 6. Prüfe das Ergebnis mit Screenshots aus dem Viewer. Abnahmekriterien siehe Tabelle in Abschnitt 14, Zeile M0.
>
> Rohdaten aus dem Spiel nie committen; umgewandelte `.glb` nur im privaten Repo per LFS.
