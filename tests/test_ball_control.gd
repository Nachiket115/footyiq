extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const Sim = preload("res://core/sim.gd")
const BallControl = preload("res://core/ball_control.gd")

const DT := 1.0 / 60.0
const EYES_DOWN := -0.7

var cfg := Config.load_all("res://config")
var t: Dictionary = cfg["tuning"]


func _state(spots: Array, ball_xz := Vector2(0.6, 0.0)) -> WorldState:
	var state := WorldState.new()
	state.pitch = {"length": 200.0, "width": 200.0, "goal_width": 0.0, "boards": true}
	for i in spots.size():
		var player := WorldState.PlayerState.new()
		player.id = i
		player.team = i % 2
		player.pos = spots[i]
		state.players.append(player)
	state.ball.pos = Vector3(ball_xz.x, t.ball.radius, ball_xz.y)
	Sim.seed_rng(state, 1)
	return state


func _cmd(id: int, action := PlayerCommand.Action.NONE, power := 0.0) -> PlayerCommand:
	var cmd := PlayerCommand.new()
	cmd.player_id = id
	cmd.action = action
	cmd.power = power
	cmd.look_pitch = EYES_DOWN
	return cmd


func _update(state: WorldState, commands: Array = [], tuning: Dictionary = t) -> void:
	var by_player := {}
	for cmd: PlayerCommand in commands:
		by_player[cmd.player_id] = cmd
	var rng := RandomNumberGenerator.new()
	rng.state = int(state.rng_state)
	BallControl.update(state, by_player, DT, tuning, rng)


func _run(state: WorldState, seconds: float, cmd: PlayerCommand) -> Array:
	var seen := []
	for i in int(seconds * 60.0):
		Sim.step(state, [cmd] if cmd != null else [], cfg)
		for event in state.events:
			seen.append(event.type)
	return seen


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func test_slow_ball_inside_radius_gives_possession() -> void:
	var state := _state([Vector2.ZERO])
	_update(state)
	check_eq(state.ball.owner_id, 0, "owner")
	check_eq(state.events[0].type, "receive", "receive event")


func test_ball_outside_radius_gives_nothing() -> void:
	var state := _state([Vector2.ZERO], Vector2(t.control.radius + 0.1, 0.0))
	_update(state)
	check_eq(state.ball.owner_id, -1, "owner")


func test_fast_ball_inside_radius_does_not() -> void:
	var state := _state([Vector2.ZERO])
	state.ball.vel = Vector3(-(t.control.max_ball_speed + 1.0), 0.0, 0.0)
	_update(state)
	check_eq(state.ball.owner_id, -1, "owner")


func test_trap_controls_a_faster_ball_and_stops_it() -> void:
	var state := _state([Vector2.ZERO])
	state.ball.vel = Vector3(-(t.control.max_ball_speed + 1.0), 0.0, 0.0)
	_update(state, [_cmd(0, PlayerCommand.Action.TRAP)])
	check_eq(state.ball.owner_id, 0, "owner")
	check_eq(state.ball.vel, Vector3.ZERO, "ball stopped")


func test_ball_too_high_is_not_controlled() -> void:
	var state := _state([Vector2.ZERO])
	state.ball.pos.y = t.control.max_height + 0.2
	_update(state)
	check_eq(state.ball.owner_id, -1, "owner")


func test_dribble_touch_pushes_ball_ahead_of_carrier() -> void:
	var state := _state([Vector2.ZERO])
	var cmd := _cmd(0)
	cmd.move = Vector2(0.0, 1.0)
	var seen := _run(state, 4.0, cmd)
	var player := state.players[0]
	var lead := (_flat(state.ball.pos) - player.pos).dot(Vector2.from_angle(player.body_yaw))
	check_eq(state.ball.owner_id, 0, "still owner")
	check(player.pos.x > 10.0, "carrier travelled")
	check(lead > t.player.radius and lead < t.control.radius, "ball ahead and close, lead %s" % lead)
	check(seen.count("touch") >= 3, "several touches, got %s" % seen.count("touch"))
	check(seen.count("touch") < 40, "not a touch every tick, got %s" % seen.count("touch"))


func test_sprinting_through_a_full_turn_keeps_the_ball() -> void:
	var state := _state([Vector2.ZERO])
	var cmd := _cmd(0)
	cmd.move = Vector2(0.0, 1.0)
	cmd.sprint = true
	_run(state, 2.0, cmd)
	check_near(state.players[0].vel.length(), t.player.sprint_speed, 0.1, "at sprint speed")
	cmd.move = Vector2(1.0, 1.0)
	_run(state, 4.0, cmd)
	check_eq(state.ball.owner_id, 0, "still owner")


func test_backpedal_and_standing_turn_keep_the_ball() -> void:
	var state := _state([Vector2.ZERO])
	var cmd := _cmd(0)
	_run(state, 0.1, cmd)
	cmd.move = Vector2(0.0, -1.0)
	_run(state, 3.0, cmd)
	check_eq(state.ball.owner_id, 0, "owner after backpedal")
	cmd.move = Vector2(1.0, 0.0)
	_run(state, 3.0, cmd)
	check_eq(state.ball.owner_id, 0, "owner after standing turn")
	var player := state.players[0]
	_run(state, 1.0, _cmd(0))
	var lead := (_flat(state.ball.pos) - player.pos).dot(Vector2.from_angle(player.body_yaw))
	check(lead > t.player.radius, "ball settles in front, lead %s" % lead)


func test_pass_speed_scales_with_power() -> void:
	for sample in [[0.0, t.kick.pass_speed_min], [1.0, t.kick.pass_speed_max]]:
		var state := _state([Vector2.ZERO])
		_update(state, [_cmd(0, PlayerCommand.Action.PASS, sample[0])])
		check_near(state.ball.vel.length(), sample[1], 1e-4, "speed at power %s" % sample[0])


func test_pass_goes_where_the_head_looks() -> void:
	var state := _state([Vector2.ZERO])
	state.players[0].head_yaw = 0.5
	_update(state, [_cmd(0, PlayerCommand.Action.PASS, 0.5)])
	var spread := deg_to_rad(t.pass.max_offbody_error_deg) * 0.5 / deg_to_rad(t.player.head_yaw_limit_deg)
	check_near(_flat(state.ball.vel).angle(), 0.5, spread + 1e-4, "direction, within the off-body error")


func test_lofted_pass_has_upward_velocity() -> void:
	var state := _state([Vector2.ZERO])
	var cmd := _cmd(0, PlayerCommand.Action.PASS, 0.5)
	cmd.lofted = true
	_update(state, [cmd])
	check(state.ball.vel.y > 1.0, "upward velocity %s" % state.ball.vel.y)


func test_pass_emits_event_and_clears_owner() -> void:
	var state := _state([Vector2.ZERO])
	_update(state)
	var cmd := _cmd(0, PlayerCommand.Action.PASS, 0.5)
	cmd.target_id = 3
	_update(state, [cmd])
	var event: Dictionary = state.events[-1]
	check_eq(state.ball.owner_id, -1, "owner cleared")
	check_eq(event.type, "pass", "event type")
	check_eq(event.player_id, 0, "event player")
	check_eq(state.ball.pass_from_id, 0, "pass from")
	check_eq(state.ball.pass_target_id, 3, "pass target")
	check_eq(state.ball.last_touch_id, 0, "last touch")


func test_passer_does_not_take_back_own_pass() -> void:
	var state := _state([Vector2.ZERO])
	Sim.step(state, [], cfg)
	Sim.step(state, [_cmd(0, PlayerCommand.Action.PASS, 0.0)], cfg)
	_run(state, 0.5, null)
	check_eq(state.ball.owner_id, -1, "ball is free")
	check(state.ball.pos.x > 2.0, "ball left the passer")


func test_cannot_kick_a_ball_an_opponent_owns() -> void:
	var state := _state([Vector2.ZERO, Vector2(1.2, 0.0)])
	_update(state)
	check_eq(state.ball.owner_id, 0, "owner")
	_update(state, [_cmd(1, PlayerCommand.Action.SHOOT, 1.0)])
	check_eq(state.ball.owner_id, 0, "still owner")


func test_receive_names_the_passer_and_interception_is_a_turnover() -> void:
	for receiver_team in [0, 1]:
		var state := _state([Vector2.ZERO, Vector2(8.0, 0.0)])
		state.players[1].team = receiver_team
		state.players[1].body_yaw = PI
		Sim.step(state, [], cfg)
		Sim.step(state, [_cmd(0, PlayerCommand.Action.PASS, 0.2)], cfg)
		var received := {}
		var turnovers := 0
		for i in 180:
			Sim.step(state, [], cfg)
			for event in state.events:
				if event.type == "receive":
					received = event
				turnovers += int(event.type == "turnover")
		check_eq(state.ball.owner_id, 1, "receiver owns the ball")
		check_eq(received.get("from_id"), 0, "receive names the passer")
		check_eq(turnovers, receiver_team, "turnover only for the other team")
		check_eq(state.ball.pass_from_id, -1, "pass is over")


func test_tackle_wins_the_ball_only_from_an_opponent() -> void:
	var always: Dictionary = t.duplicate(true)
	always.tackle.chance_per_s = 60.0
	var never: Dictionary = t.duplicate(true)
	never.tackle.chance_per_s = 0.0
	for sample in [[always, 1, 1], [never, 1, 0], [always, 0, 0]]:
		var state := _state([Vector2.ZERO, Vector2(1.3, 0.0)])
		state.players[1].team = sample[1]
		state.players[1].body_yaw = PI
		_update(state, [], sample[0])
		_update(state, [_cmd(1, PlayerCommand.Action.TACKLE)], sample[0])
		check_eq(state.ball.owner_id, sample[2], "owner after tackle")
		if sample[2] == 1:
			var turnovers := state.events.filter(func(e: Dictionary) -> bool: return e.type == "turnover")
			check_eq(turnovers.size(), 1, "one turnover event")
			check_eq(turnovers[0].get("from_id"), 0, "turnover names the loser")


func test_ball_on_player_centre_stays_finite() -> void:
	var state := _state([Vector2.ZERO], Vector2.ZERO)
	_run(state, 0.5, null)
	check(is_finite(state.ball.pos.x) and is_finite(state.ball.vel.x), "finite")


func _carrier(pitch: float, head_yaw := 0.0) -> WorldState:
	var state := _state([Vector2.ZERO])
	state.ball.owner_id = 0
	state.players[0].head_pitch = pitch
	state.players[0].head_yaw = head_yaw
	return state


func _watch(state: WorldState, seconds: float) -> float:
	for i in roundi(seconds * 60.0):
		BallControl.update_gaze_penalty(state.players[0], state.ball, DT, t)
	return state.players[0].control_penalty


func test_no_penalty_while_looking_at_the_ball() -> void:
	check_eq(_watch(_carrier(EYES_DOWN), 5.0), 0.0, "penalty")


func test_no_penalty_inside_grace() -> void:
	check_eq(_watch(_carrier(0.0), t.gaze.grace_s - 0.05), 0.0, "penalty")


func test_penalty_rises_after_0_6s_looking_away() -> void:
	check(_watch(_carrier(0.0), t.gaze.grace_s + 0.5) > 0.0, "level gaze over a ball at the feet")
	for sample in [[0.0, false], [100.0, true]]:
		var state := _carrier(0.0, deg_to_rad(sample[0]))
		state.ball.pos = Vector3(5.0, t.ball.radius, 0.0)
		check_eq(_watch(state, t.gaze.grace_s + 0.5) > 0.0, sample[1], "ball 5 m ahead, head turned %s degrees" % sample[0])


func test_penalty_rises_when_pitch_above_25() -> void:
	var state := _carrier(deg_to_rad(t.gaze.pitch_threshold_deg + 5.0))
	state.ball.pos = Vector3(3.0, 3.0, 0.0)
	check_eq(state.players[0].look_away_time, 0.0, "ball is inside the view angle")
	check(_watch(state, t.gaze.grace_s + 0.5) > 0.0, "penalty")
	check_eq(state.players[0].look_away_time, 0.0, "only the pitch rule fired")


func test_penalty_only_rises_for_the_carrier() -> void:
	var state := _carrier(0.0)
	state.ball.owner_id = -1
	check_eq(_watch(state, 3.0), 0.0, "penalty")
	check(state.players[0].look_away_time > 2.9, "look-away time is still tracked")


func test_sprint_raises_penalty_faster() -> void:
	var jogging := _carrier(0.0)
	var sprinting := _carrier(0.0)
	sprinting.players[0].sprinting = true
	var slow := _watch(jogging, t.gaze.grace_s + 0.5)
	var fast := _watch(sprinting, t.gaze.grace_s + 0.5)
	check_near(fast, slow * t.gaze.sprint_multiplier, 1e-4, "sprint multiplier")


func test_penalty_decays_when_looking_back() -> void:
	var state := _carrier(0.0)
	state.players[0].sprinting = true
	var before := _watch(state, 3.0)
	state.players[0].head_pitch = EYES_DOWN
	var after := _watch(state, 0.5)
	check(before > 0.5, "penalty built up, got %s" % before)
	check_eq(after, 0.0, "gone half a second after looking back")


func _sprint_cmd(pitch: float) -> PlayerCommand:
	var cmd := _cmd(0)
	cmd.move = Vector2(0.0, 1.0)
	cmd.sprint = true
	cmd.look_pitch = pitch
	return cmd


func _time_to_lose(rng_seed: int, cmd: PlayerCommand, limit_s: float) -> float:
	var state := _state([Vector2.ZERO])
	Sim.seed_rng(state, rng_seed)
	Sim.step(state, [_cmd(0)], cfg)
	for i in int(limit_s * 60.0):
		Sim.step(state, [cmd], cfg)
		if state.ball.owner_id != 0:
			return (i + 1) / 60.0
	return INF


func test_staring_upfield_sprinting_loses_ball_within_3s() -> void:
	var times := []
	for rng_seed in 100:
		times.append(_time_to_lose(rng_seed, _sprint_cmd(0.0), 3.0))
	times.sort()
	var lost := times.filter(func(x: float) -> bool: return x != INF).size()
	check(lost >= 90, "lost in %s of 100 runs" % lost)
	check_near(times[50], 2.0, 0.4, "median time to lose the ball")
	check(times[0] > t.gaze.grace_s, "never inside the grace period, earliest %s" % times[0])


func test_eyes_on_ball_keeps_it_10s() -> void:
	var kept := 0
	for rng_seed in 100:
		kept += int(_time_to_lose(rng_seed, _sprint_cmd(EYES_DOWN), 10.0) == INF)
	check(kept >= 95, "kept in %s of 100 runs" % kept)


func test_short_scan_while_jogging_keeps_the_ball() -> void:
	var kept := 0
	for rng_seed in 100:
		var state := _state([Vector2.ZERO])
		Sim.seed_rng(state, rng_seed)
		var cmd := _cmd(0)
		cmd.move = Vector2(0.0, 1.0)
		for cycle in 4:
			cmd.look_pitch = 0.0
			_run(state, 1.5, cmd)
			cmd.look_pitch = EYES_DOWN
			_run(state, 1.0, cmd)
		kept += int(state.ball.owner_id == 0)
	check(kept >= 95, "kept in %s of 100 runs" % kept)


func test_looking_back_recovers_control() -> void:
	var recovered := 0
	for rng_seed in 20:
		var state := _state([Vector2.ZERO])
		Sim.seed_rng(state, rng_seed)
		Sim.step(state, [_cmd(0)], cfg)
		_run(state, 4.0, _sprint_cmd(0.0))
		var player := state.players[0]
		var cmd := _cmd(0)
		for i in 600:
			if state.ball.owner_id == 0:
				break
			var bearing := (_flat(state.ball.pos) - player.pos).angle()
			cmd.move = Vector2(clampf(angle_difference(player.body_yaw, bearing) * 4.0, -1.0, 1.0), 1.0)
			Sim.step(state, [cmd], cfg)
		_run(state, 5.0, _sprint_cmd(EYES_DOWN))
		recovered += int(state.ball.owner_id == 0)
	check(recovered >= 19, "recovered and kept in %s of 20 runs" % recovered)


func test_first_touch_worse_for_faster_ball() -> void:
	var slow: float = BallControl.first_touch_quality(3.0, 0.0, true, t)
	var fast: float = BallControl.first_touch_quality(11.0, 0.0, true, t)
	check(fast < slow, "fast %s, slow %s" % [fast, slow])
	check_eq(BallControl.first_touch_quality(0.0, PI, false, t), 1.0, "a still ball is always clean")
	check(BallControl.first_touch_quality(99.0, PI, false, t) >= 0.0, "never below zero")


func test_first_touch_worse_when_facing_away() -> void:
	var facing: float = BallControl.first_touch_quality(8.0, 0.0, true, t)
	var away: float = BallControl.first_touch_quality(8.0, PI, true, t)
	var unready: float = BallControl.first_touch_quality(8.0, 0.0, false, t)
	check(away < facing, "back to the pass: %s vs %s" % [away, facing])
	check(unready < facing, "not looking: %s vs %s" % [unready, facing])


func test_touch_outcome_labels() -> void:
	check_eq(BallControl.touch_outcome(1.0, t), "clean", "top")
	check_eq(BallControl.touch_outcome(t.first_touch.clean_min - 0.01, t), "loose", "middle")
	check_eq(BallControl.touch_outcome(t.first_touch.loose_min - 0.01, t), "lost", "bottom")


func test_receive_event_reports_first_touch() -> void:
	var state := _state([Vector2.ZERO])
	state.players[0].head_pitch = EYES_DOWN
	state.ball.vel = Vector3(-6.0, 0.0, 0.0)
	_update(state)
	check_eq(state.events[0].type, "receive", "event")
	check_eq(state.events[0].get("outcome"), "clean", "outcome")
	check(state.events[0].get("quality", 0.0) > t.first_touch.clean_min, "quality")
