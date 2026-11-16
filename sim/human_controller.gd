extends RefCounted

const PlayerCommand = preload("res://core/player_command.gd")

var view_yaw := 0.0
var view_pitch := 0.0

var _look_yaw := 0.0
var _look_pitch := 0.0
var _commanded_yaw := 0.0
var _sim_adjust := 0.0
var _yaw_limit: float
var _pitch_limit: float
var _smoothing: float
var _charge_per_tick: float

var charge := 0.0


func _init(t: Dictionary) -> void:
	_yaw_limit = deg_to_rad(t.player.head_yaw_limit_deg)
	_pitch_limit = deg_to_rad(t.player.head_pitch_limit_deg)
	_smoothing = t.camera.look_smoothing_s
	_charge_per_tick = 1.0 / (t.kick.charge_time * t.sim.tick_rate)


func update_look(look_delta: Vector2, dt: float, tick_fraction := 1.0) -> void:
	_look_yaw += look_delta.x
	_look_pitch = clampf(_look_pitch + look_delta.y, -_pitch_limit, _pitch_limit)
	var target := clampf(_look_yaw - _sim_adjust * (1.0 - tick_fraction), -_yaw_limit, _yaw_limit)
	var blend := 1.0 if _smoothing <= 0.0 else 1.0 - exp(-dt / _smoothing)
	view_yaw = lerpf(view_yaw, target, blend)
	view_pitch = lerpf(view_pitch, _look_pitch, blend)


func build_command(tick: int, player_id: int, input: Dictionary) -> PlayerCommand:
	var cmd := PlayerCommand.new()
	cmd.tick = tick
	cmd.player_id = player_id
	cmd.move = input.move
	cmd.sprint = input.sprint
	cmd.align = input.align
	cmd.look_yaw = _look_yaw
	cmd.look_pitch = _look_pitch
	cmd.lofted = input.lofted
	if input.shoot:
		cmd.action = PlayerCommand.Action.SHOOT
		cmd.power = 1.0
	elif input.pass_released:
		cmd.action = PlayerCommand.Action.PASS
		cmd.power = charge
	elif input.trap:
		cmd.action = PlayerCommand.Action.TRAP
	charge = minf(charge + _charge_per_tick, 1.0) if input.pass_held else 0.0
	_commanded_yaw = _look_yaw
	return cmd


func sync(head_yaw: float) -> void:
	_sim_adjust = head_yaw - _commanded_yaw
	_look_yaw = head_yaw
