---
titel: Beim Überspringen laufende Arbeit abbrechen – Callbacks der Arbeiter und des Baggers
bereich: baustelle
datum: 2026-10-28
pruefung: e2e:debug (Absperrung mitten im Aufbau überspringen, keine zusätzlichen Teile)
---

**Was zu beachten ist:** Arbeiter und Bagger arbeiten mit Callback-Ketten. `walk_to(…, func(): act(…, func(): …)))` setzt am Ende ein Absperrteil oder bucht Aushub. Wer einen Schritt von außen beendet (Debug-Menü, später vielleicht Laden oder Abbrechen) und die Ketten weiterlaufen lässt, bekommt Teile doppelt oder Volumen in einem schon fertigen Schritt.

**Regel:**
- Vor dem Setzen des Endzustands die laufende Arbeit beenden (`DebugTools._cancel_activity`):
  - bei den Arbeitern `path`, `action` und `_cb` leeren, Getragenes freigeben und `busy = false` setzen,
  - beim Bagger `rig.stop()`, Meta `cycle` leeren und `hook_item = null` setzen,
  - `_wtasks` leeren.
- Danach die normalen `_finish_*`- und `_complete`-Funktionen aufrufen, damit Status, Bedarf und Kipper-Logik wie im echten Ablauf weiterlaufen.
- Neue Schritte bekommen einen Fall in `DebugTools.finish_step` und eine Prüfung im Szenario `debug`.
