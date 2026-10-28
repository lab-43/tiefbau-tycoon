// Tiny CLI for the Tiefbau Tycoon junction bench: osm input -> geojson outputs.
// usage: o2s_cli <input.osm|.osm.pbf> <out-prefix> [dual]
use abstutil::Timer;
use osm2streets::{Filter, MapConfig, Transformation};

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let input = std::fs::read(&args[1])?;
    let out = &args[2];
    let dual = args.get(3).map(|s| s == "dual").unwrap_or(false);
    let mut cfg = MapConfig::default();
    cfg.inferred_sidewalks = true;
    let mut timer = Timer::throwaway();
    let t0 = std::time::Instant::now();
    let (mut net, _doc) = streets_reader::osm_to_street_network(&input, None, cfg, &mut timer)?;
    let mut ts = Transformation::standard_for_clipped_areas();
    if dual {
        ts.retain(|t| !matches!(t, Transformation::CollapseShortRoads));
        ts.push(Transformation::MergeDualCarriageways);
    }
    net.apply_transformations(ts, &mut timer);
    let ms = t0.elapsed().as_millis();
    std::fs::write(format!("{out}.plain.geojson"), net.to_geojson(&Filter::All)?)?;
    std::fs::write(format!("{out}.lanes.geojson"), net.to_lane_polygons_geojson(&Filter::All)?)?;
    std::fs::write(format!("{out}.markings.geojson"), net.to_lane_markings_geojson(&Filter::All)?)?;
    std::fs::write(format!("{out}.imarkings.geojson"), net.to_intersection_markings_geojson(&Filter::All)?)?;
    println!("OK {} roads {} intersections {} ms", net.roads.len(), net.intersections.len(), ms);
    Ok(())
}
