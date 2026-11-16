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
		check_eq(Scenario.outcome(all[name], state, 0.0, {"team": int(all[name].team), "tick": state.tick}, t), "", "%s: not decided at the start" % name)
	check_eq(Scenario.problems("x", {"team": 1, "objectives": [{"attack": "nope", "defend": "low_block"}]}, cfg["objectives"]).size(), 7, "missing keys and unknown objective reported")


func test_arrange_puts_teams_in_their_shape_for_the_ball_position() -> void:
	var state: Variant = _start("build_from_the_back")
	check_eq(state.player_by_id(state.ball.owner_id).role, "gk", "keeper has the ball")
	for player in state.players:
		if player.team == 0 and player.role in ["cb", "rcb"]:
			check(player.pos.x < -state.pitch.length * 0.25, "centre-backs are deep to receive: %s" % player.pos)
		if player.team == 1 and player.role in ["cf", "st"]:
			check(player.pos.x < 0.0, "their forwards are in our half to press: %s" % player.pos)


func _held(state: Variant, team: int, seconds: float) -> Dictionary:
	return {"team": team, "tick": state.tick - int(seconds * t.sim.tick_rate)}


func test_attacking_scenario_outcomes() -> void:
	var s: Dictionary = all["build_from_the_back"]
	var state: Variant = _start("build_from_the_back")
	var ours := _held(state, 0, 5.0)
	check_eq(Scenario.outcome(s, state, s.time_s, ours, t), "lost", "time runs out")
	state.ball.pos.x = 1.0
	check_eq(Scenario.outcome(s, state, 1.0, ours, t), "won", "our player has it past halfway")
	state.ball.owner_id = -1
	check_eq(Scenario.outcome(s, state, 1.0, ours, t), "", "a loose ball past halfway is not yet a win")
	check_eq(Scenario.outcome(s, state, 1.0, _held(state, 1, t.scenario.keep_s - 0.5), t), "", "a touch by them is not a loss yet")
	check_eq(Scenario.outcome(s, state, 1.0, _held(state, 1, t.scenario.keep_s), t), "lost", "they kept it")
	state.events.append({"type": "goal", "team": 0})
	check_eq(Scenario.outcome(s, state, 1.0, ours, t), "won", "a goal for us ends it")


func test_defending_scenario_outcomes() -> void:
	var press: Dictionary = all["press_high"]
	var box: Dictionary = all["defend_the_box"]
	var state: Variant = _start("press_high")
	var theirs := _held(state, 1, 5.0)
	check_eq(Scenario.outcome(press, state, press.time_s, theirs, t), "lost", "pressing: time up without the ball is a loss")
	check_eq(Scenario.outcome(box, state, box.time_s, theirs, t), "won", "defending the box: holding out is a win")
	check_eq(Scenario.outcome(press, state, 1.0, _held(state, 0, 0.5), t), "", "one touch by us is not a win yet")
	check_eq(Scenario.outcome(press, state, 1.0, _held(state, 0, t.scenario.keep_s), t), "won", "we won the ball and kept it")
	state.ball.pos.x = press.deny * state.pitch.length - 1.0
	check_eq(Scenario.outcome(press, state, 1.0, theirs, t), "lost", "they played out past the line")


func test_possession_tracker_only_restarts_when_the_other_team_takes_the_ball() -> void:
	var state: Variant = _start("build_from_the_back")
	var held := {"team": 0, "tick": 0}
	state.tick = 100
	Scenario.track(held, state)
	check_eq(held, {"team": 0, "tick": 0}, "same team keeps its clock")
	state.ball.owner_id = -1
	Scenario.track(held, state)
	check_eq(held.tick, 0, "a loose ball does not restart it")
	for player in state.players:
		if player.team == 1:
			state.ball.owner_id = player.id
	Scenario.track(held, state)
	check_eq(held, {"team": 1, "tick": 100}, "the other team taking it restarts the clock")


func test_result_gives_a_bar_per_score_and_a_line_per_missed_trigger() -> void:
	var score := {"structure": {"build_up": 1.0, "press": 0.5}, "run": {}, "duty": {"press": 0.0}, "missed_triggers": [{"t": 14.2, "trigger": "possession_lost", "response": "run_back"}]}
	check_eq(Scenario.bars(score), [["Shape", 0.75], ["Duties", 0.0]], "bars skip kinds with no samples")
	check_eq(Scenario.misses(score, 10.0), ["Missed at 4 s: run back after possession lost"], "times count from the scenario start")


func test_defend_the_box_is_lost_when_they_carry_it_to_the_byline_zone() -> void:
	var box: Dictionary = all["defend_the_box"]
	var state: Variant = _start("defend_the_box")
	var theirs := _held(state, 1, 5.0)
	state.ball.pos.x = box.deny * state.pitch.length - 1.0
	check_eq(Scenario.outcome(box, state, 1.0, theirs, t), "lost", "their carrier is inside the line")
	state.ball.owner_id = -1
	check_eq(Scenario.outcome(box, state, 1.0, theirs, t), "", "a loose ball there is not a loss")
