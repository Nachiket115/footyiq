extends RefCounted

const WorldState = preload("res://core/world_state.gd")

const EPS := 1e-4


static func integrate(ball: WorldState.BallState, players: Array, dt: float, pitch: Dictionary, t: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var max_travel: float = t.ball.radius * t.ball.substep_travel_factor
	var steps := maxi(int(t.ball.min_substeps), ceili(ball.vel.length() * dt / max_travel))
	for i in steps:
		var event := _substep(ball, players, dt / steps, pitch, t)
		if not event.is_empty():
			events.append(event)
			break
	return events


static func _substep(ball: WorldState.BallState, players: Array, h: float, pitch: Dictionary, t: Dictionary) -> Dictionary:
	var b: Dictionary = t.ball
	var r: float = b.radius
	var g: float = t.sim.gravity

	if ball.pos.y <= r + EPS and ball.vel.y <= 0.0:
		ball.pos.y = r
		ball.vel.y = 0.0
		var speed := ball.vel.length()
		var slowed := maxf(0.0, speed - b.rolling_friction * g * h)
		ball.vel = ball.vel * (slowed / speed) if speed > 0.0 else Vector3.ZERO
	else:
		ball.vel.y -= g * h
	ball.vel /= 1.0 + b.air_drag / b.mass * ball.vel.length() * h
	ball.pos += ball.vel * h

	if ball.pos.y < r:
		ball.pos.y = r
		ball.vel.y = -ball.vel.y * b.restitution if ball.vel.y < -b.bounce_min_speed else 0.0

	var half_l: float = pitch.length * 0.5
	var half_w: float = pitch.width * 0.5
	var half_goal: float = pitch.get("goal_width", 0.0) * 0.5
	var goal_h: float = t.goal.height
	var frame_dist: float = r + t.goal.post_radius

	if half_goal > 0.0:
		for side in [-1.0, 1.0]:
			var goal_x: float = side * half_l
			if ball.pos.y < goal_h + r:
				for post_z in [-half_goal, half_goal]:
					_hit(ball, Vector2(goal_x, post_z), true, frame_dist, b.post_restitution)
			if absf(ball.pos.z) <= half_goal:
				_hit(ball, Vector2(goal_x, goal_h), false, frame_dist, b.post_restitution)

	for player: WorldState.PlayerState in players:
		if player.id != ball.owner_id and ball.pos.y - r < t.player.height:
			var surface_vel := Vector3(player.vel.x, 0.0, player.vel.y)
			_hit(ball, player.pos, true, r + t.player.radius, b.player_restitution, surface_vel)

	var in_mouth := absf(ball.pos.z) < half_goal and ball.pos.y < goal_h
	if in_mouth and absf(ball.pos.x) > half_l + r:
		return {"type": "goal", "team": 0 if ball.pos.x > 0.0 else 1}

	if pitch.get("boards", false):
		if not in_mouth:
			ball.pos.x = _board(ball.pos.x, half_l - r, ball, Vector3.AXIS_X, b.board_restitution)
		ball.pos.z = _board(ball.pos.z, half_w - r, ball, Vector3.AXIS_Z, b.board_restitution)
	elif absf(ball.pos.x) > half_l + r or absf(ball.pos.z) > half_w + r:
		var spot := Vector3(clampf(ball.pos.x, -half_l, half_l), r, clampf(ball.pos.z, -half_w, half_w))
		return {"type": "out", "pos": spot, "last_touch_id": ball.last_touch_id}
	return {}


static func _hit(ball: WorldState.BallState, axis: Vector2, in_xz: bool, min_dist: float, restitution: float, surface_vel := Vector3.ZERO) -> void:
	var delta := Vector2(ball.pos.x, ball.pos.z if in_xz else ball.pos.y) - axis
	var dist := delta.length()
	if dist >= min_dist:
		return
	var n2 := delta / dist if dist > EPS else Vector2.RIGHT
	var normal := Vector3(n2.x, 0.0, n2.y) if in_xz else Vector3(n2.x, n2.y, 0.0)
	ball.pos += normal * (min_dist - dist)
	var approach := (ball.vel - surface_vel).dot(normal)
	if approach < 0.0:
		ball.vel -= (1.0 + restitution) * approach * normal


static func _board(coord: float, limit: float, ball: WorldState.BallState, axis: int, restitution: float) -> float:
	if absf(coord) <= limit:
		return coord
	if ball.vel[axis] * coord > 0.0:
		ball.vel[axis] *= -restitution
	return signf(coord) * limit
