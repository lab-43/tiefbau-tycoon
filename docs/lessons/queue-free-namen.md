---
titel: Vor queue_free() erst remove_child()
bereich: ui
datum: 2026-10-27
pruefung: manuell
---

**Was passiert ist:** Nach `queue_free()` blieb der alte Node bis zum Frame-Ende im Baum. Ein neuer Node mit gleichem Namen bekam deshalb „@Label@123“, und die Schrittzeiten im Ladebildschirm fehlten.

**Regel:** Wenn Namen wiederverwendet werden, zuerst `parent.remove_child(n)` und dann `n.queue_free()`.
