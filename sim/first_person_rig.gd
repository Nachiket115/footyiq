extends "res://sim/camera_rig.gd"

var camera := Camera3D.new()

var _fov_min: float
var _fov_max: float
var _blend_from: Transform3D
var _blend_s := 0.0
var _blend_left := 0.0
var _chase: Dictionary
var _fov: float

var chase := false:
	set(value):
		chase = value
		set_fov(_chase.fov_deg if chase else _fov)


func _init(settings: Dictionary) -> void:
	_fov_min = settings.fov_min
	_fov_max = settings.fov_max
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = settings.near
	add_child(camera)
	_chase = settings.chase
	_fov = settings.fov_deg
	set_fov(_fov)


func _process(delta: float) -> void:
	_blend_left = maxf(0.0, _blend_left - delta / Engine.time_scale)


func set_pose(eye: Vector3, yaw: float, pitch: float) -> void:
	var pose := Transform3D(Basis.from_euler(Vector3(pitch, -yaw - PI * 0.5, 0.0)), eye)
	if chase:
		pose.origin += pose.basis.z * _chase.back + Vector3.UP * _chase.lift
	if _blend_left > 0.0:
		pose = _blend_from.interpolate_with(pose, smoothstep(0.0, 1.0, 1.0 - _blend_left / _blend_s))
	transform = pose


func blend_to(eye: Vector3, yaw: float, pitch: float, seconds: float) -> void:
	_blend_from = transform
	_blend_s = seconds
	_blend_left = seconds
	set_pose(eye, yaw, pitch)


func set_fov(degrees: float) -> void:
	camera.fov = clampf(degrees, _fov_min, _fov_max)


func set_active(active: bool) -> void:
	camera.current = active
