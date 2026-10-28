---
titel: Ein frisch geöffnetes Vollbild-Werkzeug bekommt Maus-Ereignisse aus Tests erst einen Frame später – erst warten, dann klicken
bereich: ui
datum: 2026-10-29
pruefung: e2e:stellplaetze
---

**Was passiert ist:** Im Szenario `stellplaetze` (#22) wurde der Planungsmodus geöffnet und im selben Frame mit `push_input(ev, true)` gezogen. Keine Ziehbewegung kam an: `ClosureDesigner._mouse` blieb `(0, 0)`, `_unhandled_input` lief nie. Tastendrücke im selben Frame wirkten dagegen (Szenario `vollsperrung`). Im Szenario `absperrung` lag zwischen Öffnen und Klicken schon immer ein Schritt, deshalb fiel es dort nicht auf.

**Ursache:** Nicht ganz geklärt. Die Steuerelemente des Werkzeugs (Seitenleisten mit `MOUSE_FILTER_STOP`) und das gerade ausgeblendete HUD werden erst beim nächsten Layout-Durchlauf richtig berechnet; bis dahin landen Maus-Ereignisse offenbar in der GUI und kommen nicht bis `_unhandled_input`.

**Regel:**
- In Tests nach dem Öffnen eines Werkzeugs, Fensters oder Panels mindestens einen Frame (Schritt mit `drv.t - t_mark < 0.5`) warten, bevor echte Maus-Ereignisse geschickt werden.
- Kommt ein gezogener oder geklickter Test-Schritt nicht an, zuerst prüfen, ob das Ziel das Ereignis überhaupt bekommt (`_mouse`, `_over_map`), bevor man die Logik verdächtigt.
