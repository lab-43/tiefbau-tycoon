extends SceneTree
func _init() -> void:
	Geo.setup(52.0907, 5.1214)
	var p := OsmParser.new()
	var d := p.parse_dir("res://test_fixtures/utrecht/osm", 3000.0)
	print("STATS ", d.stats)
	var kinds := {}
	for a in d.areas:
		kinds[a.kind] = kinds.get(a.kind, 0) + 1
	print("AREAS ", kinds)
	quit()
