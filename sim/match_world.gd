extends Node3D

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const Sim = preload("res://core/sim.gd")
const BallControl = preload("res://core/ball_control.gd")
const Roles = preload("res://bots/roles.gd")
const BotController = preload("res://sim/bot_controller.gd")
const InputMapper = preload("res://sim/input_mapper.gd")
const HumanController = preload("res://sim/human_controller.gd")
const CameraRig = preload("res://sim/camera_rig.gd")
const FirstPersonRig = preload("res://sim/first_person_rig.gd")
const PitchView = preload("res://sim/pitch_view.gd")
const StadiumView = preload("res://sim/stadium_view.gd")
const BallView = preload("res://sim/ball.gd")
const PlayerBody = preload("res://sim/player_body.gd")
const Meshes = preload("res://sim/meshes.gd")
const BodyIndicator = preload("res://ui/body_indicator.gd")
const Hud = preload("res://ui/hud.gd")
const Sounds = preload("res://sim/sounds.gd")

const VIEWS := ["chase", "first", "spectator"]

var cfg: Dictionary
var state: WorldState
var controlled_id := 0

var _mapper: InputMapper
var _controller: HumanController
var _bots: BotController
var _rig: CameraRig
var _spectator := Camera3D.new()
var _body_indicator: BodyIndicator
var _ball_view: BallView
var _player_views := {}
var _prev_ball: Vector3
var _prev_players := {}
var _eye_height: float
var _switch_tick := 0
var _paused_until_ms := 0
var _view := "chase"
var _drill: Dictionary
var _hud: Hud
var _sounds: Sounds
var _banner_until_ms := 0


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

	var drill: Dictionary = cfg["drills"][t.debug.drill]
	_drill = drill
	state = Roles.spawn(drill, t)
	Sim.seed_rng(state, Time.get_ticks_usec())
	for p in state.players:
		if p.team == 0 and p.role == drill.human_default_role:
			controlled_id = p.id
	var sides := []
	for side: Dictionary in t.debug.teams:
		sides.append(BotController.team(cfg, drill, side.difficulty, side.attack, side.defend))
	_bots = BotController.new(cfg, sides)
	_bots.human_id = controlled_id

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
	var hud := CanvasLayer.new()
	add_child(hud)
	_body_indicator = BodyIndicator.new(t.hud.body_indicator, deg_to_rad(t.player.head_yaw_limit_deg))
	hud.add_child(_body_indicator)
	_hud = Hud.new(t.hud.match)
	hud.add_child(_hud)
	_sounds = Sounds.new(t.audio)
	add_child(_sounds)
	_controller.cam_yaw = state.player_by_id(controlled_id).body_yaw
	_set_view(t.camera.view)
	_remember()


func _physics_process(_delta: float) -> void:
	_remember()
	if Time.get_ticks_msec() < _paused_until_ms:
		return
	var input := _mapper.poll()
	var owner := state.player_by_id(state.ball.owner_id)
	input.tackle = input.trap and owner != null and owner.team != state.player_by_id(controlled_id).team
	var command := _controller.build_command(state.tick + 1, controlled_id, input)
	if _view != "first":
		_controller.assist(command, state)
	Sim.step(state, [command] + _bots.commands(state), cfg)
	_controller.sync(state.player_by_id(controlled_id).head_yaw)
	var t: Dictionary = cfg["tuning"]
	var settled: bool = state.tick - _switch_tick >= t.switch.defend_cooldown_s * t.sim.tick_rate
	if input.switch:
		set_control(BallControl.switch_target(state, controlled_id))
	else:
		set_control(BallControl.control_after(state, controlled_id, t.control_mode != "locked_position", settled, t.control_mode == "follow_ball"))
	for p in state.players:
		_player_views[p.id].dive(PlayerBody.dive_side(p, state.ball, t))
	for event in state.events:
		if event.type == "pass" or event.type == "shot":
			_sounds.play("kick")
		elif event.type == "goal":
			_kickoff()
	if not state.events.is_empty():
		_prev_ball = state.ball.pos


func set_control(id: int) -> void:
	if id == controlled_id:
		return
	var t: Dictionary = cfg["tuning"]
	_player_views[controlled_id].visible = true
	_player_views[id].visible = _view != "first"
	controlled_id = id
	_switch_tick = state.tick
	_bots.human_id = id
	var p := state.player_by_id(id)
	_controller.take_over(p.head_yaw, p.head_pitch)
	var eye := Vector3(p.pos.x, _eye_height, p.pos.y)
	if _view == "first":
		_rig.blend_to(eye, p.body_yaw + p.head_yaw, p.head_pitch, t.switch.blend_s)
	else:
		_rig.blend_to(eye, _controller.cam_yaw, _controller.cam_pitch, t.switch.blend_s)
	if t.switch_mode == "pause":
		_paused_until_ms = Time.get_ticks_msec() + int(t.switch.pause_s * 1000.0)
	elif t.switch_mode == "slowmo":
		Engine.time_scale = t.switch.slowmo_scale
		get_tree().create_timer(t.switch.blend_s, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_camera"):
		_set_view(VIEWS[(VIEWS.find(_view) + 1) % VIEWS.size()])


func _process(delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	if _view == "first":
		_controller.update_look(_mapper.take_look(delta), delta, f)
	else:
		_controller.orbit(_mapper.take_look(delta))
	_body_indicator.head_yaw = _controller.view_yaw
	_ball_view.position = _prev_ball.lerp(state.ball.pos, f)
	for p in state.players:
		var prev: Array = _prev_players[p.id]
		var pos: Vector2 = prev[0].lerp(p.pos, f)
		var body_yaw := lerp_angle(prev[1], p.body_yaw, f)
		var head_yaw := lerp_angle(prev[2], p.head_yaw, f)
		var head_pitch := lerpf(prev[3], p.head_pitch, f)
		if p.id == controlled_id and _view == "first":
			head_yaw = _controller.view_yaw
			head_pitch = _controller.view_pitch
			_rig.set_pose(Vector3(pos.x, _eye_height, pos.y), body_yaw + head_yaw, head_pitch)
		elif p.id == controlled_id:
			_rig.set_pose(Vector3(pos.x, _eye_height, pos.y), _controller.cam_yaw, _controller.cam_pitch)
		_player_views[p.id].sync(pos, body_yaw, head_yaw, head_pitch)
	_update_hud(f)


func _remember() -> void:
	_prev_ball = state.ball.pos
	for p in state.players:
		_prev_players[p.id] = [p.pos, p.body_yaw, p.head_yaw, p.head_pitch]


func _set_view(view: String) -> void:
	_view = view
	_rig.chase = view == "chase"
	_rig.set_active(view != "spectator")
	_spectator.current = view == "spectator"
	_player_views[controlled_id].visible = view != "first"
	_body_indicator.visible = view == "first" and cfg["tuning"].hud.body_indicator.enabled


func _kickoff() -> void:
	var t: Dictionary = cfg["tuning"]
	var fresh := Roles.spawn(_drill, t)
	for p in state.players:
		p.pos = fresh.players[p.id].pos
		p.vel = Vector2.ZERO
		p.body_yaw = fresh.players[p.id].body_yaw
	_sounds.play("whistle")
	_banner_until_ms = Time.get_ticks_msec() + int(t.hud.match.banner_s * 1000.0)
	_paused_until_ms = _banner_until_ms


func _update_hud(f: float) -> void:
	var t: Dictionary = cfg["tuning"]
	_hud.score = state.score
	_hud.seconds = state.tick / t.sim.tick_rate
	_hud.charge = _controller.charge
	_hud.banner = "GOAL" if Time.get_ticks_msec() < _banner_until_ms else ""
	var marked := {controlled_id: "you_color"}
	if state.ball.owner_id == controlled_id:
		marked[_controller.receiver(state, controlled_id, _controller.charge if _controller.charge > 0.0 else 1.0)] = "pass_color"
	else:
		marked[BallControl.switch_target(state, controlled_id)] = "switch_color"
	_hud.markers.clear()
	var camera := get_viewport().get_camera_3d()
	for p in state.players:
		if not marked.has(p.id) or (p.id == controlled_id and _view == "first"):
			continue
		var pos: Vector2 = _prev_players[p.id][0].lerp(p.pos, f)
		var above := Vector3(pos.x, t.player.height + t.hud.match.marker_lift, pos.y)
		if camera.is_position_behind(above):
			continue
		var spot := camera.unproject_position(above)
		if get_viewport().get_visible_rect().has_point(spot):
			_hud.markers.append([spot, marked[p.id]])
