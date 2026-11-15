extends Node3D

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const Sim = preload("res://core/sim.gd")
const InputMapper = preload("res://sim/input_mapper.gd")
const HumanController = preload("res://sim/human_controller.gd")
const CameraRig = preload("res://sim/camera_rig.gd")
const FirstPersonRig = preload("res://sim/first_person_rig.gd")
const PitchView = preload("res://sim/pitch_view.gd")
const StadiumView = preload("res://sim/stadium_view.gd")
const BallView = preload("res://sim/ball.gd")
const PlayerBody = preload("res://sim/player_body.gd")
const Meshes = preload("res://sim/meshes.gd")

const TEMP_PLAYER_START := Vector2(-0.6, 0.0)

var cfg: Dictionary
var state: WorldState
var controlled_id := 0

var _mapper: InputMapper
var _controller: HumanController
var _rig: CameraRig
var _spectator := Camera3D.new()
var _ball_view: BallView
var _player_views := {}
var _prev_ball: Vector3
var _prev_players := {}
var _eye_height: float


func _ready() -> void:
	cfg = Config.load_all("res://config")
	if not Config.errors.is_empty():
		for message in Config.errors:
			push_error(message)
		get_tree().quit(1)
		set_process(false)
		set_physics_process(false)
		return
	var t: Dictionary = cfg["tuning"]
	Engine.physics_ticks_per_second = int(t.sim.tick_rate)
	_eye_height = t.player.eye_height

	state = WorldState.new()
	state.pitch = t.pitch.duplicate(true)
	state.ball.pos = Vector3(0.0, t.ball.radius, 0.0)
	var player := WorldState.PlayerState.new()
	player.pos = TEMP_PLAYER_START
	state.players.append(player)
	controlled_id = player.id

	add_child(PitchView.new(state.pitch, t))
	add_child(StadiumView.new(state.pitch, t))
	_ball_view = BallView.new(t)
	add_child(_ball_view)
	for p in state.players:
		_player_views[p.id] = PlayerBody.new(p, t)
		add_child(_player_views[p.id])

	_mapper = InputMapper.new(cfg["input"], t.camera)
	add_child(_mapper)
	_controller = HumanController.new(t)
	_rig = FirstPersonRig.new(t.camera)
	add_child(_rig)
	add_child(_spectator)
	_spectator.look_at_from_position(Meshes.vec3(t.debug.spectator_pos), Meshes.vec3(t.debug.spectator_target))
	_set_first_person(true)
	_remember()


func _physics_process(_delta: float) -> void:
	_remember()
	var command := _controller.build_command(state.tick + 1, controlled_id, _mapper.poll())
	Sim.step(state, [command], cfg)
	if not state.events.is_empty():
		_prev_ball = state.ball.pos


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_camera"):
		_set_first_person(_player_views[controlled_id].visible)


func _process(delta: float) -> void:
	_controller.update_look(_mapper.take_look(delta), delta)
	var f := Engine.get_physics_interpolation_fraction()
	_ball_view.position = _prev_ball.lerp(state.ball.pos, f)
	for p in state.players:
		var prev: Array = _prev_players[p.id]
		var pos: Vector2 = prev[0].lerp(p.pos, f)
		var body_yaw := lerp_angle(prev[1], p.body_yaw, f)
		var head_yaw := lerp_angle(prev[2], p.head_yaw, f)
		var head_pitch := lerpf(prev[3], p.head_pitch, f)
		if p.id == controlled_id:
			head_yaw = _controller.view_yaw
			head_pitch = _controller.view_pitch
			_rig.set_pose(Vector3(pos.x, _eye_height, pos.y), body_yaw + head_yaw, head_pitch)
		_player_views[p.id].sync(pos, body_yaw, head_yaw, head_pitch)


func _remember() -> void:
	_prev_ball = state.ball.pos
	for p in state.players:
		_prev_players[p.id] = [p.pos, p.body_yaw, p.head_yaw, p.head_pitch]


func _set_first_person(first_person: bool) -> void:
	_rig.set_active(first_person)
	_spectator.current = not first_person
	_player_views[controlled_id].visible = not first_person
