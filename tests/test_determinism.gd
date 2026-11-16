extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const Sim = preload("res://core/sim.gd")

var cfg := Config.load_all("res://config")


func _start(rng_seed: int) -> WorldState:
	var state := WorldState.new()
	state.pitch = {"length": 40.0, "width": 25.0, "goal_width": 3.0, "boards": true}
	var spots: Array[Vector2] = [Vector2(-0.5, 0.0), Vector2(6.0, 2.0)]
	for i in spots.size():
		var player := WorldState.PlayerState.new()
		player.id = i
		player.team = i
		player.pos = spots[i]
		state.players.append(player)
	state.players[0].head_yaw = 0.35
	state.ball.pos = Vector3(0.0, cfg["tuning"].ball.radius, 0.0)
	Sim.seed_rng(state, rng_seed)
	return state


func _commands(tick: int) -> Array:
	if tick % 150 != 1:
		return []
	var cmd := PlayerCommand.new()
	cmd.tick = tick
	cmd.player_id = 0
	cmd.look_yaw = 0.35
	cmd.move = Vector2(0.3, 1.0)
	cmd.action = PlayerCommand.Action.SHOOT
	cmd.power = 0.9
	cmd.lofted = tick > 1
	return [cmd]


func _run(state: WorldState, until_tick: int) -> void:
	while state.tick < until_tick:
		Sim.step(state, _commands(state.tick + 1), cfg)


func test_same_seed_same_commands_same_state() -> void:
	var a := _start(42)
	var b := _start(42)
	var start_pos := a.ball.pos
	_run(a, 600)
	_run(b, 600)
	check_eq(a.tick, 600, "tick")
	check(a.ball.pos.distance_to(start_pos) > 1.0, "the ball actually moved")
	check_eq(a.to_dict(), b.to_dict(), "states match")


func test_resume_from_snapshot_matches_straight_run() -> void:
	var straight := _start(42)
	_run(straight, 600)
	var first_half := _start(42)
	_run(first_half, 300)
	var text := JSON.stringify(first_half.to_dict(), "", false, true)
	var resumed: WorldState = WorldState.from_dict(JSON.parse_string(text))
	_run(resumed, 600)
	check_eq(resumed.to_dict(), straight.to_dict(), "resumed state matches")


func test_kick_out_of_reach_does_nothing() -> void:
	var state := _start(42)
	state.ball.pos.x = 5.0
	Sim.step(state, _commands(1), cfg)
	check_eq(state.ball.vel, Vector3.ZERO, "ball not kicked")


func test_player_cannot_run_through_the_goal() -> void:
	var state := WorldState.new()
	state.pitch = cfg["drills"]["5v5"].pitch
	var runner := WorldState.PlayerState.new()
	runner.pos = Vector2(state.pitch.length * 0.5 - 2.0, 0.5)
	state.players.append(runner)
	var side := WorldState.PlayerState.new()
	side.id = 1
	side.pos = Vector2(state.pitch.length * 0.5 + 0.6, 4.0)
	side.body_yaw = -PI * 0.5
	state.players.append(side)
	state.ball.pos = Vector3(-10.0, 0.11, 0.0)
	Sim.seed_rng(state, 1)
	for i in 180:
		var cmds := []
		for id in 2:
			var cmd := PlayerCommand.new()
			cmd.player_id = id
			cmd.move = Vector2(0.0, 1.0)
			cmds.append(cmd)
		Sim.step(state, cmds, cfg)
	var t: Dictionary = cfg["tuning"]
	check(runner.pos.x <= state.pitch.length * 0.5 + 1e-3, "stopped at the goal line: %s" % runner.pos)
	check(side.pos.y >= state.pitch.goal_width * 0.5 + t.player.radius - 1e-3, "stopped by the side net: %s" % side.pos)
