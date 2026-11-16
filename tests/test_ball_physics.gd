extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const BallPhysics = preload("res://core/ball_physics.gd")

const DT := 1.0 / 60.0
const OPEN := {"length": 1000.0, "width": 1000.0, "goal_width": 0.0, "boards": false}
const PITCH := {"length": 40.0, "width": 25.0, "goal_width": 3.0, "boards": false}

var t: Dictionary = Config.load_all("res://config")["tuning"]
var r: float = t.ball.radius


func _ball(pos: Vector3, vel := Vector3.ZERO) -> WorldState.BallState:
	var ball := WorldState.BallState.new()
	ball.pos = pos
	ball.vel = vel
	return ball


func _player_at(pos: Vector2) -> WorldState.PlayerState:
	var player := WorldState.PlayerState.new()
	player.pos = pos
	return player


func _run(ball: WorldState.BallState, seconds: float, pitch := OPEN, players := []) -> Array:
	for i in int(seconds / DT):
		var events := BallPhysics.integrate(ball, players, DT, pitch, t)
		if not events.is_empty():
			return events
	return []


func _finite(ball: WorldState.BallState) -> bool:
	return ball.pos.is_finite() and ball.vel.is_finite()


func test_bounce_height_ratio_matches_restitution_squared() -> void:
	var ball := _ball(Vector3(0.0, r + 1.0, 0.0))
	var bounced := false
	var apex := 0.0
	for i in 180:
		BallPhysics.integrate(ball, [], DT, OPEN, t)
		if ball.vel.y > 0.0:
			bounced = true
		if bounced:
			apex = maxf(apex, ball.pos.y)
	var e: float = t.ball.restitution
	check(bounced, "ball bounced")
	check_near(apex - r, e * e, 0.03, "first apex")


func test_rolling_ball_decays_and_stops() -> void:
	var ball := _ball(Vector3(0.0, r, 0.0), Vector3(10.0, 0.0, 0.0))
	var last_speed := ball.vel.length()
	var monotonic := true
	for i in int(30.0 / DT):
		BallPhysics.integrate(ball, [], DT, OPEN, t)
		if ball.vel.length() > last_speed:
			monotonic = false
		last_speed = ball.vel.length()
	check(monotonic, "speed never increases")
	check_eq(ball.vel, Vector3.ZERO, "stopped")
	check(ball.pos.x > 5.0, "rolled a useful distance: %s" % ball.pos.x)
	check_near(ball.pos.y, r, 1e-5, "stays on the ground")


func test_drag_terminal_velocity() -> void:
	var ball := _ball(Vector3(0.0, 100000.0, 0.0))
	_run(ball, 20.0)
	var expected := sqrt(t.ball.mass * t.sim.gravity / t.ball.air_drag)
	check_near(-ball.vel.y, expected, expected * 0.02, "terminal velocity")


func test_ball_rests_at_radius_height() -> void:
	var ball := _ball(Vector3(1.0, r + 0.5, 2.0))
	_run(ball, 10.0)
	check_near(ball.pos.y, r, 1e-5, "height")
	check_eq(ball.vel, Vector3.ZERO, "velocity")


func test_zero_velocity_stays_finite() -> void:
	var ball := _ball(Vector3(0.0, r, 0.0))
	_run(ball, 1.0)
	check(_finite(ball), "finite")
	check_eq(ball.pos, Vector3(0.0, r, 0.0), "did not move")


func test_ball_on_player_axis_stays_finite() -> void:
	var ball := _ball(Vector3(0.0, 0.5, 0.0))
	_run(ball, 0.2, OPEN, [_player_at(Vector2.ZERO)])
	check(_finite(ball), "finite")


func test_fast_shot_does_not_tunnel_through_post() -> void:
	var ball := _ball(Vector3(17.0, r, 1.5), Vector3(40.0, 0.0, 0.0))
	var events := _run(ball, 0.5, PITCH)
	check(events.is_empty(), "no goal or out: %s" % [events])
	check(ball.vel.x < 0.0, "came back off the post")
	check(ball.pos.x < 20.0, "stayed in front of the post")


func test_fast_shot_does_not_tunnel_through_player() -> void:
	var ball := _ball(Vector3(-3.0, 0.5, 0.0), Vector3(40.0, 0.0, 0.0))
	_run(ball, 0.3, OPEN, [_player_at(Vector2.ZERO)])
	check(ball.pos.x < 0.0, "stayed on the near side: %s" % ball.pos.x)


func test_ball_passes_over_player_head() -> void:
	var ball := _ball(Vector3(-3.0, 3.0, 0.0), Vector3(40.0, 0.0, 0.0))
	_run(ball, 0.3, OPEN, [_player_at(Vector2.ZERO)])
	check(ball.pos.x > 3.0, "went over: %s" % ball.pos.x)


func test_crossbar_rebounds() -> void:
	var ball := _ball(Vector3(18.0, t.goal.height, 0.0), Vector3(20.0, 0.0, 0.0))
	var events := _run(ball, 0.3, PITCH)
	check(events.is_empty(), "no goal or out: %s" % [events])
	check(ball.vel.x < 0.0, "came back off the bar")


func test_boards_rebound_when_enabled() -> void:
	var pitch := PITCH.merged({"boards": true}, true)
	var ball := _ball(Vector3(0.0, r, 10.0), Vector3(0.0, 0.0, 15.0))
	var events := _run(ball, 1.0, pitch)
	check(events.is_empty(), "no out event: %s" % [events])
	check(ball.vel.z < 0.0, "rebounded")
	check(absf(ball.pos.z) <= 12.5, "inside the boards")


func test_out_event_when_boards_disabled() -> void:
	var ball := _ball(Vector3(0.0, r, 10.0), Vector3(0.0, 0.0, 15.0))
	var events := _run(ball, 1.0, PITCH)
	check_eq(events.size(), 1, "event count")
	check_eq(events[0].type, "out", "event type")
	check_near(events[0].pos.z, 12.5, 1e-5, "restart point on the line")


func test_goal_event_between_posts_under_bar() -> void:
	var events := _run(_ball(Vector3(19.0, r, 0.0), Vector3(10.0, 0.0, 0.0)), 1.0, PITCH)
	check_eq(events[0].type, "goal", "right goal type")
	check_eq(events[0].team, 0, "team 0 scores in the +x goal")
	events = _run(_ball(Vector3(-19.0, r, 0.0), Vector3(-10.0, 0.0, 0.0)), 1.0, PITCH)
	check_eq(events[0].type, "goal", "left goal type")
	check_eq(events[0].team, 1, "team 1 scores in the -x goal")


func test_over_the_bar_or_wide_is_out_not_goal() -> void:
	var events := _run(_ball(Vector3(19.0, 3.0, 0.0), Vector3(10.0, 0.0, 0.0)), 1.0, PITCH)
	check_eq(events[0].type, "out", "over the bar")
	events = _run(_ball(Vector3(19.0, r, 3.0), Vector3(10.0, 0.0, 0.0)), 1.0, PITCH)
	check_eq(events[0].type, "out", "wide of the post")


func test_keeper_parries_a_fast_shot_within_reach_but_not_a_slow_ball() -> void:
	var keeper := WorldState.PlayerState.new()
	keeper.role = "gk"
	keeper.pos = Vector2(5.0, 0.0)
	var pitch := {"length": 200.0, "width": 200.0, "goal_width": 0.0, "boards": true}
	for case: Array in [[25.0, true], [8.0, false]]:
		var ball := WorldState.BallState.new()
		ball.pos = Vector3(0.0, t.ball.radius, t.goal.keeper_reach - 0.2)
		ball.vel = Vector3(case[0], 0.0, 0.0)
		for i in 60:
			BallPhysics.integrate(ball, [keeper], 1.0 / 60.0, pitch, t)
		check_eq(ball.pos.z > t.goal.keeper_reach, case[1], "ball at %.0f m/s ends at z %.2f" % [case[0], ball.pos.z])


func test_keeper_dives_further_the_longer_a_shot_has_been_in_flight() -> void:
	var keeper := WorldState.PlayerState.new()
	keeper.role = "gk"
	keeper.pos = Vector2(1.0, 0.0)
	var pitch := {"length": 200.0, "width": 200.0, "goal_width": 0.0, "boards": true}
	var wide: float = t.goal.keeper_reach + t.ball.radius + 0.3
	for case: Array in [[0.0, false], [1.0, true]]:
		var ball := WorldState.BallState.new()
		ball.pos = Vector3(0.0, t.ball.radius, wide)
		ball.vel = Vector3(25.0, 0.0, 0.0)
		ball.flight = case[0]
		for i in 6:
			BallPhysics.integrate(ball, [keeper], 1.0 / 60.0, pitch, t)
		check_eq(ball.pos.z > wide + 0.05, case[1], "after %.1f s of flight the ball ends at z %.2f" % [case[0], ball.pos.z])
	check(t.goal.dive_reach < PITCH.goal_width * 0.5, "a full dive still leaves the corners")
