extends RefCounted

const PlayerCommand = preload("res://core/player_command.gd")
const WorldState = preload("res://core/world_state.gd")
const Intent = preload("res://core/intent.gd")
const BallControl = preload("res://core/ball_control.gd")

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
var _shot_power_min: float

var charge := 0.0
var cam_yaw := 0.0
var cam_pitch := 0.0
var aim := 0.0

var _t: Dictionary


func _init(t: Dictionary) -> void:
	_yaw_limit = deg_to_rad(t.player.head_yaw_limit_deg)
	_pitch_limit = deg_to_rad(t.player.head_pitch_limit_deg)
	_smoothing = t.camera.look_smoothing_s
	_charge_per_tick = 1.0 / (t.kick.charge_time * t.sim.tick_rate)
	_shot_power_min = t.kick.shot_power_min
	_t = t
	cam_pitch = deg_to_rad(t.camera.chase.pitch_deg)


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
	if input.shoot_released:
		cmd.action = PlayerCommand.Action.SHOOT
		cmd.power = lerpf(_shot_power_min, 1.0, charge)
	elif input.pass_released or input.lob_released:
		cmd.action = PlayerCommand.Action.PASS
		cmd.power = charge
		cmd.lofted = input.lob_released
	elif input.get("tackle", false):
		cmd.action = PlayerCommand.Action.TACKLE
	elif input.trap:
		cmd.action = PlayerCommand.Action.TRAP
	charge = minf(charge + _charge_per_tick, 1.0) if input.pass_held or input.lob_held or input.shoot_held else 0.0
	_commanded_yaw = _look_yaw
	return cmd


func take_over(head_yaw: float, head_pitch: float) -> void:
	_look_yaw = head_yaw
	_look_pitch = head_pitch
	_commanded_yaw = head_yaw
	_sim_adjust = 0.0
	view_yaw = head_yaw
	view_pitch = head_pitch
	charge = 0.0


func sync(head_yaw: float) -> void:
	_sim_adjust = head_yaw - _commanded_yaw
	_look_yaw = head_yaw


func orbit(look_delta: Vector2) -> void:
	var c: Dictionary = _t.camera.chase
	cam_yaw = wrapf(cam_yaw + look_delta.x, -PI, PI)
	cam_pitch = clampf(cam_pitch + look_delta.y, deg_to_rad(c.pitch_min_deg), deg_to_rad(c.pitch_max_deg))


func assist(cmd: PlayerCommand, state: WorldState) -> void:
	var player := state.player_by_id(cmd.player_id)
	var push := cmd.move.limit_length(1.0)
	var dir := Vector2.from_angle(cam_yaw) * push.y + Vector2.from_angle(cam_yaw + PI * 0.5) * push.x
	var moving: bool = dir.length() > _t.assist.stick_deadzone
	var intent := Intent.new()
	intent.desired_facing = player.body_yaw
	if moving:
		intent.desired_velocity = dir * (_t.player.sprint_speed if cmd.sprint else _t.player.jog_speed)
	var run := intent.to_command(cmd.tick, player, _t)
	cmd.move = run.move
	cmd.sprint = run.sprint
	cmd.align = false
	aim = dir.angle() if moving else player.body_yaw

	var kick := aim
	if cmd.action == PlayerCommand.Action.PASS:
		cmd.target_id = receiver(state, player.id, cmd.power)
		if cmd.target_id != -1:
			var mate := state.player_by_id(cmd.target_id)
			var speed: float = lerpf(_t.kick.pass_speed_min, _t.kick.pass_speed_max, cmd.power)
			kick = (mate.pos + mate.vel * player.pos.distance_to(mate.pos) / speed - _ball(state)).angle()
	elif cmd.action == PlayerCommand.Action.SHOOT:
		kick = shot_aim(state, player)
	else:
		var offset := _ball(state) - player.pos
		kick = offset.angle()
		cmd.look_pitch = -atan2(_t.player.eye_height - state.ball.pos.y, offset.length())
		cmd.look_yaw = clampf(angle_difference(player.body_yaw, kick), -_yaw_limit, _yaw_limit)
		return
	cmd.move.x = 0.0
	cmd.look_pitch = 0.0
	cmd.look_yaw = clampf(angle_difference(player.body_yaw, kick), -_yaw_limit, _yaw_limit)


func receiver(state: WorldState, player_id: int, power: float) -> int:
	var speed: float = lerpf(_t.kick.pass_speed_min, _t.kick.pass_speed_max, power)
	return BallControl.intended_receiver(state, player_id, Vector2.from_angle(aim), speed, _t)


func shot_aim(state: WorldState, player: WorldState.PlayerState) -> float:
	var goal_x: float = state.pitch.length * (0.5 if player.team == 0 else -0.5)
	var from := _ball(state)
	if absf(angle_difference(aim, (Vector2(goal_x, 0.0) - from).angle())) > deg_to_rad(_t.assist.shot_cone_deg):
		return aim
	var side: float = state.pitch.goal_width * 0.5 - _t.assist.post_margin
	for other in state.players:
		if other.team != player.team and other.role == "gk" and other.pos.y > 0.0:
			side = -side
	return (Vector2(goal_x, side) - from).angle()


func _ball(state: WorldState) -> Vector2:
	return Vector2(state.ball.pos.x, state.ball.pos.z)
