extends RefCounted


static func flat(color: String, roughness := 0.8) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = roughness
	return material


static func shader(code: Shader, params: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = code
	for key: String in params:
		material.set_shader_parameter(key, params[key])
	return material


static func add(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	parent.add_child(instance)
	return instance


static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return mesh


static func sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh


static func quad(size: Vector2) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = size
	return mesh


static func vec3(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
