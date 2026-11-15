extends MeshInstance3D


func _init(t: Dictionary) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = t.ball.radius
	sphere.height = t.ball.radius * 2.0
	mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(t.visual.ball_color as String)
	material_override = material
