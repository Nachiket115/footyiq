extends RefCounted

static var errors: Array[String] = []


static func load_all(dir: String) -> Dictionary:
	var out := {}
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json"):
			continue
		var path := dir.path_join(file)
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK:
			errors.append("%s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
			continue
		out[file.get_basename()] = json.data
	return out


static func require(cfg: Dictionary, path: String) -> Variant:
	var node: Variant = cfg
	for key in path.split("."):
		if not (node is Dictionary and node.has(key)):
			errors.append("missing config key: %s" % path)
			return null
		node = node[key]
	return node
