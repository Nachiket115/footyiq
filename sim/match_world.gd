extends Node3D

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const Sim = preload("res://core/sim.gd")
const InputMapper = preload("res://sim/input_mapper.gd")
const PitchView = preload("res://sim/pitch_view.gd")
const StadiumView = preload("res://sim/stadium_view.gd")
const BallView =preload("res://sim/ball.gd")
const PlayerBody = preload("res://sim/player_body.gd")

const TEMP_KICK_POWER := 0.5
const TEMP_PLAYER_START := Vector2(-0.6, 0.0)

var cfg: Dictionary
var state: WorldState
var ball_view: BallView
var player_views := {}


func _ready() -> void:
	cfg = Config.load_all("res://config")
	if not Config.errors.is_empty():
		for message in Config.errors:
			push_error(message)
		get_tree().quit(1)
		set_physics_process(false)
		return
	var t: Dictionary = cfg["tuning"]
	Engine.physics_ticks_per_second = int(t.sim.tick_rate)
	InputMapper.register(cfg["input"])

	state = WorldState.new()
	state.pitch = t.pitch.duplicate(true)
	state.ball.pos = Vector3(0.0, t.ball.radius, 0.0)
	var player := WorldState.PlayerState.new()
	player.pos = TEMP_PLAYER_START
	state.players.append(player)

	add_child(PitchView.new(state.pitch, t))
	add_child(StadiumView.new(state.pitch, t))
	ball_view = BallView.new(t)
	add_child(ball_view)
	for p in state.players:
		player_views[p.id] = PlayerBody.new(p, t)
		add_child(player_views[p.id])

	var camera := Camera3D.new()
	add_child(camera)
	var eye: Array = t.debug.spectator_pos
	var target: Array = t.debug.spectator_target
	camera.look_at_from_position(Vector3(eye[0], eye[1], eye[2]), Vector3(target[0], target[1], target[2]))
	_sync(true)


func _physics_process(_delta: float) -> void:
	Sim.step(state, _commands(), cfg)
	_sync(not state.events.is_empty())


func _commands() -> Array:
	if not Input.is_action_just_pressed("shoot"):
		return []
	var cmd := PlayerCommand.new()
	cmd.tick = state.tick + 1
	cmd.player_id = state.players[0].id
	cmd.action = PlayerCommand.Action.SHOOT
	cmd.power = TEMP_KICK_POWER
	cmd.lofted = Input.is_action_pressed("lofted")
	return [cmd]


func _sync(teleported: bool) -> void:
	ball_view.position = state.ball.pos
	if teleported:
		ball_view.reset_physics_interpolation()
	for p in state.players:
		player_views[p.id].sync(p)
