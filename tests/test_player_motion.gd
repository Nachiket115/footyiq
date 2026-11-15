extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const PlayerMotion = preload("res://core/player_motion.gd")

const DT := 1.0 / 60.0

var p: Dictionary = Config.load_all("res://config")["tuning"].player
var yaw_limit := deg_to_rad(p.head_yaw_limit_deg)


func _cmd(move: Vector2, sprint := false, look_yaw := 0.0, look_pitch := 0.0) -> PlayerCommand:
	var cmd := PlayerCommand.new()
	cmd.move = move
	cmd.sprint = sprint
	cmd.look_yaw = look_yaw
	cmd.look_pitch = look_pitch
	return cmd


func _run(player: WorldState.PlayerState, cmd: PlayerCommand, seconds: float, params := p) -> void:
	for i in roundi(seconds / DT):
		PlayerMotion.apply(player, cmd, DT, params)


func test_reaches_jog_speed_not_above() -> void:
	var player := WorldState.PlayerState.new()
	var top := 0.0
	for i in 180:
		PlayerMotion.apply(player, _cmd(Vector2(0, 1)), DT, p)
		top = maxf(top, player.vel.length())
	check_near(player.vel.length(), p.jog_speed, 0.01, "steady speed")
	check(top <= p.jog_speed + 0.001, "never above jog: %s" % top)
	check(player.pos.x > 8.0, "moved along body facing")
	check_near(player.pos.y, 0.0, 1e-4, "no sideways drift")


func test_sprint_caps_at_sprint_speed() -> void:
	var player := WorldState.PlayerState.new()
	_run(player, _cmd(Vector2(0, 1), true), 3.0)
	check_near(player.vel.length(), p.sprint_speed, 0.01, "sprint speed")
	check(player.sprinting, "sprinting flag")


func test_sprinting_90_degree_turn_takes_about_0_75s() -> void:
	var player := WorldState.PlayerState.new()
	_run(player, _cmd(Vector2(0, 1), true), 3.0)
	var ticks := 0
	while player.body_yaw < PI * 0.5 and ticks < 600:
		PlayerMotion.apply(player, _cmd(Vector2(1, 1), true), DT, p)
		ticks += 1
	check_near(ticks * DT, 0.75, 0.05, "time for a 90 degree turn at sprint")


func test_jog_turn_rate_is_240() -> void:
	var player := WorldState.PlayerState.new()
	_run(player, _cmd(Vector2(0, 1)), 2.0)
	_run(player, _cmd(Vector2(1, 1)), 0.25)
	check_near(rad_to_deg(player.body_yaw), 60.0, 2.0, "yaw after 0.25 s")


func test_pivot_on_the_spot() -> void:
	var player := WorldState.PlayerState.new()
	_run(player, _cmd(Vector2(-1, 0)), 0.25)
	check_near(rad_to_deg(player.body_yaw), -60.0, 2.0, "yaw after 0.25 s")
	check_near(player.pos.length(), 0.0, 1e-4, "did not travel")


func test_backpedal_is_half_jog_and_does_not_turn() -> void:
	var player := WorldState.PlayerState.new()
	_run(player, _cmd(Vector2(1, -1)), 2.0)
	check_near(player.vel.x, -p.jog_speed * p.backpedal_factor, 0.01, "backwards speed")
	check_near(player.body_yaw, 0.0, 1e-6, "no turn")
	check(not player.sprinting, "cannot sprint backwards")


func test_head_turn_inside_limit_does_not_move_body() -> void:
	var player := WorldState.PlayerState.new()
	_run(player, _cmd(Vector2(0, 1), false, 1.0, 0.3), 1.0)
	check_near(player.head_yaw, 1.0, 1e-6, "head yaw")
	check_near(player.head_pitch, 0.3, 1e-6, "head pitch")
	check_near(player.body_yaw, 0.0, 1e-6, "body yaw")


func test_scanning_while_running_does_not_drift() -> void:
	var player := WorldState.PlayerState.new()
	for i in 180:
		var look := sin(i * 0.1) * PI * 0.5
		PlayerMotion.apply(player, _cmd(Vector2(0, 1), true, look), DT, p)
	check_near(player.pos.y, 0.0, 1e-4, "no sideways drift")
	check_near(player.body_yaw, 0.0, 1e-6, "body did not turn")


func test_look_past_limit_drags_body() -> void:
	var player := WorldState.PlayerState.new()
	PlayerMotion.apply(player, _cmd(Vector2.ZERO, false, yaw_limit + 0.5), DT, p)
	var max_turn := deg_to_rad(p.turn_rate_jog_deg) * DT
	check_near(player.body_yaw, max_turn, 1e-6, "body dragged at the turn rate")
	check_near(player.head_yaw, yaw_limit, 1e-6, "head stays at the limit")


func test_head_clamped_to_limits() -> void:
	var player := WorldState.PlayerState.new()
	PlayerMotion.apply(player, _cmd(Vector2.ZERO, false, -9.0, 9.0), DT, p)
	check_near(player.head_yaw, -yaw_limit, 1e-6, "yaw limit")
	check_near(player.head_pitch, deg_to_rad(p.head_pitch_limit_deg), 1e-6, "pitch limit")
	check_near(rad_to_deg(yaw_limit), 110.0, 1e-4, "yaw limit is 110 degrees")
	check_near(p.head_pitch_limit_deg, 70.0, 1e-4, "pitch limit is 70 degrees")


func test_strafe_mode_sidesteps_without_turning() -> void:
	var strafe: Dictionary = p.duplicate(true)
	strafe.lateral_mode = "strafe"
	var player := WorldState.PlayerState.new()
	_run(player, _cmd(Vector2(1, 0)), 2.0, strafe)
	check_near(player.vel.y, p.jog_speed * p.strafe_factor, 0.01, "sidestep speed")
	check_near(player.vel.x, 0.0, 0.01, "no forward speed")
	check_near(player.body_yaw, 0.0, 1e-6, "no turn")


func test_zero_move_decelerates_without_nan() -> void:
	var player := WorldState.PlayerState.new()
	_run(player, _cmd(Vector2(0, 1), true), 2.0)
	_run(player, _cmd(Vector2.ZERO), 2.0)
	check_eq(player.vel, Vector2.ZERO, "stopped")
	check(player.pos.is_finite(), "finite")


func test_separate_leaves_centres_two_radii_apart() -> void:
	var a := WorldState.PlayerState.new()
	var b := WorldState.PlayerState.new()
	b.pos = Vector2(0.2, 0.0)
	var c := WorldState.PlayerState.new()
	c.pos = Vector2(5.0, 5.0)
	PlayerMotion.separate([a, b, c], p.radius)
	check_near(a.pos.distance_to(b.pos), p.radius * 2.0, 1e-4, "pushed apart")
	check_eq(c.pos, Vector2(5.0, 5.0), "distant player untouched")


func test_separate_coincident_players_stays_finite() -> void:
	var a := WorldState.PlayerState.new()
	var b := WorldState.PlayerState.new()
	PlayerMotion.separate([a, b], p.radius)
	check(a.pos.is_finite() and b.pos.is_finite(), "finite")
	check_near(a.pos.distance_to(b.pos), p.radius * 2.0, 1e-4, "pushed apart")
