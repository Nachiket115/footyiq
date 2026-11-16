extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const Sim = preload("res://core/sim.gd")
const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const Intent = preload("res://core/intent.gd")
const Steering = preload("res://bots/steering.gd")
const Roles = preload("res://bots/roles.gd")
const BotController = preload("res://sim/bot_controller.gd")

var cfg := Config.load_all("res://config")
var t: Dictionary = cfg["tuning"]
var drill: Dictionary = cfg["drills"]["5v5"]


func test_seek_runs_at_full_speed_toward_target() -> void:
	check_eq(Steering.seek(Vector2.ZERO, Vector2(0.0, 5.0), 4.0), Vector2(0.0, 4.0), "velocity")
	check_eq(Steering.seek(Vector2.ONE, Vector2.ONE, 4.0), Vector2.ZERO, "on the target")


func test_arrive_slows_inside_radius() -> void:
	var far := Steering.arrive(Vector2.ZERO, Vector2(10.0, 0.0), 4.0, 3.0)
	var near := Steering.arrive(Vector2.ZERO, Vector2(1.5, 0.0), 4.0, 3.0)
	check_near(far.length(), 4.0, 1e-6, "full speed outside the radius")
	check_near(near.length(), 2.0, 1e-6, "half speed halfway in")
	check_eq(Steering.arrive(Vector2.ONE, Vector2.ONE, 4.0, 3.0), Vector2.ZERO, "stopped on the target")


func test_separation_pushes_apart() -> void:
	var push := Steering.separation(Vector2.ZERO, [Vector2(0.5, 0.0), Vector2(9.0, 0.0)], 1.5)
	check(push.x < 0.0 and push.y == 0.0, "pushed away from the close neighbour only: %s" % push)
	var closer := Steering.separation(Vector2.ZERO, [Vector2(0.2, 0.0)], 1.5)
	check(closer.length() > push.length(), "stronger when closer")
	check(Steering.separation(Vector2.ZERO, [Vector2.ZERO], 1.5).is_finite(), "finite on top of a neighbour")


func test_interpose_targets_midpoint() -> void:
	var vel := Steering.interpose(Vector2.ZERO, Vector2(10.0, 4.0), Vector2(10.0, -4.0), 4.0, 3.0)
	check_near(vel.angle(), 0.0, 1e-6, "heads for the midpoint")
	check_eq(Steering.interpose(Vector2(10.0, 0.0), Vector2(10.0, 4.0), Vector2(10.0, -4.0), 4.0, 3.0), Vector2.ZERO, "stops on it")


func test_blend_caps_at_max_speed() -> void:
	var fast := Steering.blend([Vector2(4.0, 0.0), Vector2(4.0, 0.0)], [1.0, 1.0], 4.0)
	var slow := Steering.blend([Vector2(1.0, 0.0), Vector2(0.0, 2.0)], [1.0, 0.5], 4.0)
	check_near(fast.length(), 4.0, 1e-6, "capped")
	check_eq(slow, Vector2(1.0, 1.0), "weighted sum below the cap")


func test_anchor_mirrors_and_follows_the_ball() -> void:
	var role := {"home": [-0.25, 0.2], "shift": [0.5, 0.5]}
	var pitch: Dictionary = drill.pitch
	check_eq(Roles.anchor(role, Vector2.ZERO, pitch, 1), Vector2(-10.0, 5.0), "team attacking +x")
	check_eq(Roles.anchor(role, Vector2.ZERO, pitch, -1), Vector2(10.0, 5.0), "team attacking -x")
	check_eq(Roles.anchor(role, Vector2(4.0, -2.0), pitch, 1), Vector2(-8.0, 4.0), "shifts with the ball")
	check_eq(Roles.anchor(role, Vector2(0.0, 99.0), pitch, 1).y, pitch.width * 0.5, "stays on the pitch")


func test_spawn_builds_five_a_side() -> void:
	var state: WorldState = Roles.spawn(drill, t)
	check_eq(state.players.size(), 10, "players")
	check_eq(state.players.filter(func(p: WorldState.PlayerState) -> bool: return p.team == 1).size(), 5, "team 1")
	check_eq(state.players[0].role, "gk", "first role")
	check(state.players[0].pos.x < 0.0 and state.players[5].pos.x > 0.0, "teams start in their own halves")
	check_near(absf(state.players[5].body_yaw), PI, 1e-6, "team 1 faces -x")


func test_snapshot_copies_the_world() -> void:
	var state: WorldState = Roles.spawn(drill, t)
	state.tick = 120
	state.ball.pos = Vector3(1.0, 2.0, 3.0)
	state.ball.owner_id = 4
	var snap: PitchSnapshot = PitchSnapshot.from_world(state, t.sim.tick_rate)
	check_near(snap.time, 2.0, 1e-6, "time")
	check_eq(snap.players.size(), 10, "players")
	check_eq(snap.players[7].team, 1, "team")
	check_eq(snap.players[7].pos, state.players[7].pos, "pos")
	check_eq(snap.ball_pos, Vector2(1.0, 3.0), "ball on the ground plane")
	check_eq(snap.ball_height, 2.0, "ball height")
	check_eq(snap.owner_id, 4, "owner")


func test_intent_becomes_a_command_that_turns_then_runs() -> void:
	var player := WorldState.PlayerState.new()
	var intent := Intent.new()
	intent.desired_velocity = Vector2(0.0, t.player.sprint_speed)
	intent.action = PlayerCommand.Action.TACKLE
	var turning: PlayerCommand = intent.to_command(9, player, t)
	check(turning.move.x > 0.0, "steers toward +yaw")
	check_near(turning.move.y, 0.0, 1e-6, "does not run sideways to the target")
	check_eq(turning.action, PlayerCommand.Action.TACKLE, "action carried")
	check_eq(turning.tick, 9, "tick")
	player.body_yaw = PI * 0.5
	var running: PlayerCommand = intent.to_command(9, player, t)
	check(running.sprint and is_equal_approx(running.move.y, 1.0), "sprints once facing it")
	intent.desired_velocity = Vector2.ZERO
	intent.desired_facing = PI
	var standing: PlayerCommand = intent.to_command(9, player, t)
	check(standing.move.y == 0.0 and standing.move.x > 0.0, "stands and turns to the desired facing")


func _run_bots(ticks: int) -> Dictionary:
	var state: WorldState = Roles.spawn(drill, t)
	Sim.seed_rng(state, 3)
	var controller := BotController.new(cfg, [drill, drill])
	var min_dist := INF
	var flips := {}
	var last_turn := {}
	var last_yaw := {}
	var moved := 0.0
	for p in state.players:
		flips[p.id] = 0
		last_turn[p.id] = 0.0
		last_yaw[p.id] = p.body_yaw
	for i in ticks:
		var before := state.players[4].pos
		Sim.step(state, controller.commands(state), cfg)
		moved += state.players[4].pos.distance_to(before)
		for a in state.players:
			var turn := angle_difference(last_yaw[a.id], a.body_yaw)
			last_yaw[a.id] = a.body_yaw
			if absf(turn) > 1e-5:
				flips[a.id] += int(turn * last_turn[a.id] < 0.0)
				last_turn[a.id] = turn
			for b in state.players:
				if a.id < b.id:
					min_dist = minf(min_dist, a.pos.distance_to(b.pos))
	return {"min_dist": min_dist, "max_flips": flips.values().max(), "moved": moved, "state": state}


func test_ten_bots_600_ticks_never_overlap() -> void:
	var run := _run_bots(600)
	check(run.min_dist >= t.player.radius * 2.0 - 0.01, "closest pair %s m" % run.min_dist)
	check(run.moved > 5.0, "the bots actually move, striker covered %s m" % run.moved)


func test_no_jitter() -> void:
	var run := _run_bots(600)
	var per_second: float = run.max_flips / 10.0
	check(per_second < t.steering.max_flips, "worst bot flips turn direction %s times per second" % per_second)


func test_bot_carrier_keeps_its_eyes_on_the_ball() -> void:
	var state: WorldState = Roles.spawn(drill, t)
	var controller := BotController.new(cfg, [drill, drill])
	var striker := state.players[4]
	state.ball.pos = Vector3(striker.pos.x + 0.6, t.ball.radius, striker.pos.y)
	for i in 300:
		Sim.step(state, controller.commands(state), cfg)
		if state.ball.owner_id != striker.id:
			break
		check_eq(striker.control_penalty, 0.0, "no gaze penalty at tick %s" % i)


func test_human_player_gets_no_bot_command() -> void:
	var state: WorldState = Roles.spawn(drill, t)
	var controller := BotController.new(cfg, [drill, drill])
	controller.human_id = 3
	var ids := controller.commands(state).map(func(c: PlayerCommand) -> int: return c.player_id)
	check_eq(ids.size(), 9, "nine commands")
	check(not ids.has(3), "none for the human")
