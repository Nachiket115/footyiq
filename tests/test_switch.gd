extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const Sim = preload("res://core/sim.gd")
const BallControl = preload("res://core/ball_control.gd")

var cfg := Config.load_all("res://config")
var t: Dictionary = cfg["tuning"]


func _state() -> WorldState:
	var state := WorldState.new()
	state.pitch = {"length": 200.0, "width": 200.0, "goal_width": 0.0, "boards": true}
	var spots := [[0, Vector2.ZERO], [0, Vector2(10.0, 1.0)], [0, Vector2(4.0, -3.0)], [1, Vector2(30.0, 0.0)]]
	for i in spots.size():
		var player := WorldState.PlayerState.new()
		player.id = i
		player.team = spots[i][0]
		player.pos = spots[i][1]
		state.players.append(player)
	state.ball.pos = Vector3(0.6, t.ball.radius, 0.0)
	state.ball.owner_id = 0
	state.ball.last_touch_id = 0
	Sim.seed_rng(state, 1)
	return state


func _pass(state: WorldState) -> void:
	var cmd := PlayerCommand.new()
	cmd.player_id = 0
	cmd.action = PlayerCommand.Action.PASS
	cmd.power = 0.5
	cmd.look_yaw = state.players[0].head_yaw
	Sim.step(state, [cmd], cfg)


func _pass_event(state: WorldState) -> Dictionary:
	for event in state.events:
		if event.type == "pass":
			return event
	return {}


func test_receiver_is_closest_to_projected_path() -> void:
	var state := _state()
	check_eq(BallControl.intended_receiver(state, 0, Vector2.RIGHT, 15.0, t), 1, "1 m off the path beats 3 m off")
	state.players[2].pos = Vector2(8.0, -4.0)
	state.players[2].vel = Vector2(0.0, 7.0)
	check_eq(BallControl.intended_receiver(state, 0, Vector2.RIGHT, 15.0, t), 2, "a runner arriving on the path is picked")
	check_eq(BallControl.intended_receiver(state, 0, Vector2.ZERO, 15.0, t), -1, "no direction, no receiver")


func test_no_receiver_outside_tolerance_returns_minus_1() -> void:
	var state := _state()
	check_eq(BallControl.intended_receiver(state, 0, Vector2.UP, 15.0, t), -1, "nobody that way")
	state.players[1].pos = Vector2(10.0, t.pass.receiver_tolerance + 0.5)
	state.players[2].pos = Vector2(-20.0, 0.0)
	check_eq(BallControl.intended_receiver(state, 0, Vector2.RIGHT, 15.0, t), -1, "just outside the tolerance")
	state.players[1].pos = Vector2(150.0, 0.0)
	check_eq(BallControl.intended_receiver(state, 0, Vector2.RIGHT, 15.0, t), -1, "further than the ball will roll")


func test_no_switch_when_receiver_is_minus_1() -> void:
	var state := _state()
	state.players[0].body_yaw = -PI * 0.5
	_pass(state)
	check_eq(_pass_event(state).get("target_id"), -1, "pass is still logged, with no target")
	check_eq(BallControl.control_after(state, 0, true), 0, "control stays")


func test_pass_off_body_facing_has_larger_error() -> void:
	var player := WorldState.PlayerState.new()
	var errors := []
	for head_yaw: float in [0.0, 0.5, 1.5, deg_to_rad(t.player.head_yaw_limit_deg)]:
		player.head_yaw = head_yaw
		errors.append(absf(angle_difference(head_yaw, BallControl.aim_direction(player, t, 1.0).angle())))
		check_near(BallControl.aim_direction(player, t, 0.0).angle(), head_yaw, 1e-6, "no error on a centred roll")
	check_eq(errors[0], 0.0, "none along body facing")
	check(errors[1] < errors[2] and errors[2] < errors[3], "grows with the angle: %s" % [errors])
	check_near(errors[3], deg_to_rad(t.pass.max_offbody_error_deg), 1e-6, "capped at the limit")


func test_follow_ball_switches_on_release_tick() -> void:
	var state := _state()
	_pass(state)
	check_eq(_pass_event(state).get("target_id"), 1, "intended receiver")
	check_eq(state.ball.pass_target_id, 1, "ball remembers the target")
	check_eq(BallControl.control_after(state, 0, true), 1, "control moves on the tick of the kick")
	check_eq(BallControl.control_after(state, 2, true), 2, "someone else's pass does not move it")


func test_locked_position_never_switches() -> void:
	var state := _state()
	_pass(state)
	check_eq(BallControl.control_after(state, 0, false), 0, "control stays")


func test_interception_gives_control_to_nearest_teammate() -> void:
	var state := _state()
	state.players[3].pos = Vector2(5.0, 0.0)
	state.ball.pos = Vector3(4.5, t.ball.radius, 0.0)
	state.ball.vel = Vector3(2.0, 0.0, 0.0)
	state.ball.owner_id = -1
	state.ball.pass_from_id = 0
	state.ball.pass_target_id = 1
	Sim.step(state, [], cfg)
	check_eq(state.ball.owner_id, 3, "opponent took it")
	check_eq(BallControl.control_after(state, 1, true), 2, "nearest teammate to the ball")
	check_eq(BallControl.control_after(state, 1, false), 1, "not in locked position")
	check_eq(BallControl.control_after(state, 0, true), 2, "whoever was controlled, the nearest teammate takes over")
	check_eq(BallControl.control_after(state, 0, true, false), 0, "but not while a recent switch is settling")


func test_follow_ball_moves_to_a_teammate_who_gets_the_ball() -> void:
	var state := _state()
	state.ball.pos = Vector3(4.5, t.ball.radius, -3.0)
	state.ball.owner_id = -1
	Sim.step(state, [], cfg)
	check_eq(state.ball.owner_id, 2, "teammate picked it up")
	check_eq(BallControl.control_after(state, 0, true), 2, "control follows the ball")
	check_eq(BallControl.control_after(state, 0, false), 0, "not in locked position")


func test_losing_the_ball_skips_the_keeper() -> void:
	var state := _state()
	state.players[2].role = "gk"
	state.players[3].pos = Vector2(5.0, 0.0)
	state.ball.pos = Vector3(4.5, t.ball.radius, 0.0)
	state.ball.owner_id = -1
	Sim.step(state, [], cfg)
	check_eq(BallControl.control_after(state, 0, true), 0, "nearest outfield teammate, not the keeper")


func test_on_pass_mode_ignores_bots_passing_and_losing_the_ball() -> void:
	var state := _state()
	state.ball.pos = Vector3(4.5, t.ball.radius, -3.0)
	state.ball.owner_id = -1
	Sim.step(state, [], cfg)
	check_eq(state.ball.owner_id, 2, "teammate picked it up")
	check_eq(BallControl.control_after(state, 0, true, true, false), 0, "control stays when a teammate gets the ball")
	state = _state()
	_pass(state)
	check_eq(BallControl.control_after(state, 0, true, true, false), 1, "my own pass still moves control")


func test_switch_key_takes_the_other_teammate_nearest_the_ball() -> void:
	var state := _state()
	state.ball.pos = Vector3(4.5, t.ball.radius, -3.0)
	state.ball.owner_id = -1
	check_eq(BallControl.switch_target(state, 0), 2, "nearest to the ball")
	check(BallControl.switch_target(state, 2) != 2, "already nearest: takes the next one, never itself")
	state.players[2].role = "gk"
	check(BallControl.switch_target(state, 0) != 2, "never the keeper")
