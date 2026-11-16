extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const ScenarioReport = preload("res://tools/scenario_report.gd")

var big := Config.for_drill(Config.load_all("res://config"), "11v11")
var report := ScenarioReport.scenarios(big, 1, 1)


func test_same_seed_gives_the_same_report() -> void:
	check_eq(JSON.stringify(ScenarioReport.scenarios(big, 1, 1)), JSON.stringify(report), "deterministic")


func test_report_has_a_cell_per_scenario_and_difficulty() -> void:
	check_eq(report.keys(), big["drills"]["11v11"].scenarios, "scenarios")
	var cell: Dictionary = report["build_from_the_back"]["hard"]
	check_eq(report["press_high"]["hard"].runs, 1, "runs")
	check(cell.win_rate >= 0.0 and cell.win_rate <= 1.0, "win rate in range")
	check(cell.block_depth > 0.0 and cell.block_depth < 105.0, "block depth in metres")


func test_idle_role_gets_no_bot_command() -> void:
	var idle := ScenarioReport.scenarios(big, 1, 1, "dm")
	check(JSON.stringify(report) != JSON.stringify(idle), "an idle pivot changes the result")


func test_play_reports_passing_and_carries() -> void:
	var small: Dictionary = big.duplicate(true)
	small["tuning"].headless.match_s = 20.0
	var play := ScenarioReport.play(small, 1, 1)
	check_eq(play.keys(), ["pass_completion", "outs_per_match", "carry_p90_s", "carry_mean_s", "tackles_per_match"], "keys")
	check(play.pass_completion > 0.0 and play.pass_completion <= 1.0, "completion in range: %s" % play.pass_completion)
	check(play.carry_p90_s >= play.carry_mean_s * 0.5 and play.carry_p90_s < 20.0, "carry times plausible")
