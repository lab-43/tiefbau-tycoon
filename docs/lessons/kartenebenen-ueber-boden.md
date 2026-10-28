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
