extends RefCounted

const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const BallPhysics = preload("res://core/ball_physics.gd")
const BallControl = preload("res://core/ball_control.gd")


static func seed_rng(state: WorldState, rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	state.rng_state = str(rng.state)


static func step(state: WorldState, commands: Array, cfg: Dictionary) -> WorldState:
	var t: Dictionary = cfg["tuning"]
	var dt: float = 1.0 / t.sim.tick_rate
	state.tick += 1
	state.events.clear()

	for cmd: PlayerCommand in commands:
		if cmd.action == PlayerCommand.Action.SHOOT:
			BallControl.kick(state, cmd, t)

	for event in BallPhysics.integrate(state.ball, state.players, dt, state.pitch, t):
		event["tick"] = state.tick
		state.events.append(event)
		if event.type == "goal":
			state.score[event.team] += 1
			_place_ball(state.ball, Vector3(0.0, t.ball.radius, 0.0))
		else:
			_place_ball(state.ball, event.pos)
	return state


static func _place_ball(ball: WorldState.BallState, pos: Vector3) -> void:
	ball.pos = pos
	ball.vel = Vector3.ZERO
	ball.spin = Vector3.ZERO
	ball.owner_id = -1
