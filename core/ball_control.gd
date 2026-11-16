extends RefCounted

const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")

const Action = PlayerCommand.Action


static func update(state: WorldState, commands: Dictionary, dt: float, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var ball := state.ball
	var c: Dictionary = t.control
	var owner := state.player_by_id(ball.owner_id)
	if owner != null and not _near(ball, owner, c.radius, c.max_height):
		ball.owner_id = -1
		owner = null

	var fresh := false
	if owner != null:
		for player in state.players:
			if player.team == owner.team or _action(commands, player) != Action.TACKLE:
				continue
			if _near(ball, player, t.tackle.radius, c.max_height) and rng.randf() < t.tackle.chance_per_s * dt:
				owner = player
				fresh = true
				_take(state, player, true)
				break

	if owner == null:
		owner = _claimant(state, commands, c)
		if owner != null:
			fresh = true
			_take(state, owner, false)

	for player in state.players:
		var action := _action(commands, player)
		if action != Action.PASS and action != Action.SHOOT:
			continue
		if ball.owner_id != -1 and ball.owner_id != player.id:
			continue
		if _near(ball, player, c.radius, t.player.height):
			_kick(state, player, commands[player.id], t.kick)
			return

	if owner == null:
		return
	if _action(commands, owner) == Action.TRAP:
		_set_flat_vel(ball, owner.vel)
	elif fresh or _touch_due(ball, owner, t.dribble):
		_touch(ball, owner, t)
		_event(state, "touch", owner.id)


static func _action(commands: Dictionary, player: WorldState.PlayerState) -> int:
	var cmd: PlayerCommand = commands.get(player.id)
	return Action.NONE if cmd == null else cmd.action


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _set_flat_vel(ball: WorldState.BallState, vel: Vector2) -> void:
	ball.vel = Vector3(vel.x, minf(ball.vel.y, 0.0), vel.y)


static func _near(ball: WorldState.BallState, player: WorldState.PlayerState, radius: float, max_height: float) -> bool:
	return ball.pos.y <= max_height and _flat(ball.pos).distance_to(player.pos) <= radius


static func _claimant(state: WorldState, commands: Dictionary, c: Dictionary) -> WorldState.PlayerState:
	var ball := state.ball
	var best: WorldState.PlayerState = null
	var best_dist := INF
	for player in state.players:
		if not _near(ball, player, c.radius, c.max_height):
			continue
		var offset := _flat(ball.pos) - player.pos
		var rel := _flat(ball.vel) - player.vel
		var max_speed: float = c.max_ball_speed
		if _action(commands, player) == Action.TRAP:
			max_speed *= c.trap_speed_factor
		if rel.length() > max_speed or rel.dot(offset) > 0.0:
			continue
		if offset.length() < best_dist:
			best_dist = offset.length()
			best = player
	return best


static func _take(state: WorldState, player: WorldState.PlayerState, tackle: bool) -> void:
	var ball := state.ball
	var previous := state.player_by_id(ball.last_touch_id)
	if previous != null and previous.team != player.team:
		_event(state, "turnover", player.id, {"from_id": previous.id, "tackle": tackle})
	_event(state, "receive", player.id, {"from_id": ball.pass_from_id, "target_id": ball.pass_target_id})
	ball.owner_id = player.id
	ball.last_touch_id = player.id
	ball.pass_from_id = -1
	ball.pass_target_id = -1


static func _kick(state: WorldState, player: WorldState.PlayerState, cmd: PlayerCommand, k: Dictionary) -> void:
	var ball := state.ball
	var passing := cmd.action == Action.PASS
	var power := clampf(cmd.power, 0.0, 1.0)
	var speed: float = lerpf(k.pass_speed_min, k.pass_speed_max, power) if passing else k.shot_speed * power
	var yaw := player.body_yaw + player.head_yaw
	var loft := deg_to_rad(k.loft_angle_deg) if cmd.lofted else 0.0
	ball.vel = Vector3(cos(yaw) * cos(loft), sin(loft), sin(yaw) * cos(loft)) * speed
	ball.owner_id = -1
	ball.last_touch_id = player.id
	ball.pass_from_id = player.id if passing else -1
	ball.pass_target_id = cmd.target_id if passing else -1
	_event(state, "pass" if passing else "shot", player.id, {"target_id": cmd.target_id, "power": power, "lofted": cmd.lofted})


static func _home(player: WorldState.PlayerState, d: Dictionary) -> Vector2:
	return player.pos + Vector2.from_angle(player.body_yaw) * d.lead_distance


static func _touch_due(ball: WorldState.BallState, player: WorldState.PlayerState, d: Dictionary) -> bool:
	var offset := _flat(ball.pos) - _home(player, d)
	return offset.length() > d.slack and offset.dot(_flat(ball.vel) - player.vel) >= 0.0


static func _touch(ball: WorldState.BallState, player: WorldState.PlayerState, t: Dictionary) -> void:
	var to_home := _home(player, t.dribble) - _flat(ball.pos)
	var roll_speed: float = sqrt(2.0 * t.ball.rolling_friction * t.sim.gravity * to_home.length())
	_set_flat_vel(ball, player.vel + to_home.normalized() * roll_speed * t.dribble.touch_speed_factor)


static func _event(state: WorldState, type: String, player_id: int, extra := {}) -> void:
	var event := {"type": type, "tick": state.tick, "player_id": player_id}
	event.merge(extra)
	state.events.append(event)
