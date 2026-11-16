extends RefCounted

const Tactic = preload("res://core/tactic.gd")
const Scenario = preload("res://core/scenario.gd")

static var errors: Array[String] = []


static func load_all(dir: String) -> Dictionary:
	var out := {}
	for sub in DirAccess.get_directories_at(dir):
		out[sub] = load_all(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json"):
			continue
		var path := dir.path_join(file)
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK:
			errors.append("%s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
			continue
		out[file.get_basename()] = json.data
	for name: String in out.get("scenarios", {}):
		errors.append_array(Scenario.problems(name, out.scenarios[name], out.get("objectives", {})))
	var drills: Dictionary = out.get("drills", {})
	for name: String in drills:
		if not drills[name].has("tactic"):
			continue
		var tactic: String = drills[name].tactic
		if not out.get("tactics", {}).has(tactic):
			errors.append("drills.json %s: unknown tactic %s" % [name, tactic])
			continue
		errors.append_array(Tactic.problems(tactic, out.tactics[tactic]))
		drills[name].roles = out.tactics[tactic].roles
		var away: String = drills[name].get("away_tactic", tactic)
		if not out.tactics.has(away):
			errors.append("drills.json %s: unknown tactic %s" % [name, away])
			continue
		errors.append_array(Tactic.problems(away, out.tactics[away]))
		drills[name].team_roles = [drills[name].roles, out.tactics[away].roles]
		for team in drills[name].teams.size():
			for role: String in drills[name].teams[team]:
				if not drills[name].team_roles[team].has(role):
					errors.append("drills.json %s: team %d role %s is not in its tactic" % [name, team, role])
	return out


static func for_drill(cfg: Dictionary, name: String) -> Dictionary:
	var out := cfg.duplicate(true)
	_merge(out, out["drills"][name].get("overrides", {}))
	out["tuning"].debug.drill = name
	return out


static func _merge(into: Dictionary, from: Dictionary) -> void:
	for key: String in from:
		if from[key] is Dictionary and into.get(key) is Dictionary:
			_merge(into[key], from[key])
		else:
			into[key] = from[key]


static func require(cfg: Dictionary, path: String) -> Variant:
	var node: Variant = cfg
	for key in path.split("."):
		if not (node is Dictionary and node.has(key)):
			errors.append("missing config key: %s" % path)
			return null
		node = node[key]
	return node
