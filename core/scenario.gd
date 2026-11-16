extends RefCounted

const WorldState = preload("res://core/world_state.gd")
const Tactic = preload("res://core/tactic.gd")

const KEYS := ["title", "goal", "team", "ball", "time_s", "objectives"]


static func problems(name: String, s: Dictionary, objectives: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for key: String in KEYS + (["reach"] if s.get("team", 0) == 0 else ["hold", "deny"]):
		if not s.has(key):
			found.append("scenario %s: missing %s" % [name, key])
	for side: Dictionary in s.get("objectives", []):
		for phase: String in ["attack", "defend"]:
			if not objectives.has(side.get(phase, "")):
				found.append("scenario %s: unknown objective %s" % [name, side.get(phase, "")])
	return found


static func outcome(s: Dictionary, state: WorldState, elapsed: float) -> String:
	for event in state.events:
		if event.type == "goal":
			return "won" if event.team == 0 else "lost"
	var owner := state.player_by_id(state.ball.owner_id)
	var upfield: float = state.ball.pos.x / state.pitch.length
	if s.team == 0:
		if owner != null and owner.team == 1:
			return "lost"
		if owner != null and upfield >= s.reach:
			return "won"
		return "lost" if elapsed >= s.time_s else ""
	if owner != null and owner.team == 0:
		return "won"
	if upfield <= s.deny:
		return "lost"
	if elapsed >= s.time_s:
		return "won" if s.hold else "lost"
	return ""


static func summary(score: Dictionary, start_s := 0.0) -> Array[String]:
	var lines: Array[String] = []
	for kind: Array in [["structure", "Shape"], ["run", "Runs"], ["duty", "Duties"]]:
		var cells: Dictionary = score.get(kind[0], {})
		if cells.is_empty():
			continue
		var total := 0.0
		for phase: String in cells:
			total += cells[phase]
		lines.append("%s  %d%%" % [kind[1], roundi(100.0 * total / cells.size())])
	for miss: Dictionary in score.get("missed_triggers", []):
		lines.append("Missed at %.0f s: %s after %s" % [miss.t - start_s, miss.response.replace("_", " "), miss.trigger.replace("_", " ")])
	return lines
