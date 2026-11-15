extends Node3D


func _init(pitch: Dictionary, t: Dictionary) -> void:
	var v: Dictionary = t.visual
	var length: float = pitch.length
	var width: float = pitch.width
	var line_w: float = v.line_width
	var line_h: float = v.line_height
	var line_color := Color(v.line_color as String)

	var ground := PlaneMesh.new()
	ground.size = Vector2(length + v.pitch_margin * 2.0, width + v.pitch_margin * 2.0)
	_add(ground, Color(v.pitch_color as String), Vector3.ZERO)

	for side in [-1.0, 1.0]:
		_add(_box(Vector3(length + line_w, line_h, line_w)), line_color, Vector3(0.0, line_h * 0.5, side * width * 0.5))
		_add(_box(Vector3(line_w, line_h, width + line_w)), line_color, Vector3(side * length * 0.5, line_h * 0.5, 0.0))
	_add(_box(Vector3(line_w, line_h, width)), line_color, Vector3(0.0, line_h * 0.5, 0.0))

	var circle := TorusMesh.new()
	circle.inner_radius = v.centre_circle_radius - line_w * 0.5
	circle.outer_radius = v.centre_circle_radius + line_w * 0.5
	_add(circle, line_color, Vector3(0.0, line_h * 0.5, 0.0)).scale.y = line_h / line_w

	var goal_w: float = pitch.get("goal_width", 0.0)
	if goal_w > 0.0:
		var goal_color := Color(v.goal_color as String)
		var goal_h: float = t.goal.height
		for side in [-1.0, 1.0]:
			var goal_x: float = side * length * 0.5
			for post_side in [-1.0, 1.0]:
				_add(_cylinder(t.goal.post_radius, goal_h), goal_color, Vector3(goal_x, goal_h * 0.5, post_side * goal_w * 0.5))
			_add(_cylinder(t.goal.post_radius, goal_w), goal_color, Vector3(goal_x, goal_h, 0.0)).rotation.x = PI * 0.5

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(v.sky_color as String)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = v.ambient_energy
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(v.sun_angles_deg[0], v.sun_angles_deg[1], 0.0)
	sun.shadow_enabled = true
	add_child(sun)


func _add(mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	return instance


func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	return cylinder
