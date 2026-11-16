extends RefCounted

const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const LaneMath = preload("res://core/lane_math.gd")

const THIRD := 1.0 / 6.0
const PHASES := ["build_up", "final_third", "defensive_transition", "press", "low_block"]
const KINDS := {"run": "triggers", "duty": "duties"}
const EVENTS := {"possession_won": [], "possession_lost": [], "phase_enter": ["phase"], "mate_receives": ["role"], "carrier_near": ["radius"]}
const RESPONSES := {"run_forward": ["distance"], "run_back": ["distance"], "offer_lane": [], "press": ["distance"], "mark": ["distance"], "in_zone": []}


static func problems(name: String, tactic: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var roles: Dictionary = tactic.get("roles", {})
	if roles.is_empty():
		found.append("tactic %s: no roles" % name)
	for role: String in roles:
		var data: Dictionary = roles[role]
		var where := "tactic %s role %s" % [name, role]
		for key: String in ["shift", "zones", "triggers", "duties", "structure.mates", "structure.mate_distance", "structure.line_height", "structure.duty_distance"]:
			var node: Variant = data
			for part in key.split("."):
				node = node.get(part) if node is Dictionary else null
			if node == null:
				found.append("%s: missing %s" % [where, key])
		for phase: String in PHASES:
			if not data.get("zones", {}).has(phase):
				found.append("%s: no zone for %s" % [where, phase])
		for list: String in KINDS.values():
			for tr: Dictionary in data.get(list, []):
				var event: String = tr.get("event", "")
				var response: String = tr.get("response", "")
				if not EVENTS.has(event) or not RESPONSES.has(response):
					found.append("%s: unknown event or response in %s" % [where, tr])
					continue
				for arg: String in EVENTS[event] + RESPONSES[response] + ["window_s"]:
					if not tr.has(arg):
						found.append("%s: %s needs %s" % [where, event, arg])
	return found


static func possession(snap: PitchSnapshot) -> int:
	for id: int in [snap.owner_id, snap.last_touch_id]:
		for player in snap.players:
			if player.id == id:
				return player.team
	return -1


static func phase_of_play(snap: PitchSnapshot, team: int) -> String:
	var upfield: float = snap.ball_pos.x * (1 if team == 0 else -1) / snap.pitch.length
	if possession(snap) != 1 - team:
		return "final_third" if upfield > THIRD else "build_up"
	if upfield > THIRD:
		return "press"
	return "low_block" if upfield < -THIRD else "defensive_transition"


static func target_zone(role_data: Dictionary, phase: String, snap: PitchSnapshot, attacking_dir: int) -> Dictionary:
	var zone: Dictionary = role_data.zones[phase]
	var size := Vector2(snap.pitch.length, snap.pitch.width)
	var home := Vector2(zone.center[0] * attacking_dir, zone.center[1]) * size
	var shift := Vector2(role_data.shift[0], role_data.shift[1])
	return {"center": (home + snap.ball_pos * shift).clamp(size * -0.5, size * 0.5), "tolerance": zone.tolerance}


static func score_role(frames: Array, role_data: Dictionary, p: Dictionary) -> Dictionary:
	var tally := {"structure": {}, "run": {}, "duty": {}}
	var missed := []
	var pending := []
	var was := {}
	for snap: PitchSnapshot in frames:
		var me := _player(snap, p.player_id)
		var dir := 1 if me.team == 0 else -1
		var phase := phase_of_play(snap, me.team)
		var zone := target_zone(role_data, phase, snap, dir)
		var in_zone: bool = me.pos.distance_to(zone.center) <= zone.tolerance
		if snap.owner_id != -1 and snap.owner_id != me.id:
			var shaped := in_zone and _spaced(snap, me, role_data.structure, dir)
			_add(tally.structure, phase, float(shaped or _on_duty(snap, me, role_data.structure.duty_distance)))
		var lane := _offers_lane(snap, me, p.tuning)

		for kind: String in KINDS:
			var list: Array = role_data[KINDS[kind]]
			for i in list.size():
				var key := "%s%d" % [kind, i]
				var on := _event(list[i], snap, me, phase)
				if on and was.get(key) == false and not pending.any(func(item: Dictionary) -> bool: return item.key == key):
					pending.append({"key": key, "kind": kind, "tr": list[i], "t": snap.time, "phase": phase, "pos": me.pos, "lane": false})
				was[key] = on

		for item: Dictionary in pending.duplicate():
			var tr: Dictionary = item.tr
			item.lane = item.lane or lane
			if _response(tr, item, snap, me, dir, in_zone, lane):
				_add(tally[item.kind], item.phase, 1.0 if item.kind == "duty" or item.lane else p.tuning.tactic.run_without_lane)
			elif snap.time - item.t >= tr.window_s:
				_add(tally[item.kind], item.phase, 0.0)
				missed.append({"t": item.t, "trigger": tr.event, "response": tr.response})
			else:
				continue
			pending.erase(item)

	var result := {"missed_triggers": missed}
	for kind: String in tally:
		result[kind] = {}
		for phase: String in tally[kind]:
			result[kind][phase] = tally[kind][phase][0] / tally[kind][phase][1]
	return result


static func _spaced(snap: PitchSnapshot, me: Dictionary, rules: Dictionary, dir: int) -> bool:
	var height: float = (me.pos.x - snap.ball_pos.x) * dir
	if height < rules.line_height[0] or height > rules.line_height[1]:
		return false
	for other in snap.players:
		if other.team == me.team and other.role in rules.mates:
			var gap: float = me.pos.distance_to(other.pos)
			if gap < rules.mate_distance[0] or gap > rules.mate_distance[1]:
				return false
	return true


static func _on_duty(snap: PitchSnapshot, me: Dictionary, reach: float) -> bool:
	if possession(snap) != 1 - me.team:
		return false
	if me.pos.distance_to(snap.ball_pos) <= reach:
		return true
	return _near_opponent(snap, me, reach)


static func _near_opponent(snap: PitchSnapshot, me: Dictionary, reach: float) -> bool:
	for other in snap.players:
		if other.team != me.team and other.role != "gk" and other.pos.distance_to(me.pos) <= reach:
			return true
	return false


static func _offers_lane(snap: PitchSnapshot, me: Dictionary, tuning: Dictionary) -> bool:
	if snap.owner_id == me.id or possession(snap) != me.team:
		return false
	var opponents := []
	for other in snap.players:
		if other.team != me.team:
			opponents.append(other.pos)
	return LaneMath.lane_openness(snap.ball_pos, me.pos, opponents, tuning) >= tuning.tactic.open_lane


static func _event(tr: Dictionary, snap: PitchSnapshot, me: Dictionary, phase: String) -> bool:
	match tr.event:
		"possession_won":
			return possession(snap) == me.team
		"possession_lost":
			return possession(snap) == 1 - me.team
		"phase_enter":
			return phase == tr.phase
	for other in snap.players:
		if other.id == snap.owner_id and other.id != me.id:
			if tr.event == "mate_receives":
				return other.team == me.team and other.role == tr.role
			return other.team != me.team and other.pos.distance_to(me.pos) <= tr.radius
	return false


static func _response(tr: Dictionary, item: Dictionary, snap: PitchSnapshot, me: Dictionary, dir: int, in_zone: bool, lane: bool) -> bool:
	match tr.response:
		"run_forward":
			return (me.pos.x - item.pos.x) * dir >= tr.distance
		"run_back":
			return (item.pos.x - me.pos.x) * dir >= tr.distance
		"offer_lane":
			return lane
		"press":
			return me.pos.distance_to(snap.ball_pos) <= tr.distance
		"in_zone":
			return in_zone
	return _near_opponent(snap, me, tr.distance)


static func _add(tally: Dictionary, phase: String, value: float) -> void:
	var cell: Array = tally.get_or_add(phase, [0.0, 0])
	cell[0] += value
	cell[1] += 1


static func _player(snap: PitchSnapshot, id: int) -> Dictionary:
	for player in snap.players:
		if player.id == id:
			return player
	assert(false, "no player %d in frame" % id)
	return {}
