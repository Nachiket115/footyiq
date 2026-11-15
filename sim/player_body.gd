extends Node3D

const WorldState = preload("res://core/world_state.gd")

var head := Node3D.new()


func _init(player: WorldState.PlayerState, t: Dictionary) -> void:
	var v: Dictionary = t.visual
	var p: Dictionary = t.player
	var capsule := CapsuleMesh.new()
	capsule.radius = p.radius
	capsule.height = p.height
	_add(self, capsule, v.team_colors[player.team], Vector3(0.0, p.height * 0.5, 0.0))
	_add(self, _box(v.stripe_size), v.stripe_color, Vector3(0.0, v.stripe_height, -p.radius))
	head.position.y = p.eye_height
	add_child(head)
	_add(head, _box(v.visor_size), v.visor_color, Vector3(0.0, 0.0, -p.radius))


func sync(player: WorldState.PlayerState) -> void:
	position = Vector3(player.pos.x, 0.0, player.pos.y)
	rotation.y = -player.body_yaw - PI * 0.5
	head.rotation = Vector3(player.head_pitch, -player.head_yaw, 0.0)


func _add(parent: Node3D, mesh: Mesh, color: String, pos: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	parent.add_child(instance)


func _box(size: Array) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = Vector3(size[0], size[1], size[2])
	return box
