---
titel: Fremde 3D-Modelle per Skript in die Konventionen der Spielmodelle bringen
bereich: fahrzeuge
datum: 2026-10-28
pruefung: e2e:verkehrslichter (Lampenglas des Busses) + manuell: Nahaufnahme tags/nachts ansehen
---

**Was passiert ist:** Meldung #2. Der Bus im Verkehr war ein prozeduraler Klotz, weil Construction Simulator keinen Linienbus hat. Jonathan wollte einen echten Citaro und hat das Sketchfab-Modell „Mercedes CITARO II RATP“ (CC BY 4.0) heruntergeladen (`private/mercedescitaroiiratp.zip`). Das Modell kam aus SketchUp:
- Kanten als Linien-Primitive, die Godot als Linien rendern würde.
- Länge entlang +X, Front bei x = 0, nicht −Z.
- Kein `metallicFactor`: Der glTF-Standard 1.0 macht alles verchromt.
- Pariser Zielanzeige, französisches Kennzeichen, RATP-Logos und -Farben.
- Die Lampen waren eigene Farbmaterialien, aber ohne Funktion und ohne Seite.

**Regel:**
- Fremdmodelle nie von Hand im Spielcode zurechtbiegen. Ein Import-Skript unter `tools/models/` bringt sie in die Konventionen von `docs/consim_assets.md`: Meter, Front −Z, +X rechts, Boden y = 0, Ursprung zwischen den Achsen, Lampenglas als `<mat>__light_head` usw. Linien weg, PBR-Werte setzen. Dann greifen die normalen Wege des Spiels (`TrafficModels._glass`) ohne Sonderfälle.
- Das Ergebnis ist privat wie die Construction-Simulator-Modelle. Es kommt nach `game/assets/consim/<id>/` (gitignored) und muss auf dem PC in den Asset-Ordner und an `private/assets.tar` angehängt werden (`tar -rf`, nicht neu schreiben, Lektion pc-mount-ueberschreiben). Sonst fehlt es der nächsten Session.
- Das neue Modell ändert `daten.hash`, also das Daten-pck neu nach `build/main` liefern.
- Herkunft und Lizenz in die JSON des Modells und in `docs/consim_assets.md` schreiben.
- Modelle, deren Lampenglas im Asset fehlt, aber geometrisch bekannt ist (Polizei = Kompakt-Pkw, Scania = Lichtmarker), teilt `LampSplit` beim Laden auf, statt Kästen anzubauen.
