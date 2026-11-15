extends SceneTree


func _init() -> void:
	var total := 0
	var failed := 0
	for file in DirAccess.get_files_at("res://tests"):
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			print("FAIL %s: could not load" % file)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			total += 1
			var case: RefCounted = script.new()
			case.call(test_name)
			var problems: Array[String] = case.failures
			if case.checks == 0:
				problems = ["made no checks"]
			if problems.is_empty():
				continue
			failed += 1
			for problem in problems:
				print("FAIL %s.%s: %s" % [file, test_name, problem])
	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
