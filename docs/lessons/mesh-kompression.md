---
titel: Komprimierte Meshes runden Positionen auf 1/65535 der Chunk-Größe
bereich: godot
datum: 2026-10-28
pruefung: e2e:gelaende (Toleranz aus der AABB)
---

**Was passiert ist:** Meldung #8. Der Test „Ebene liegt auf dem Gelände“ meldete bei `area_residential` 7,6 cm Abweichung, obwohl der Punkt in `MeshLayer` exakt angehoben war (roh 6,483 m bei Grund 6,471 m). `MapBuilder.add_chunk_layers` baut die Meshes mit `Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES`. Godot speichert die Positionen dann als 16 Bit relativ zur AABB. Diese Fläche reichte über 5,7 km, also wurde x/z auf etwa 9 cm gerundet. An einer steilen Stelle wurde daraus ein Höhenfehler von mehreren Zentimetern.
**Ursache:** Kompression ist für Dinge wie Zentimeter-Ebenen zu grob, sobald ein Chunk-Mesh große Flächen enthält.
**Regel:**
- Exakte Höhenreihenfolge nie über Vertex-Positionen sicherstellen, sondern im Shader (`terrain_depth`, Lektion gelaende-hoehen).
- Tests, die Vertex-Positionen aus fertigen Meshes lesen, rechnen mit der Toleranz `max(AABB-Breite, -Tiefe) / 65535` mal Steigung.
