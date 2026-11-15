extends Node3D

const WorldState = preload("res://core/world_state.gd")
const Meshes = preload("res://sim/meshes.gd")

var head := Node3D.new()


func _init(player: WorldState.PlayerState, t: Dictionary) -> void:
	var v: Dictionary = t.visual
	var b: Dictionary = v.body
	var shirt := Meshes.flat(v.team_colors[player.team])
	var shorts := Meshes.flat(b.shorts_color)
	var skin := Meshes.flat(b.skin_color)
	var torso := Meshes.vec3(b.torso_size)
	var arm := Meshes.vec3(b.arm_size)

	Meshes.add(self, Meshes.box(torso), shirt, Vector3(0.0, b.torso_height, 0.0))
	Meshes.add(self, Meshes.box(Meshes.vec3(b.shorts_size)), shorts, Vector3(0.0, b.shorts_height, 0.0))
	Meshes.add(self, Meshes.box(Meshes.vec3(v.stripe_size)), Meshes.flat(v.stripe_color), Vector3(0.0, b.torso_height, -torso.z * 0.5))
	for side in [-1.0, 1.0]:
		Meshes.add(self, Meshes.cylinder(b.leg_radius, b.leg_length), skin, Vector3(side * b.leg_spacing, b.leg_length * 0.5, 0.0))
		Meshes.add(self, Meshes.box(arm), shirt, Vector3(side * (torso.x + arm.x) * 0.5, b.torso_height + (torso.y - arm.y) * 0.5, 0.0))

	head.position.y = t.player.eye_height
	add_child(head)
	Meshes.add(head, Meshes.sphere(b.head_radius), skin, Vector3.ZERO)
	Meshes.add(head, Meshes.box(Meshes.vec3(v.visor_size)), Meshes.flat(v.visor_color, 0.2), Vector3(0.0, 0.0, -b.head_radius))


func sync(pos: Vector2, body_yaw: float, head_yaw: float, head_pitch: float) -> void:
	position = Vector3(pos.x, 0.0, pos.y)
	rotation.y = -body_yaw - PI * 0.5
	head.rotation = Vector3(head_pitch, -head_yaw, 0.0)
