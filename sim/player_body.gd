extends Node3D

const WorldState = preload("res://core/world_state.gd")
const KitShader = preload("res://sim/shaders/kit.gdshader")

const MANIFEST := "res://assets/characters/quaternius/character.json"
const REGION_SLOTS := 80

static var _m := {}
static var _library: AnimationLibrary


class HeadLook extends SkeletonModifier3D:
	var bones := PackedInt32Array()
	var yaw := 0.0
	var pitch := 0.0

	func _process_modification() -> void:
		var skeleton := get_skeleton()
		var share := 1.0 / bones.size()
		var turn := Basis(Vector3.UP, -yaw * share) * Basis(Vector3.RIGHT, -pitch * share)
		for bone in bones:
			var pose := skeleton.get_bone_global_pose(bone)
			pose.basis = turn * pose.basis
			skeleton.set_bone_global_pose(bone, pose)


var _anim := AnimationPlayer.new()
var _pivot := Node3D.new()
var _dive: Dictionary
var _diving: Tween
var _look := HeadLook.new()
var _last_pos := Vector2.ZERO
var _last_usec := 0


static func _manifest() -> Dictionary:
	if _m.is_empty():
		_m = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		var source: Node = load(_m.animations).instantiate()
		_library = (source.find_child("AnimationPlayer") as AnimationPlayer).get_animation_library("")
		source.free()
	return _m


func _init(player: WorldState.PlayerState, t: Dictionary) -> void:
	var m := _manifest()
	var model: Node3D = load(m.scene).instantiate()
	model.rotation.y = PI
	model.scale = Vector3.ONE * (t.player.height / m.model_height)
	add_child(_pivot)
	_pivot.add_child(model)
	_dive = t.visual.dive
	model.add_child(_anim)
	_anim.add_animation_library("", _library)

	var skeleton: Skeleton3D = model.find_child("Skeleton3D")
	for bone: String in m.look_bones:
		_look.bones.append(skeleton.find_bone(bone))
	skeleton.add_child(_look)

	var body: MeshInstance3D = model.find_child(m.kit.mesh)
	var source: StandardMaterial3D = body.mesh.surface_get_material(0)
	var team := Color(t.visual.team_colors[player.team])
	var kit := ShaderMaterial.new()
	kit.shader = KitShader
	kit.set_shader_parameter("albedo_map", source.albedo_texture)
	kit.set_shader_parameter("normal_map", source.normal_texture)
	kit.set_shader_parameter("roughness_map", source.roughness_texture)
	kit.set_shader_parameter("shirt", team)
	kit.set_shader_parameter("shorts", Color(t.visual.body.shorts_color))
	kit.set_shader_parameter("socks", team)
	kit.set_shader_parameter("boots", Color(m.kit.boot_color))
	kit.set_shader_parameter("region", _regions(body.skin, skeleton, m.kit.regions))
	body.set_surface_override_material(0, kit)


func sync(pos: Vector2, body_yaw: float, head_yaw: float, head_pitch: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := (now - _last_usec) / 1e6
	if elapsed > 0.0:
		_animate((pos - _last_pos).dot(Vector2.from_angle(body_yaw)) / elapsed)
	_last_pos = pos
	_last_usec = now
	position = Vector3(pos.x, 0.0, pos.y)
	rotation.y = -body_yaw - PI * 0.5
	_look.yaw = head_yaw
	_look.pitch = head_pitch


static func dive_side(player: WorldState.PlayerState, ball: WorldState.BallState, t: Dictionary) -> float:
	var vel := Vector2(ball.vel.x, ball.vel.z)
	if player.role != "gk" or ball.owner_id != -1 or vel.length() <= t.control.max_ball_speed * t.control.trap_speed_factor:
		return 0.0
	var at := Vector2(ball.pos.x, ball.pos.z)
	var along := (player.pos - at).dot(vel.normalized())
	if along < 0.0 or along > t.visual.dive.trigger_distance:
		return 0.0
	var miss := at + vel.normalized() * along - player.pos
	if miss.length() < t.player.radius or miss.length() > t.goal.dive_reach + t.ball.radius:
		return 0.0
	return signf(miss.dot(Vector2.from_angle(player.body_yaw + PI * 0.5)))


func dive(side: float) -> void:
	if side == 0.0 or (_diving != null and _diving.is_running()):
		return
	_diving = create_tween()
	_diving.tween_property(_pivot, "position:x", side * _dive.slide, _dive.in_s)
	_diving.parallel().tween_property(_pivot, "rotation:z", -side * deg_to_rad(_dive.lean_deg), _dive.in_s)
	_diving.tween_interval(_dive.hold_s)
	_diving.tween_property(_pivot, "position:x", 0.0, _dive.out_s)
	_diving.parallel().tween_property(_pivot, "rotation:z", 0.0, _dive.out_s)


func _animate(forward_speed: float) -> void:
	for clip: Dictionary in _m.clips:
		if absf(forward_speed) > clip.max_speed:
			continue
		if _anim.current_animation != clip.name:
			_anim.play(clip.name, _m.blend_s)
		_anim.speed_scale = 1.0 if clip.stride_speed == 0.0 else forward_speed / clip.stride_speed
		return


func _regions(skin: Skin, skeleton: Skeleton3D, groups: Array) -> PackedFloat32Array:
	var regions := PackedFloat32Array()
	regions.resize(REGION_SLOTS)
	for bind in mini(skin.get_bind_count(), REGION_SLOTS):
		var bone := String(skin.get_bind_name(bind))
		if bone.is_empty():
			bone = skeleton.get_bone_name(skin.get_bind_bone(bind))
		for group in groups.size():
			if groups[group].has(bone):
				regions[bind] = group + 1.0
	return regions
