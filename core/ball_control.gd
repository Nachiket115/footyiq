extends RefCounted

const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")

const Action = PlayerCommand.Action


static func update(state: WorldState, commands: Dictionary, dt: float, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var ball := state.ball
	var c: Dictionary = t.control
	ball.touch_wait = maxf(0.0, ball.touch_wait - dt)
	for player in state.players:
		update_gaze_penalty(player, ball, dt, t)

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
				break
	else:
		owner = _claimant(state, commands, c)
		fresh = owner != null

	var error := 0.0
	if fresh:
		var trapping := _action(commands, owner) == Action.TRAP
		var quality := _arrival_quality(ball, owner, trapping, t)
		if quality < t.first_touch.clean_min:
			error = 1.0 - quality
		_take(state, owner, ball.owner_id != -1, quality, touch_outcome(quality, t))
		if trapping:
			_set_flat_vel(ball, owner.vel)
		else:
			_touch(ball, owner, t)

	for player in state.players:
		var action := _action(commands, player)
		if action != Action.PASS and action != Action.SHOOT:
			continue
		if ball.owner_id != -1 and ball.owner_id != player.id:
			continue
		if _near(ball, player, c.radius, t.player.height):
			_kick(state, player, commands[player.id], t, rng)
			return

	if owner == null:
		return
	if not fresh:
		if ball.touch_wait > 0.0 or not _touch_due(ball, owner, t.dribble):
			return
		_touch(ball, owner, t)
	error = maxf(error, owner.control_penalty)
	if error > 0.0:
		var spread := deg_to_rad(t.touch.max_error_deg) * error
		var stray := Vector2.from_angle(owner.body_yaw + rng.randf_range(-spread, spread))
		_set_flat_vel(ball, _flat(ball.vel) + stray * t.touch.max_error_speed * error * rng.randf())
	ball.touch_wait = t.dribble.touch_interval
	_event(state, "touch", owner.id, {"error": error})


static func update_gaze_penalty(player: WorldState.PlayerState, ball: WorldState.BallState, dt: float, t: Dictionary) -> void:
	var g: Dictionary = t.gaze
	var yaw := player.body_yaw + player.head_yaw
	var pitch := player.head_pitch
	var view := Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw))
	var to_ball := ball.pos - Vector3(player.pos.x, t.player.eye_height, player.pos.y)
	var away := view.angle_to(to_ball) > deg_to_rad(g.angle_threshold_deg)
	player.look_away_time = player.look_away_time + dt if away else 0.0
	player.pitch_up_time = player.pitch_up_time + dt if pitch > deg_to_rad(g.pitch_threshold_deg) else 0.0
	if ball.owner_id == player.id and not _watching(player, g):
		var rate: float = g.rise_rate * (g.sprint_multiplier if player.sprinting else 1.0)
		player.control_penalty = minf(1.0, player.control_penalty + rate * dt)
	else:
		player.control_penalty = maxf(0.0, player.control_penalty - g.decay_rate * dt)


static func aim_direction(player: WorldState.PlayerState, p: Dictionary, roll := 0.0) -> Vector2:
	var off_body := minf(1.0, absf(player.head_yaw) / deg_to_rad(p.player.head_yaw_limit_deg))
	return Vector2.from_angle(player.body_yaw + player.head_yaw + roll * off_body * deg_to_rad(p.pass.max_offbody_error_deg))


static func intended_receiver(state: WorldState, passer_id: int, dir: Vector2, speed: float, p: Dictionary) -> int:
	var passer := state.player_by_id(passer_id)
	var best := -1
	if dir == Vector2.ZERO or speed <= 0.0:
		return best
	var reach: float = speed * speed / (2.0 * p.ball.rolling_friction * p.sim.gravity)
	var best_gap: float = p.pass.receiver_tolerance
	for mate in state.players:
		if mate.team != passer.team or mate.id == passer_id:
			continue
		var meet := mate.pos + mate.vel * clampf((mate.pos - passer.pos).dot(dir), 0.0, reach) / speed
		var gap := meet.distance_to(passer.pos + dir * clampf((meet - passer.pos).dot(dir), 0.0, reach))
		if gap <= best_gap:
			best_gap = gap
			best = mate.id
	return best


static func control_after(state: WorldState, controlled_id: int, follow_ball: bool, defend_switch := true, on_receive := true) -> int:
	if not follow_ball:
		return controlled_id
	var team := state.player_by_id(controlled_id).team
	for event in state.events:
		if event.type == "pass" and event.player_id == controlled_id and event.target_id != -1:
			return event.target_id
		if event.type != "receive" or not on_receive:
			continue
		if state.player_by_id(event.player_id).team == team:
			return event.player_id
		if defend_switch:
			return switch_target(state, controlled_id, true)
	return controlled_id


static func switch_target(state: WorldState, controlled_id: int, may_stay := false) -> int:
	var team := state.player_by_id(controlled_id).team
	var nearest := controlled_id
	var nearest_dist := INF
	for mate in state.players:
		var dist := mate.pos.distance_to(_flat(state.ball.pos))
		if mate.team == team and mate.role != "gk" and dist < nearest_dist and (may_stay or mate.id != controlled_id):
			nearest_dist = dist
			nearest = mate.id
	return nearest


static func first_touch_quality(ball_speed: float, pass_to_facing_angle: float, oriented: bool, t: Dictionary) -> float:
	var f: Dictionary = t.first_touch
	var pace := clampf(ball_speed / t.control.max_ball_speed, 0.0, 1.0)
	var cost: float = f.speed_weight + f.angle_weight * absf(pass_to_facing_angle) / PI
	if not oriented:
		cost += f.unoriented_weight
	return clampf(1.0 - pace * cost, 0.0, 1.0)


static func touch_outcome(quality: float, t: Dictionary) -> String:
	if quality >= t.first_touch.clean_min:
		return "clean"
	return "loose" if quality >= t.first_touch.loose_min else "lost"


static func _watching(player: WorldState.PlayerState, g: Dictionary) -> bool:
	return maxf(player.look_away_time, player.pitch_up_time) <= g.grace_s


static func _arrival_quality(ball: WorldState.BallState, player: WorldState.PlayerState, trapping: bool, t: Dictionary) -> float:
	var rel := _flat(ball.vel) - player.vel
	var speed := rel.length()
	var angle := 0.0 if speed == 0.0 else angle_difference(player.body_yaw, (-rel).angle())
	if trapping:
		speed /= t.control.trap_speed_factor
	return first_touch_quality(speed, angle, _watching(player, t.gaze), t)


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


static func _take(state: WorldState, player: WorldState.PlayerState, tackle: bool, quality: float, outcome: String) -> void:
	var ball := state.ball
	var previous := state.player_by_id(ball.last_touch_id)
	if previous != null and previous.team != player.team:
		_event(state, "turnover", player.id, {"from_id": previous.id, "tackle": tackle})
	_event(state, "receive", player.id, {"from_id": ball.pass_from_id, "target_id": ball.pass_target_id, "quality": quality, "outcome": outcome})
	ball.owner_id = player.id
	ball.last_touch_id = player.id
	ball.pass_from_id = -1
	ball.pass_target_id = -1


static func _kick(state: WorldState, player: WorldState.PlayerState, cmd: PlayerCommand, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var ball := state.ball
	var k: Dictionary = t.kick
	var passing := cmd.action == Action.PASS
	var power := clampf(cmd.power, 0.0, 1.0)
	var speed: float = lerpf(k.pass_speed_min, k.pass_speed_max, power) if passing else k.shot_speed * power
	var looked := passing and cmd.target_id == -1
	var dir := aim_direction(player, t, rng.randf_range(-1.0, 1.0) if looked else 0.0)
	var loft := deg_to_rad(k.loft_angle_deg) if cmd.lofted else 0.0
	ball.vel = Vector3(dir.x * cos(loft), sin(loft), dir.y * cos(loft)) * speed
	var target := cmd.target_id if passing else -1
	if passing and target == -1:
		target = intended_receiver(state, player.id, dir, speed, t)
	ball.flight = 0.0
	ball.owner_id = -1
	ball.last_touch_id = player.id
	ball.pass_from_id = player.id if passing else -1
	ball.pass_target_id = target
	_event(state, "pass" if passing else "shot", player.id, {"target_id": target, "power": power, "lofted": cmd.lofted})


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
