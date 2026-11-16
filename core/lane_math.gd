extends RefCounted

const PitchSnapshot = preload("res://core/pitch_snapshot.gd")


static func lane_openness(from: Vector2, to: Vector2, opponents: Array, p: Dictionary) -> float:
	var l: Dictionary = p.lane
	var seg := to - from
	var len_sq := seg.length_squared()
	var open := 1.0
	for opp: Vector2 in opponents:
		var along := (opp - from).dot(seg) / len_sq if len_sq > 0.0 else 0.0
		var closest := from + seg * clampf(along, 0.0, 1.0)
		var reach: float = l.reach_radius + l.opp_speed * (closest - from).length() / l.pass_speed
		if along > 1.0:
			reach = l.behind_radius
		open = minf(open, clampf((opp.distance_to(closest) - reach) / l.margin, 0.0, 1.0))
	return open


static func space_score(point: Vector2, opponents: Array, p: Dictionary) -> float:
	var nearest := INF
	for opp: Vector2 in opponents:
		nearest = minf(nearest, point.distance_to(opp))
	return clampf(nearest / p.lane.space_radius, 0.0, 1.0)


static func option_value(snap: PitchSnapshot, passer_id: int, receiver_id: int, attacking_dir: int, p: Dictionary) -> float:
	return _option(snap, passer_id, receiver_id, attacking_dir, p).value


static func rank_options(snap: PitchSnapshot, passer_id: int, attacking_dir: int, p: Dictionary) -> Array[Dictionary]:
	var passer := _player(snap, passer_id)
	var options: Array[Dictionary] = []
	for mate in snap.players:
		if mate.team == passer.team and mate.id != passer_id:
			options.append(_option(snap, passer_id, mate.id, attacking_dir, p))
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.value > b.value)
	return options


static func _option(snap: PitchSnapshot, passer_id: int, receiver_id: int, attacking_dir: int, p: Dictionary) -> Dictionary:
	var l: Dictionary = p.lane
	var w: Dictionary = l.weights
	var passer := _player(snap, passer_id)
	var receiver := _player(snap, receiver_id)
	var opponents := []
	for other in snap.players:
		if other.team != passer.team:
			opponents.append(other.pos)
	var from: Vector2 = passer.pos
	var to: Vector2 = receiver.pos
	var openness := lane_openness(from, to, opponents, p)
	var progression := clampf((to.x - from.x) * attacking_dir / snap.pitch.length, -1.0, 1.0)
	var risk := clampf(from.distance_to(to) / l.max_pass_distance, 0.0, 1.0)
	var value: float = w.openness * openness + w.progression * progression \
		+ w.space * space_score(to, opponents, p) - w.risk * risk
	return {"id": receiver_id, "value": value, "openness": openness}


static func _player(snap: PitchSnapshot, id: int) -> Dictionary:
	for player in snap.players:
		if player.id == id:
			return player
	assert(false, "no player %d in snapshot" % id)
	return {}
