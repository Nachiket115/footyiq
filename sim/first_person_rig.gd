extends "res://sim/camera_rig.gd"

var camera := Camera3D.new()

var _fov_min: float
var _fov_max: float


func _init(settings: Dictionary) -> void:
	_fov_min = settings.fov_min
	_fov_max = settings.fov_max
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = settings.near
	add_child(camera)
	set_fov(settings.fov_deg)


func set_pose(eye: Vector3, yaw: float, pitch: float) -> void:
	position = eye
	rotation = Vector3(pitch, -yaw - PI * 0.5, 0.0)


func set_fov(degrees: float) -> void:
	camera.fov = clampf(degrees, _fov_min, _fov_max)


func set_active(active: bool) -> void:
	camera.current = active
