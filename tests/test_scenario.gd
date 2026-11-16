extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const Roles = preload("res://bots/roles.gd")
const Scenario = preload("res://core/scenario.gd")

var cfg := Config.for_drill(Config.load_all("res://config"), "11v11")
var t: Dictionary = cfg["tuning"]
var drill: Dictionary = cfg["drills"]["11v11"]
var all: Dictionary = cfg["scenarios"]


func _start(name: String) -> Variant:
	var state := Roles.spawn(drill, t)
	var s: Dictionary = all[name]
	Roles.arrange(state, drill, Vector2(s.ball[0] * state.pitch.length, s.ball[1] * state.pitch.width), s.team, t)
	return state


func test_every_scenario_is_valid_and_starts_undecided() -> void:
	for name: String in drill.scenarios:
		check_eq(Scenario.problems(name, all[name], cfg["objectives"]), [] as Array[String], name)
		var state: Variant = _start(name)
		check_eq(state.player_by_id(state.ball.owner_id).team, int(all[name].team), "%s: the right team starts with the ball" % name)
		check_eq(Scenario.outcome(all[name], state, 0.0), "", "%s: not decided at the start" % name)
	check_eq(Scenario.problems("x", {"team": 1, "objectives": [{"attack": "nope", "defend": "low_block"}]}, cfg["objectives"]).size(), 7, "missing keys and unknown objective reported")


func test_arrange_puts_teams_in_their_shape_for_the_ball_position() -> void:
	var state: Variant = _start("build_from_the_back")
	check_eq(state.player_by_id(state.ball.owner_id).role, "gk", "keeper has the ball")
	for player in state.players:
		if player.team == 0 and player.role in ["cb", "rcb"]:
			check(player.pos.x < -state.pitch.length * 0.25, "centre-backs are deep to receive: %s" % player.pos)
		if player.team == 1 and player.role in ["cf", "st"]:
			check(player.pos.x < 0.0, "their forwards are in our half to press: %s" % player.pos)


func test_attacking_scenario_outcomes() -> void:
	var s: Dictionary = all["build_from_the_back"]
	var state: Variant = _start("build_from_the_back")
	check_eq(Scenario.outcome(s, state, s.time_s), "lost", "time runs out")
	state.ball.pos.x = 1.0
	check_eq(Scenario.outcome(s, state, 1.0), "won", "our player has it past halfway")
	state.ball.owner_id = -1
	check_eq(Scenario.outcome(s, state, 1.0), "", "a loose ball past halfway is not yet a win")
	for player in state.players:
		if player.team == 1:
			state.ball.owner_id = player.id
	check_eq(Scenario.outcome(s, state, 1.0), "lost", "they took it")
	state.events.append({"type": "goal", "team": 0})
	check_eq(Scenario.outcome(s, state, 1.0), "won", "a goal for us ends it")


func test_defending_scenario_outcomes() -> void:
	var press: Dictionary = all["press_high"]
	var box: Dictionary = all["defend_the_box"]
	var state: Variant = _start("press_high")
	check_eq(Scenario.outcome(press, state, press.time_s), "lost", "pressing: time up without the ball is a loss")
	check_eq(Scenario.outcome(box, state, box.time_s), "won", "defending the box: holding out is a win")
	state.ball.pos.x = press.deny * state.pitch.length - 1.0
	check_eq(Scenario.outcome(press, state, 1.0), "lost", "they played out past the line")
	state.ball.owner_id = 5
	check_eq(Scenario.outcome(press, state, 1.0), "won", "we won the ball")


func test_result_gives_a_bar_per_score_and_a_line_per_missed_trigger() -> void:
	var score := {"structure": {"build_up": 1.0, "press": 0.5}, "run": {}, "duty": {"press": 0.0}, "missed_triggers": [{"t": 14.2, "trigger": "possession_lost", "response": "run_back"}]}
	check_eq(Scenario.bars(score), [["Shape", 0.75], ["Duties", 0.0]], "bars skip kinds with no samples")
	check_eq(Scenario.misses(score, 10.0), ["Missed at 4 s: run back after possession lost"], "times count from the scenario start")
