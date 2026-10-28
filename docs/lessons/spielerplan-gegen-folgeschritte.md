---
titel: Wird ein festes Schema durch Spielerentscheidungen ersetzt, jede Annahme der Folgeschritte gegen leere und ungewöhnliche Pläne prüfen
bereich: baustelle
datum: 2026-10-28
pruefung: e2e:absperrung (Baustelle 2: alle Teile verworfen; Baustelle 3: Plan ohne Teil im Fahrstreifen)
---

**Was passiert ist:** Mit dem Absperrung-Designer (#9) baut die Kolonne den Plan des Spielers statt des festen Schemas. Lint, Kompilieren und das eigene Szenario waren grün. Eine unabhängige Prüfung fand trotzdem zwei Wege, auf denen ein Auftrag für immer hängen blieb:
- `Site._can_closure` verlangte „Material im Bus oder schon ein Teil aufgestellt“. Das Material wird beim Start entnommen. Verwirft ein geänderter Plan alle schon stehenden Teile, galt die Baustelle als „ohne Absperrmaterial“ – dauerhaft.
- Den Verkehr schaltete nur ein Teil im gesperrten Fahrstreifen um (`traffic_on`). Graben, Bagger-Anfahrt und Kipper setzen `traffic_on` voraus. Ein Plan nur mit Schildern und Markierung am Rand ließ sich übernehmen und aufbauen, danach ging nichts weiter.

**Ursache:** Das feste Schema garantierte stillschweigend Zustände (immer ein Teil im Fahrstreifen, Material ↔ aufgestellte Teile), auf die sich spätere Schritte verlassen. Mit freien Plänen gilt das nicht mehr, und die eigenen Tests benutzten nur sinnvolle Pläne.

**Regel:**
- Vor dem Freigeben eines Schemas die Folgeschritte nach Bedingungen durchsuchen, die es bisher garantierte (`grep` nach den Zustandsvariablen, hier `traffic_on`, `cargo.barriers`, `_placed_count`).
- Zustände, die „verbraucht“ werden (Material), ausdrücklich führen und speichern (`kit_used`), nicht aus anderen Größen ableiten.
- Im Test mindestens einen leeren bzw. extremen Plan und einen Planwechsel mitten im Aufbau bis zum Ende durchspielen.
- Prüfungen im Designer, die nur warnen, entbinden nicht davon: Das Spiel muss auch mit einem schlechten Plan weiterlaufen.
