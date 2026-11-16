extends RefCounted

const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const PlayerMotion = preload("res://core/player_motion.gd")
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

	var by_player := {}
	for cmd: PlayerCommand in commands:
		by_player[cmd.player_id] = cmd
	var margin: float = t.player.out_margin
	var limit := Vector2(state.pitch.length * 0.5 + margin, state.pitch.width * 0.5 + margin)
	for player in state.players:
		var cmd: PlayerCommand = by_player.get(player.id)
		PlayerMotion.apply(player, cmd if cmd != null else _idle(player), dt, t.player)
	PlayerMotion.separate(state.players, t.player.radius)
	for player in state.players:
		player.pos = player.pos.clamp(-limit, limit)

	var rng := RandomNumberGenerator.new()
	rng.state = int(state.rng_state)
	BallControl.update(state, by_player, dt, t, rng)
	state.rng_state = str(rng.state)

	for event in BallPhysics.integrate(state.ball, state.players, dt, state.pitch, t):
		event["tick"] = state.tick
		state.events.append(event)
		if event.type == "goal":
			state.score[event.team] += 1
			_place_ball(state.ball, Vector3(0.0, t.ball.radius, 0.0))
		else:
			var reach_x: float = state.pitch.length * 0.5 - t.sim.restart_inset
			var reach_z: float = state.pitch.width * 0.5 - t.sim.restart_inset
			_place_ball(state.ball, Vector3(clampf(event.pos.x, -reach_x, reach_x), event.pos.y, clampf(event.pos.z, -reach_z, reach_z)))
	return state


static func _idle(player: WorldState.PlayerState) -> PlayerCommand:
	var cmd := PlayerCommand.new()
	cmd.player_id = player.id
	cmd.look_yaw = player.head_yaw
	cmd.look_pitch = player.head_pitch
	return cmd


static func _place_ball(ball: WorldState.BallState, pos: Vector3) -> void:
	ball.pos = pos
	ball.vel = Vector3.ZERO
	ball.spin = Vector3.ZERO
	ball.owner_id = -1
	ball.pass_from_id = -1
	ball.pass_target_id = -1
