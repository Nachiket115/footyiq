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


static func track(held: Dictionary, state: WorldState) -> void:
	var owner := state.player_by_id(state.ball.owner_id)
	if owner != null and owner.team != held.get("team", -1):
		held.team = owner.team
		held.tick = state.tick


static func outcome(s: Dictionary, state: WorldState, elapsed: float, held: Dictionary, t: Dictionary) -> String:
	for event in state.events:
		if event.type == "goal":
			return "won" if event.team == 0 else "lost"
	var owner := state.player_by_id(state.ball.owner_id)
	var upfield: float = state.ball.pos.x / state.pitch.length
	var kept: bool = (state.tick - held.tick) / t.sim.tick_rate >= t.scenario.keep_s
	if s.team == 0:
		if held.team == 1 and kept:
			return "lost"
		if owner != null and owner.team == 0 and upfield >= s.reach:
			return "won"
		return "lost" if elapsed >= s.time_s else ""
	if held.team == 0 and kept:
		return "won"
	if upfield <= s.deny and (not s.get("deny_owned", false) or (owner != null and owner.team == 1)):
		return "lost"
	if elapsed >= s.time_s:
		return "won" if s.hold else "lost"
	return ""


static func bars(score: Dictionary) -> Array:
	var out := []
	for kind: Array in [["structure", "Shape"], ["run", "Runs"], ["duty", "Duties"]]:
		var cells: Dictionary = score.get(kind[0], {})
		if cells.is_empty():
			continue
		var total := 0.0
		for phase: String in cells:
			total += cells[phase]
		out.append([kind[1], total / cells.size()])
	return out


static func misses(score: Dictionary, start_s := 0.0) -> Array:
	var out := []
	for miss: Dictionary in score.get("missed_triggers", []):
		out.append("Missed at %.0f s: %s after %s" % [miss.t - start_s, miss.response.replace("_", " "), miss.trigger.replace("_", " ")])
	return out
