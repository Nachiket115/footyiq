extends MeshInstance3D

const Meshes = preload("res://sim/meshes.gd")


func _init(t: Dictionary) -> void:
	mesh = Meshes.sphere(t.ball.radius)
	material_override = Meshes.flat(t.visual.ball_color, 0.35)
