extends RefCounted

const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const Intent = preload("res://core/intent.gd")
const LaneMath = preload("res://core/lane_math.gd")
const Steering = preload("res://bots/steering.gd")
const Roles = preload("res://bots/roles.gd")

const Action = PlayerCommand.Action

var snap: PitchSnapshot
var role: Dictionary
var t: Dictionary
var b: Dictionary
var w: Dictionary
var diff: Dictionary
var objective: Dictionary
var rng: RandomNumberGenerator
var me: Dictionary
var mates: Array[Dictionary] = []
var opps: Array[Dictionary] = []
var opp_pos: Array[Vector2] = []
var dir := 1
var goal := Vector2.ZERO
var own_goal := Vector2.ZERO
var jog := 0.0
var sprint := 0.0
var holder := {}
var ball_at := Vector2.ZERO
var chasing := false


static func decide(snapshot: PitchSnapshot, role_data: Dictionary, params: Dictionary) -> Intent:
	return new(snapshot, role_data, params)._decide()


func _init(snapshot: PitchSnapshot, role_data: Dictionary, params: Dictionary) -> void:
	snap = snapshot
	role = role_data
	t = params.tuning
	b = t.bot
	diff = params.difficulty
	rng = params.rng
	me = _player(params.self_id)
	for other in snap.players:
		if other.id == me.id:
			continue
		if other.team == me.team:
			mates.append(other)
		else:
			opps.append(other)
			opp_pos.append(other.pos)
	dir = Roles.attacking_dir(me.team)
	own_goal = _goal_of(me.team)
	goal = -own_goal
	jog = t.player.jog_speed * diff.speed_factor
	sprint = t.player.sprint_speed * diff.speed_factor
	_find_holder()
	objective = params.objectives["attack" if holder.team == me.team else "defend"]
	w = b.weights.duplicate()
	for key: String in objective.weights:
		w[key] *= objective.weights[key]


func _decide() -> Intent:
	if snap.owner_id == me.id:
		return _on_ball()
	if chasing:
		return _collect()
	if me.role == "gk":
		var line := Roles.anchor(role, snap.ball_pos, snap.pitch, dir)
		var post: float = snap.pitch.goal_width * 0.5
		return _go(Vector2(line.x, clampf(snap.ball_pos.y, -post, post)), sprint, Action.TRAP)
	return _support() if holder.team == me.team else _defend()


func _find_holder() -> void:
	ball_at = snap.ball_pos
	holder = me
	var best := [{}, {}]
	var times := [INF, INF]
	var points := [ball_at, ball_at]
	var keeping := -1
	for other in snap.players:
		if other.id == snap.owner_id:
			holder = other
			return
		if other.id == snap.last_touch_id:
			keeping = other.team
		var reach := _intercept(other)
		if other.role == "gk" and reach.point.distance_to(_goal_of(other.team)) > b.gk_claim_radius:
			continue
		if reach.time < times[other.team]:
			times[other.team] = reach.time
			best[other.team] = other
			points[other.team] = reach.point
	var first := 0 if times[0] <= times[1] else 1
	if keeping != -1 and times[keeping] < times[1 - keeping] + b.contest_margin:
		first = keeping
	if best[first].is_empty():
		return
	holder = best[first]
	ball_at = points[first]
	chasing = best[me.team].get("id", -1) == me.id and times[me.team] < times[first] + b.contest_margin


func _intercept(who: Dictionary) -> Dictionary:
	var speed := snap.ball_vel.length()
	var heading := snap.ball_vel / speed if speed > 0.0 else Vector2.ZERO
	var slowing: float = t.ball.rolling_friction * t.sim.gravity
	var half := Vector2(snap.pitch.length, snap.pitch.width) * 0.5
	var point := snap.ball_pos
	var time := 0.0
	while time <= b.intercept_horizon:
		var roll := minf(time, speed / slowing)
		point = (snap.ball_pos + heading * (speed * roll - 0.5 * slowing * roll * roll)).clamp(-half, half)
		if who.pos.distance_to(point) <= t.control.radius + t.player.sprint_speed * time:
			return {"time": time, "point": point}
		time += b.intercept_step
	return {"time": time + who.pos.distance_to(point) / t.player.sprint_speed, "point": point}


func _collect() -> Intent:
	var fast: bool = (snap.ball_vel - me.vel).length() > b.trap_speed
	return _go(_intercept(me).point, sprint, Action.TRAP if fast else Action.NONE)


func _on_ball() -> Intent:
	if me.pos.distance_to(snap.ball_pos) > b.gather_distance:
		var gather := _go(me.pos, 0.0)
		gather.desired_velocity = me.vel
		return gather
	var best := _go(me.pos, 0.0)
	var best_value := _noisy(w.hold * LaneMath.space_score(me.pos, opp_pos, t))
	for option in LaneMath.rank_options(snap, me.id, dir, t):
		var mate := _player(option.id)
		var offset: Vector2 = mate.pos - me.pos
		if offset.length() < b.min_pass_distance:
			continue
		var turn := absf(angle_difference(me.facing, offset.angle())) / PI
		var value := _noisy(option.value - w.turn * turn)
		if value > best_value:
			best_value = value
			best = _pass(mate)
	if me.role == "gk":
		return best

	var reach: float = t.steering.shoot_range
	var dist: float = me.pos.distance_to(goal)
	if dist < reach:
		var aim := _shot_aim()
		var fast := {"lane": t.lane.duplicate()}
		fast.lane.pass_speed = t.kick.shot_speed
		var open := LaneMath.lane_openness(me.pos, aim, _outfield(opps).map(func(o: Dictionary) -> Vector2: return o.pos), fast)
		var value := _noisy(w.shoot * open * (1.0 - b.shot_distance_falloff * dist / reach))
		if value > best_value:
			best_value = value
			best = Intent.new()
			best.action = Action.SHOOT
			best.power = 1.0
			best.desired_facing = (aim - me.pos).angle()

	var half := Vector2(snap.pitch.length, snap.pitch.width) * 0.5
	var here := LaneMath.space_score(me.pos, opp_pos, t)
	var run := Intent.new()
	var run_value := -INF
	for angle: float in b.dribble_angles_deg:
		var heading := Vector2.from_angle((goal - me.pos).angle() + deg_to_rad(angle))
		var probe: Vector2 = me.pos + heading * b.dribble_probe
		if absf(probe.x) > half.x or absf(probe.y) > half.y:
			continue
		var ahead := LaneMath.space_score(probe, opp_pos, t)
		var gain: float = (probe.x - me.pos.x) * dir / snap.pitch.length
		var swerve := absf(angle_difference(me.facing, heading.angle())) / PI
		var value: float = w.dribble * (ahead + here) * 0.5 + t.lane.weights.progression * gain - w.swerve * swerve
		if value > run_value:
			run_value = value
			run.desired_velocity = heading * lerpf(jog, sprint, b.dribble_sprint * ahead)
			run.desired_facing = heading.angle()
	return run if _noisy(run_value) > best_value else best


func _pass(mate: Dictionary) -> Intent:
	var k: Dictionary = t.kick
	var dist: float = me.pos.distance_to(mate.pos)
	var speed := clampf(b.pass_speed_base + b.pass_speed_per_m * dist, k.pass_speed_min, k.pass_speed_max)
	var aim: Vector2 = mate.pos + mate.vel * dist / speed
	var intent := Intent.new()
	intent.action = Action.PASS
	intent.target_id = mate.id
	intent.power = inverse_lerp(k.pass_speed_min, k.pass_speed_max, speed)
	intent.desired_facing = (aim - me.pos).angle()
	return intent


func _shot_aim() -> Vector2:
	var side: float = snap.pitch.goal_width * 0.5 - b.shot_post_margin
	for opp in opps:
		if opp.role == "gk" and opp.pos.y < 0.0:
			return Vector2(goal.x, side)
	return Vector2(goal.x, -side)


func _support() -> Intent:
	var anchor := _anchor()
	var half := Vector2(snap.pitch.length, snap.pitch.width) * 0.5 - Vector2.ONE
	var points := [anchor]
	var count := int(b.support_points)
	for i in count:
		var offset: Vector2 = Vector2.from_angle(TAU * i / count) * b.support_radius
		points.append((anchor + offset).clamp(-half, half))
		points.append((anchor + offset * 0.5).clamp(-half, half))
	var best := anchor
	var best_value := -INF
	for point: Vector2 in points:
		var nearest_mate := INF
		for mate in mates:
			nearest_mate = minf(nearest_mate, point.distance_to(mate.pos))
		var value: float = w.lane * LaneMath.lane_openness(ball_at, point, opp_pos, t) \
			+ w.space * LaneMath.space_score(point, opp_pos, t) \
			+ w.zone * (point.x * dir / snap.pitch.length + 0.5) \
			+ w.spacing * minf(1.0, nearest_mate / b.spacing_radius) \
			- w.travel * me.pos.distance_to(point) / b.support_radius
		if value > best_value:
			best_value = value
			best = point
	return _go(best, jog)


func _defend() -> Intent:
	var pressing := false
	var free: Array[Dictionary] = []
	for defender in _outfield(mates + [me]):
		if defender.pos.distance_to(ball_at) < diff.press_radius * objective.press_scale:
			pressing = true
			if defender.id == me.id:
				return _press()
		else:
			free.append(defender)

	var threats := _outfield(opps).filter(func(o: Dictionary) -> bool: return o.id != holder.id)
	threats.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x.pos.distance_to(own_goal) < y.pos.distance_to(own_goal))
	if not pressing and holder.role != "gk":
		threats.push_front(holder)
	for threat in threats:
		if free.is_empty():
			break
		var marker: Dictionary = free[0]
		for defender in free:
			if defender.pos.distance_to(threat.pos) < marker.pos.distance_to(threat.pos):
				marker = defender
		free.erase(marker)
		if marker.id == me.id:
			return _mark(threat)
	return _hurry(_anchor())


func _anchor() -> Vector2:
	var half := Vector2(snap.pitch.length, snap.pitch.width) * 0.5
	var shifted := Roles.anchor(role, snap.ball_pos, snap.pitch, dir) + Vector2(dir * objective.line_offset, 0.0)
	return shifted.clamp(-half, half)


func _press() -> Intent:
	if snap.owner_id == -1:
		return _collect()
	var in_reach: bool = me.pos.distance_to(snap.ball_pos) < t.tackle.radius * b.tackle_reach
	return _go(snap.ball_pos, sprint, Action.TACKLE if in_reach else Action.NONE)


func _mark(threat: Dictionary) -> Intent:
	var to_goal: Vector2 = (own_goal - threat.pos).normalized()
	if threat.id == holder.id:
		return _hurry(threat.pos + to_goal * b.contain_distance)
	var to_ball: Vector2 = (ball_at - threat.pos).normalized()
	return _hurry(threat.pos + (to_goal + to_ball * diff.lane_cover).normalized() * b.mark_distance)


func _hurry(target: Vector2) -> Intent:
	return _go(target, sprint if me.pos.distance_to(target) > b.hurry_distance else jog)


func _go(target: Vector2, speed: float, action := Action.NONE) -> Intent:
	var intent := Intent.new()
	intent.desired_velocity = Steering.arrive(me.pos, target, speed, t.steering.arrive_radius)
	intent.desired_facing = (snap.ball_pos - me.pos).angle()
	intent.action = action
	return intent


func _noisy(value: float) -> float:
	return value + rng.randfn(0.0, b.choice_noise)


func _outfield(group: Array) -> Array:
	return group.filter(func(p: Dictionary) -> bool: return p.role != "gk")


func _goal_of(team: int) -> Vector2:
	return Vector2(-Roles.attacking_dir(team) * snap.pitch.length * 0.5, 0.0)


func _player(id: int) -> Dictionary:
	for player in snap.players:
		if player.id == id:
			return player
	assert(false, "no player %d in snapshot" % id)
	return {}
