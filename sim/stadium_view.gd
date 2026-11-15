extends Node3D

const Meshes = preload("res://sim/meshes.gd")

var _seat_xf: Array[Transform3D] = []
var _seat_col: Array[Color] = []
var _body_xf: Array[Transform3D] = []
var _body_col: Array[Color] = []
var _head_xf: Array[Transform3D] = []
var _head_col: Array[Color] = []


func _init(pitch: Dictionary, t: Dictionary) -> void:
	var s: Dictionary = t.visual.stadium
	var c: Dictionary = s.crowd
	var half_l: float = pitch.length * 0.5 + s.gap
	var half_w: float = pitch.width * 0.5 + s.gap
	var concrete := Meshes.flat(s.concrete_color, 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.seed)

	for i in 4:
		var along_x := i % 2 == 0
		var stand := Node3D.new()
		stand.rotation.y = i * PI * 0.5
		add_child(stand)
		_build_stand(stand, (half_l if along_x else half_w) * 2.0, half_w if along_x else half_l, s, concrete, rng, i)

	Meshes.add_many(self, Meshes.box(Meshes.vec3(s.seat_size)), Meshes.instance_tinted(0.5), _seat_xf, _seat_col)
	Meshes.add_many(self, Meshes.capsule(c.body_radius, c.body_height, 6), Meshes.instance_tinted(0.9), _body_xf, _body_col)
	Meshes.add_many(self, Meshes.sphere(c.head_radius, 8), Meshes.instance_tinted(0.7), _head_xf, _head_col)

	var mast := Meshes.flat(s.steel_color, 0.5)
	var lamp := Meshes.glowing(s.lamp_color, s.lamp_energy)
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			var base := Vector3(x_side * (half_l + s.depth * 0.5), 0.0, z_side * (half_w + s.depth * 0.5))
			Meshes.add(self, Meshes.cylinder(s.mast_radius, s.mast_height), mast, base + Vector3.UP * s.mast_height * 0.5)
			var head := Meshes.add(self, Meshes.box(Meshes.vec3(s.lamp_size)), lamp, base + Vector3.UP * s.mast_height)
			head.look_at_from_position(head.position, Vector3.ZERO)


func _build_stand(stand: Node3D, along: float, dist: float, s: Dictionary, concrete: Material, rng: RandomNumberGenerator, index: int) -> void:
	var depth: float = s.depth
	var base_h: float = s.base_height
	var rows := int(depth / s.row_depth)
	var row_rise: float = s.height / rows
	var seats := int(along / s.seat_width)
	var seat_size := Meshes.vec3(s.seat_size)

	Meshes.add(stand, Meshes.box(Vector3(along, base_h, s.wall_thickness)), concrete, Vector3(0.0, base_h * 0.5, dist + s.wall_thickness * 0.5))
	var boards: Array = s.board_colors
	var panel_w: float = along / s.board_panels
	for p in int(s.board_panels):
		var board := Meshes.glowing(boards[(p + index) % boards.size()], s.board_energy)
		var board_x: float = -along * 0.5 + panel_w * (p + 0.5)
		Meshes.add(stand, Meshes.box(Vector3(panel_w, s.board_height, s.board_thickness)), board, Vector3(board_x, s.board_height * 0.5, dist - s.board_thickness * 0.5))

	for row in rows:
		var top: float = base_h + (row + 1) * row_rise
		var z: float = dist + s.wall_thickness + (row + 0.5) * s.row_depth
		Meshes.add(stand, Meshes.box(Vector3(along, top, s.row_depth)), concrete, Vector3(0.0, top * 0.5, z))
		for seat in seats:
			if seat % int(s.aisle_every) < int(s.aisle_width):
				continue
			var x: float = -along * 0.5 + (seat + 0.5) * s.seat_width
			_add_seat(stand.transform, Vector3(x, top, z), seat_size, s, rng)

	var top_of_stand: float = base_h + s.height + s.roof_clearance
	var back_z: float = dist + s.wall_thickness + depth
	var span: float = along + depth * 2.0
	Meshes.add(stand, Meshes.box(Vector3(span, top_of_stand, s.wall_thickness)), concrete, Vector3(0.0, top_of_stand * 0.5, back_z))
	var roof_depth: float = depth * s.roof_cover
	var roof_front: float = back_z - roof_depth
	Meshes.add(stand, Meshes.box(Vector3(span, s.wall_thickness, roof_depth)), Meshes.flat(s.roof_color, 0.4), Vector3(0.0, top_of_stand, back_z - roof_depth * 0.5))
	Meshes.add(stand, Meshes.box(Vector3(span, s.fascia_height, s.wall_thickness)), Meshes.flat(s.fascia_color, 0.4), Vector3(0.0, top_of_stand, roof_front))
	var steel := Meshes.flat(s.steel_color, 0.5)
	var columns := int(along / s.column_spacing)
	for col in columns + 1:
		var col_x: float = -along * 0.5 + col * along / columns
		Meshes.add(stand, Meshes.cylinder(s.column_radius, top_of_stand), steel, Vector3(col_x, top_of_stand * 0.5, back_z - s.column_radius * 2.0))


func _add_seat(stand_xf: Transform3D, step: Vector3, seat_size: Vector3, s: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Dictionary = s.crowd
	var seat_pos := step + Vector3(0.0, seat_size.y * 0.5, s.row_depth * 0.3)
	_seat_xf.append(stand_xf * Transform3D(Basis.IDENTITY, seat_pos))
	_seat_col.append(Color(s.seat_color as String))
	if rng.randf() > c.occupancy:
		return
	var size := rng.randf_range(c.size_min, c.size_max)
	var lift: float = c.standing_lift if rng.randf() < c.standing_share else c.seated_lift
	var feet := step + Vector3(rng.randf_range(-c.jitter, c.jitter), lift, 0.0)
	var body_h: float = c.body_height * size
	_body_xf.append(stand_xf * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), feet + Vector3.UP * body_h * 0.5))
	var clothes: Array = c.clothing_colors
	var shade := rng.randf_range(c.shade_min, 1.0)
	_body_col.append(Color(clothes[rng.randi() % clothes.size()] as String) * Color(shade, shade, shade))
	_head_xf.append(stand_xf * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), feet + Vector3.UP * (body_h + c.head_radius * size * 0.7)))
	var skins: Array = c.skin_colors
	_head_col.append(Color(skins[rng.randi() % skins.size()] as String))
