# osm2streets als Vergleich im Kreuzungs-Prüfstand

Probe aus Meldung #5 (28.10.2026). [osm2streets](https://github.com/a-b-street/osm2streets) (A/B Street, Apache-2.0) erzeugt aus OSM Fahrbahnflächen, Kreuzungsflächen und Markierungen. Hier läuft es als Vergleich gegen unsere eigene Straßen-Aufbereitung, nicht im Spiel.

## Bauen

Die aktuelle Fassung hängt an `muv-osm` von gitlab.com. Das ist aus dem Container und der Geräte-Shell nicht erreichbar. Deshalb nehmen wir den Stand direkt vor der Umstellung auf muv: Commit `e277778` (4. 3. 2024). Die Geometrie hat sich danach kaum geändert, nur das Lesen der Spuren.

```
git clone https://github.com/a-b-street/osm2streets && cd osm2streets && git fetch --depth=600 origin main
git worktree add ../o2s_2024 e277778 && cd ../o2s_2024
mkdir -p o2s_cli/src && cp <repo>/tools/kreuzungen_o2s/main.rs o2s_cli/src/
# o2s_cli/Cargo.toml: abstutil (git abstreet), anyhow + geom (workspace), osm2streets + streets_reader (path)
# Cargo.toml: "o2s_cli" bei [workspace] members ergänzen
cargo build --release -p o2s_cli       # ~2 min
```

## Laufen lassen

```
for f in testdata/kreuzungen/*.osm.pbf; do id=$(basename $f .osm.pbf); o2s_cli $f /tmp/o2s_raw/$id.std; done
tools/kreuzungen.sh /tmp/kreuzungen                       # unser Stand, legt /tmp/kreuzungen/export an
python3 tools/kreuzungen_o2s/o2s_to_bench.py /tmp/o2s_raw std testdata/kreuzungen/kreuzungen.json /tmp/kreuzungen/export /tmp/o2s_bench
python3 tools/kreuzungen.py /tmp/kreuzungen/export /tmp/o2s_bench --labels heute,o2s --out /tmp/vergleich
```

Der Umsetzer nimmt nur Straßen mit Kfz-Spuren. Eigene Rad- und Fußwege sind im Spiel Wege der Stadt. Die Gehwegecken schneidet er aus den Kreuzungsflächen, wie es das Spiel tun würde. Spuren und Abbiegewege liefert osm2streets in diesem Stand nicht, deshalb stehen dort „–“.

## Ergebnis der Probe (8 Kreuzungen, Kreis 150 m)

| | Knoten | Splitter | Gehweg auf Fahrbahn | Markierung |
|---|---|---|---|---|
| Spiel (Stand 28.10.) | 142 | 61 | 89 m² | 6,7 km |
| osm2streets | 98 | 66 | 150 m² | 16,1 km |

- Saubere Flächen an normalen Kreuzungen, viel mehr Markierungen (Leitlinien, Pfeile, Haltlinien).
- An großen Hamburger Knoten (Billhorner Brückenstraße, Deichtorplatz) bleiben Dreiecksflächen, Splitter und Stufen in der Breite.
- Auf der ganzen 10 × 10-km-Karte stürzt es ab (`trim_to_corners` → `must_shift_left`). In 1-km-Kacheln betrifft das 1 von 100.
- Keine Abbiegewege auf Spurebene in diesem Stand.

Entscheidung und weitere Schritte stehen im Verlauf von Meldung #5.
