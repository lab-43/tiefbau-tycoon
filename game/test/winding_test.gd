extends Node3D
func _ready() -> void:
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.2,0.2,0.3); add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-60, 30, 0); add_child(sun)
	for k in 2:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a := Vector3(-1,0,-1) + Vector3(k*3,0,0); var b := Vector3(1,0,-1) + Vector3(k*3,0,0); var c := Vector3(1,0,1) + Vector3(k*3,0,0)
		st.set_normal(Vector3.UP)
		if k == 0:
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)   # a->b->c  (viewed from above: -z to +z ...)
		else:
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
		var mi := MeshInstance3D.new(); mi.mesh = st.commit()
		var m := StandardMaterial3D.new(); m.albedo_color = Color(1,0.4,0.1) if k == 0 else Color(0.1,1,0.4); mi.material_override = m
		add_child(mi)
	var cam := Camera3D.new(); cam.position = Vector3(1.5, 5, 4); add_child(cam); cam.look_at(Vector3(1.5,0,0)); cam.current = true
