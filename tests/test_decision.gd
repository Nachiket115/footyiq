extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const Decision = preload("res://core/decision.gd")

var cfg := Config.load_all("res://config")
var t: Dictionary = cfg["tuning"]


func _snap(players: Array) -> PitchSnapshot:
	var snap := PitchSnapshot.new()
	snap.pitch = {"length": 40.0, "width": 25.0, "goal_width": 3.0}
	for i in players.size():
		snap.players.append({"id": i, "team": players[i][0], "role": players[i][1], "pos": players[i][2], "vel": Vector2.ZERO, "facing": 0.0})
	snap.owner_id = 0
	snap.ball_pos = players[0][2]
	return snap


func _kinds(choices: Array) -> Array:
	return choices.map(func(c: Dictionary) -> String: return c.kind)


func test_options_name_one_pass_per_direction_plus_dribble() -> void:
	var choices := Decision.options(_snap([
		[0, "cm", Vector2(-5.0, 0.0)],
		[0, "rw", Vector2(5.0, 8.0)],
		[0, "cf", Vector2(9.0, -2.0)],
		[0, "cb", Vector2(-14.0, 0.0)],
		[0, "rcm", Vector2(-5.0, 9.0)],
		[1, "cb", Vector2(18.0, 10.0)],
	]), 0, 1, t)
	check_eq(_kinds(choices), ["through", "square", "back", "dribble"], "one option per kind, in a fixed order, no shot from distance")
	check(choices[0].label in ["Through pass to RW", "Through pass to CF"], "the forward pass names its receiver: %s" % choices[0].label)
	check_eq(choices[2].label, "Back pass to CB", "back pass label")


func test_blocked_pass_is_not_offered_and_shot_appears_in_range() -> void:
	var choices := Decision.options(_snap([
		[0, "cf", Vector2(12.0, 0.0)],
		[0, "cm", Vector2(0.0, 0.0)],
		[1, "cb", Vector2(5.0, 0.0)],
		[1, "gk", Vector2(19.0, 0.0)],
	]), 0, 1, t)
	check_eq(_kinds(choices), ["shoot", "dribble"], "pass through a defender is left out; shot is on")


func test_verdict_compares_the_choice_with_the_best_option() -> void:
	var choices := [
		{"kind": "through", "target_id": 4, "value": 1.4, "label": "Through pass to RW"},
		{"kind": "back", "target_id": 2, "value": 0.6, "label": "Back pass to CB"},
		{"kind": "dribble", "target_id": -1, "value": 0.9, "label": "Dribble"},
	]
	check_eq(Decision.kind_of(choices, {"type": "pass", "target_id": 2}), "back", "pass to the centre-back is the back pass")
	check_eq(Decision.kind_of(choices, {"type": "shot"}), "shoot", "shot")
	check_eq(Decision.kind_of(choices, {"type": "pass", "target_id": 9}), "other", "a pass to someone not listed")
	check_eq(Decision.verdict(choices, "through"), {"good": true, "text": "Through pass to RW: the best option"}, "best")
	check_eq(Decision.verdict(choices, "back"), {"good": false, "text": "Back pass to CB. Better: through pass to RW"}, "safer but not best")
	check_eq(Decision.verdict(choices, "other").good, false, "an unlisted pass is not the best")
