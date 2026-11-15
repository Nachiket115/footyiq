extends Node3D

const Meshes = preload("res://sim/meshes.gd")
const GRASS_SHADER = preload("res://sim/shaders/grass.gdshader")
const NET_SHADER = preload("res://sim/shaders/net.gdshader")


func _init(pitch: Dictionary, t: Dictionary) -> void:
	var v: Dictionary = t.visual
	var length: float = pitch.length
	var width: float = pitch.width
	var line_w: float = v.line_width
	var line_h: float = v.line_height
	var line := Meshes.flat(v.line_color)

	var ground := PlaneMesh.new()
	ground.size = Vector2(length + v.pitch_margin * 2.0, width + v.pitch_margin * 2.0)
	var grass := Meshes.shader(GRASS_SHADER, {
		"albedo_tex": load(v.grass_maps.color),
		"normal_tex": load(v.grass_maps.normal),
		"roughness_tex": load(v.grass_maps.roughness),
		"tint": Color(v.grass_tint as String),
		"tile_size": v.grass_tile_size,
		"stripe_width": v.mow_stripe_width,
		"stripe_contrast": v.mow_stripe_contrast,
	})
	Meshes.add(self, ground, grass, Vector3.ZERO)

	for side in [-1.0, 1.0]:
		Meshes.add(self, Meshes.box(Vector3(length + line_w, line_h, line_w)), line, Vector3(0.0, line_h * 0.5, side * width * 0.5))
		Meshes.add(self, Meshes.box(Vector3(line_w, line_h, width + line_w)), line, Vector3(side * length * 0.5, line_h * 0.5, 0.0))
	Meshes.add(self, Meshes.box(Vector3(line_w, line_h, width)), line, Vector3(0.0, line_h * 0.5, 0.0))

	var circle := TorusMesh.new()
	circle.inner_radius = v.centre_circle_radius - line_w * 0.5
	circle.outer_radius = v.centre_circle_radius + line_w * 0.5
	Meshes.add(self, circle, line, Vector3(0.0, line_h * 0.5, 0.0)).scale.y = line_h / line_w

	var goal_w: float = pitch.get("goal_width", 0.0)
	if goal_w > 0.0:
		for side in [-1.0, 1.0]:
			_add_goal(side, side * length * 0.5, goal_w, t)
	_add_lighting(v)


func _add_goal(side: float, goal_x: float, goal_w: float, t: Dictionary) -> void:
	var v: Dictionary = t.visual
	var goal_h: float = t.goal.height
	var radius: float = t.goal.post_radius
	var depth: float = v.net_depth
	var frame := Meshes.flat(v.goal_color, 0.4)
	for post_side in [-1.0, 1.0]:
		Meshes.add(self, Meshes.cylinder(radius, goal_h), frame, Vector3(goal_x, goal_h * 0.5, post_side * goal_w * 0.5))
	Meshes.add(self, Meshes.cylinder(radius, goal_w), frame, Vector3(goal_x, goal_h, 0.0)).rotation.x = PI * 0.5

	var net := Meshes.shader(NET_SHADER, {"color": Color(v.goal_color as String)})
	var mid_x := goal_x + side * depth * 0.5
	_add_net(Vector2(goal_w, goal_h), net, Vector3(goal_x + side * depth, goal_h * 0.5, 0.0), v).rotation.y = PI * 0.5
	_add_net(Vector2(depth, goal_w), net, Vector3(mid_x, goal_h, 0.0), v).rotation.x = -PI * 0.5
	for net_side in [-1.0, 1.0]:
		_add_net(Vector2(depth, goal_h), net, Vector3(mid_x, goal_h * 0.5, net_side * goal_w * 0.5), v)


func _add_net(size: Vector2, material: Material, pos: Vector3, v: Dictionary) -> MeshInstance3D:
	var panel := Meshes.add(self, Meshes.quad(size), material, pos)
	panel.set_instance_shader_parameter("cells", size / v.net_spacing)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return panel


func _add_lighting(v: Dictionary) -> void:
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = load(v.sky_path)
	var sky := Sky.new()
	sky.sky_material = panorama
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = v.sky_energy
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = v.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = v.tonemap_white
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = v.glow_intensity
	env.fog_enabled = true
	env.fog_density = v.fog_density
	env.fog_aerial_perspective = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.look_at_from_position(Meshes.vec3(v.sun_direction), Vector3.ZERO)
	sun.light_color = Color(v.sun_color as String)
	sun.light_energy = v.sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = v.shadow_distance
