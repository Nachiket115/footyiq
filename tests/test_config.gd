extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")

const TMP_DIR := "user://test_config"


func test_load_all_reads_tuning() -> void:
	Config.errors.clear()
	var cfg := Config.load_all("res://config")
	check_eq(Config.require(cfg, "tuning.sim.tick_rate"), 60.0, "tick rate")
	check(Config.errors.is_empty(), "no errors: %s" % [Config.errors])


func test_require_missing_key_reports_path() -> void:
	Config.errors.clear()
	var cfg := {"tuning": {"sim": {}}}
	check_eq(Config.require(cfg, "tuning.sim.nope"), null, "missing value")
	check_eq(Config.errors.size(), 1, "error count")
	check(Config.errors[0].contains("tuning.sim.nope"), "error names the key")


func test_malformed_json_reports_file() -> void:
	Config.errors.clear()
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var file := FileAccess.open(TMP_DIR + "/bad.json", FileAccess.WRITE)
	file.store_string("{ \"a\": ")
	file.close()
	var cfg := Config.load_all(TMP_DIR)
	DirAccess.remove_absolute(TMP_DIR + "/bad.json")
	check(not cfg.has("bad"), "bad file not loaded")
	check_eq(Config.errors.size(), 1, "error count")
	check(Config.errors[0].contains("bad.json"), "error names the file")
