extends Node3D

const Meshes = preload("res://sim/meshes.gd")
const CROWD_SHADER = preload("res://sim/shaders/crowd.gdshader")


func _init(pitch: Dictionary, t: Dictionary) -> void:
	var s: Dictionary = t.visual.stadium
	var half_l: float = pitch.length * 0.5 + s.gap
	var half_w: float = pitch.width * 0.5 + s.gap
	var crowd := Meshes.shader(CROWD_SHADER, {
		"seat_color": Color(s.seat_color as String),
		"seat_width": s.seat_width,
		"row_depth": s.row_depth,
		"occupancy": s.occupancy,
	})
	for i in 4:
		var along_x := i % 2 == 0
		var stand := Node3D.new()
		stand.rotation.y = i * PI * 0.5
		add_child(stand)
		_build_stand(stand, (half_l if along_x else half_w) * 2.0, half_w if along_x else half_l, s, crowd, i)

	var mast := Meshes.flat(s.concrete_color)
	var lamp := Meshes.flat(s.lamp_color)
	lamp.emission_enabled = true
	lamp.emission = Color(s.lamp_color as String)
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			var base := Vector3(x_side * (half_l + s.depth * 0.5), 0.0, z_side * (half_w + s.depth * 0.5))
			Meshes.add(self, Meshes.cylinder(s.mast_radius, s.mast_height), mast, base + Vector3.UP * s.mast_height * 0.5)
			var head := Meshes.add(self, Meshes.box(Meshes.vec3(s.lamp_size)), lamp, base + Vector3.UP * s.mast_height)
			head.look_at_from_position(head.position, Vector3.ZERO)


func _build_stand(stand: Node3D, along: float, dist: float, s: Dictionary, crowd: Material, index: int) -> void:
	var depth: float = s.depth
	var rise: float = s.height
	var base_h: float = s.base_height
	var concrete := Meshes.flat(s.concrete_color)
	var boards: Array = s.board_colors

	Meshes.add(stand, Meshes.box(Vector3(along, base_h, s.wall_thickness)), concrete, Vector3(0.0, base_h * 0.5, dist + s.wall_thickness * 0.5))
	var panel_w: float = along / s.board_panels
	for p in int(s.board_panels):
		var board := Meshes.flat(boards[(p + index) % boards.size()], 0.5)
		var x: float = -along * 0.5 + panel_w * (p + 0.5)
		Meshes.add(stand, Meshes.box(Vector3(panel_w, s.board_height, s.board_thickness)), board, Vector3(x, s.board_height * 0.5, dist - s.board_thickness * 0.5))

	var slope := Meshes.add(stand, Meshes.box(Vector3(along, s.wall_thickness, Vector2(depth, rise).length())), crowd, Vector3(0.0, base_h + rise * 0.5, dist + depth * 0.5))
	slope.rotation.x = -atan2(rise, depth)

	var top: float = base_h + rise + s.roof_clearance
	Meshes.add(stand, Meshes.box(Vector3(along + depth * 2.0, top, s.wall_thickness)), concrete, Vector3(0.0, top * 0.5, dist + depth))
	var roof_depth: float = depth * s.roof_cover
	Meshes.add(stand, Meshes.box(Vector3(along + depth * 2.0, s.wall_thickness, roof_depth)), Meshes.flat(s.roof_color, 0.5), Vector3(0.0, top, dist + depth - roof_depth * 0.5))
