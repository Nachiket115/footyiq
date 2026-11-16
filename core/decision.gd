extends RefCounted

const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const LaneMath = preload("res://core/lane_math.gd")

const NAMES := {"through": "Through pass", "square": "Square pass", "back": "Back pass", "shoot": "Shoot", "dribble": "Dribble"}
const ORDER := ["through", "square", "back", "shoot", "dribble"]


static func options(snap: PitchSnapshot, player_id: int, dir: int, t: Dictionary) -> Array:
	var d: Dictionary = t.decision
	var w: Dictionary = t.bot.weights
	var me := {}
	var by_id := {}
	var opponents := []
	var outfield := []
	for player in snap.players:
		by_id[player.id] = player
		if player.id == player_id:
			me = player
	for player in snap.players:
		if player.team != me.team:
			opponents.append(player.pos)
			if player.role != "gk":
				outfield.append(player.pos)

	var found := {}
	for option in LaneMath.rank_options(snap, player_id, dir, t):
		var mate: Dictionary = by_id[option.id]
		var ahead: float = (mate.pos.x - me.pos.x) * dir
		var kind := "through" if ahead > d.forward_m else ("back" if ahead < -d.forward_m else "square")
		if option.openness >= d.min_open and not found.has(kind):
			found[kind] = {"kind": kind, "target_id": mate.id, "value": option.value, "label": "%s to %s" % [NAMES[kind], mate.role.to_upper()]}

	var goal := Vector2(dir * snap.pitch.length * 0.5, 0.0)
	var reach: float = t.steering.shoot_range
	var dist: float = me.pos.distance_to(goal)
	if dist < reach:
		var open := LaneMath.lane_openness(me.pos, goal, outfield, t)
		if open > 0.0:
			found["shoot"] = {"kind": "shoot", "target_id": -1, "value": w.shoot * open * (1.0 - t.bot.shot_distance_falloff * dist / reach), "label": NAMES.shoot}

	var probe: Vector2 = me.pos + Vector2(dir * t.bot.dribble_probe, 0.0)
	var room := (LaneMath.space_score(probe, opponents, t) + LaneMath.space_score(me.pos, opponents, t)) * 0.5
	found["dribble"] = {"kind": "dribble", "target_id": -1, "value": w.dribble * room, "label": NAMES.dribble}

	var out := []
	for kind: String in ORDER:
		if found.has(kind):
			out.append(found[kind])
	return out


static func kind_of(choices: Array, event: Dictionary) -> String:
	if event.type == "shot":
		return "shoot"
	for choice: Dictionary in choices:
		if choice.target_id != -1 and choice.target_id == event.get("target_id", -1):
			return choice.kind
	return "other"


static func verdict(choices: Array, kind: String) -> Dictionary:
	var best: Dictionary = choices[0]
	var picked := "Pass"
	for choice: Dictionary in choices:
		if choice.value > best.value:
			best = choice
		if choice.kind == kind:
			picked = choice.label
	if kind == "shoot":
		picked = NAMES.shoot
	if best.kind == kind:
		return {"good": true, "text": "%s: the best option" % picked}
	return {"good": false, "text": "%s. Better: %s" % [picked, best.label[0].to_lower() + best.label.substr(1)]}
