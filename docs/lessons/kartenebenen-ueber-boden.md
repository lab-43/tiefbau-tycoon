---
titel: Flache Kartenebenen liegen über der Bodenfläche – wer Höhen ändert, erhöht BAKE_VERSION
bereich: karte
datum: 2026-10-28
pruefung: e2e:ebenen
---

**Was passiert ist:** Meldung #4 „Das Wasser soll ein schönes helles Blau haben“. Im Meldungsbild war die Elbe neutralgrau (RGB 166/164/167), der Shader `water.gdshader` gab aber Petrol vor. Das Wasser lag mit `CityMesher.WATER_Y = -0.55` unter der durchgehenden, undurchsichtigen Bodenfläche (`MapBuilder.create_city_root`, y = 0). Zu sehen war nur der Boden. Die Uferwände (`_bank`) waren ebenso unsichtbar. Sie hätten außerdem an jeder Kante zwischen zwei Wasserflächen eine Linie mitten im Fluss gezeichnet. Eine reine Farbänderung im Shader hätte nichts bewirkt.
**Ursache:** Das Wasser sollte „abgesenkt“ wirken, aber der Boden hat keine Löcher. Kein Test prüfte die Höhenreihenfolge der Ebenen.
**Regel:**
- Jede flache Kartenebene (Wasser, `area_*`) liegt über `MapBuilder.GROUND_Y`. Darunter ist sie unsichtbar.
- Wasser liegt über allen Flächen (Hafen-Landuse überlappt die Becken) und unter Gleisbett, Wegen und Straßen. Aktuell: Flächen 0,010–0,030 · Wasser 0,031 · Gleisbett 0,032 · Wege 0,04 · Straße 0,05.
- Wer Höhen oder Inhalt der gebackenen Meshes ändert, erhöht `MapBuilder.BAKE_VERSION`. Sonst lädt das Spiel die alte `baked_v<n>.bin` und die Änderung kommt bei Jonathan nie an.
- `tools/test.sh ebenen` (läuft auch bei `pbf`) prüft die Reihenfolge an Utrecht. Mit dem alten Wert schlägt er fehl.
- Erhöhen zwei Sessions `BAKE_VERSION` parallel (#5 und #8 beide auf 5), beim Rebase die höhere Zahl plus 1 nehmen und beide Gründe im Kommentar behalten.

**Nachtrag (#32, Bisect in einer Wegwerf-Kopie):** Alle Klone im Container teilen sich den Datenordner `app_userdata/Baustellen Manager`. Ein Bisect über ältere Commits desselben Branches (gleiche BAKE_VERSION 12, aber anderes Deck-Format) hinterließ eine Testkarte `dev_utrecht/baked_v12.bin` ohne das neue Feld `lv`. Die folgenden Läufe von job, markierungen und platzieren lasen diese alte Karte; platzieren brach mit „Invalid access to property or key 'lv'“ ab, die anderen blieben grün, prüften also teils alten Stand. Seitdem baut `tools/test.sh` die Testkarte neu, sobald sich der Kartencode (`game/src/map/*.gd`) geändert hat (`dev_utrecht/.kartencode`). Bei Karten außerhalb der Tests (Jonathans Karte für Bilder) die `baked_v*.bin` nach Code-Änderungen von Hand löschen.
