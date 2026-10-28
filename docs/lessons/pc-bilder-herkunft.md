---
titel: PNG und JPEG kommen auf dem PC mit Herkunftsdaten an – Bilder ohne diesen Block vergleichen
bereich: pc-bruecke
datum: 2026-10-29
pruefung: manuell: Bilddaten ohne APP11/caBX im Container und auf dem PC hashen (Skript unten)
---

**Was passiert ist:** Meldung #24. 108 Asset-Dateien der neuen Maschinen gingen per `device_commit_files` nach `game/assets/consim/`. Alle `.glb`, `.json` und `.import` hatten auf dem PC dieselbe SHA256 wie im Container, aber **alle 47 JPEG-Texturen** wichen ab. Beispiel `excavator_r938_Generic_Normal_N_T.jpg`: 320 Byte im Container, 6091 Byte auf dem PC. Dazugekommen war ein JPEG-Segment `0xFFEB` (APP11) mit einem C2PA-/JUMBF-Herkunftsnachweis (~5,7 KB). Bei PNG war schon bekannt, dass ein `caBX`-Block dazukommt (pc-bruecke.md).

**Ursache:** Die Brücke versieht Bilder beim Schreiben auf den PC mit Herkunftsdaten. Die Bilddaten selbst bleiben gleich; Decoder (auch Godot) überspringen APP11-Segmente und unbekannte PNG-Blöcke.

**Regel:**
- Nach einer Übertragung Nicht-Bilder per SHA256 vergleichen, Bilder getrennt: erst die Herkunftsblöcke entfernen, dann hashen. Für JPEG:
  ```python
  d=open(f,'rb').read(); o=bytearray(d[:2]); i=2
  while d[i]==0xFF and d[i+1]!=0xDA:
      L=int.from_bytes(d[i+2:i+4],'big')
      if d[i+1]!=0xEB: o+=d[i:i+2+L]
      i+=2+L
  o+=d[i:]   # sha256(o) muss im Container und auf dem PC gleich sein
  ```
- Eine abweichende Bild-Prüfsumme ist deshalb kein Übertragungsfehler. Eine abweichende Prüfsumme bei `.glb`, `.pck`, `.json` schon.
- `private/assets.tar` enthält danach die Bilder mit Herkunftsdaten. Das ist in Ordnung, die Texturen laden gleich.
