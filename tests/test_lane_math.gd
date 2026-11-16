extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const LaneMath = preload("res://core/lane_math.gd")

var t: Dictionary = Config.load_all("res://config")["tuning"]
var from := Vector2.ZERO
var to := Vector2(20.0, 0.0)


func _snap(players: Array) -> PitchSnapshot:
	var snap := PitchSnapshot.new()
	snap.pitch = {"length": 40.0, "width": 25.0}
	for i in players.size():
		snap.players.append({"id": i, "team": players[i][0], "role": "", "pos": players[i][1], "vel": Vector2.ZERO, "facing": 0.0})
	return snap


func test_empty_lane_is_1() -> void:
	check_eq(LaneMath.lane_openness(from, to, [], t), 1.0, "no opponents")
	check_eq(LaneMath.lane_openness(from, to, [Vector2(10.0, 15.0)], t), 1.0, "opponent far off the lane")


func test_opponent_on_lane_is_0() -> void:
	check_eq(LaneMath.lane_openness(from, to, [Vector2(10.0, 0.0)], t), 0.0, "opponent on the line")


func test_opponent_near_receiver_end_lowers_more_than_near_passer() -> void:
	var near_passer := LaneMath.lane_openness(from, to, [Vector2(2.0, 3.0)], t)
	var near_receiver := LaneMath.lane_openness(from, to, [Vector2(18.0, 3.0)], t)
	check(near_passer > 0.0, "near the passer the lane is partly open: %s" % near_passer)
	check(near_receiver < near_passer, "receiver end %s < passer end %s" % [near_receiver, near_passer])


func test_zero_length_lane_is_finite() -> void:
	var open := LaneMath.lane_openness(from, from, [Vector2(5.0, 0.0)], t)
	check(is_finite(open) and open >= 0.0 and open <= 1.0, "in range: %s" % open)


func test_forward_option_outranks_equal_backward_option() -> void:
	var snap := _snap([[0, Vector2.ZERO], [0, Vector2(10.0, 0.0)], [0, Vector2(-10.0, 0.0)], [1, Vector2(0.0, 8.0)]])
	check(LaneMath.option_value(snap, 0, 1, 1, t) > LaneMath.option_value(snap, 0, 2, 1, t), "forward wins attacking +x")
	check(LaneMath.option_value(snap, 0, 2, -1, t) > LaneMath.option_value(snap, 0, 1, -1, t), "backward wins attacking -x")


func test_rank_options_sorted_and_excludes_passer() -> void:
	var snap := _snap([[0, Vector2.ZERO], [0, Vector2(10.0, 0.0)], [0, Vector2(-10.0, 0.0)], [0, Vector2(6.0, 10.0)], [1, Vector2(5.0, -1.0)]])
	var ranked := LaneMath.rank_options(snap, 0, 1, t)
	check_eq(ranked.size(), 3,"three teammates, no opponent")
	for o in ranked:
		check(o.id != 0 and o.id != 4, "passer and opponent excluded")
	for i in ranked.size() - 1:
		check(ranked[i].value >= ranked[i + 1].value, "sorted high to low")
	check_eq(ranked[0].id, 3, "open forward option first")
	check_eq(ranked[-1].id, 1, "blocked forward option ranks below the open backward one")
	check_eq(ranked.filter(func(o: Dictionary) -> bool: return o.id == 1)[0].openness, 0.0, "blocked lane reports 0 openness")


func test_marker_behind_the_receiver_does_not_close_the_lane() -> void:
	var from := Vector2.ZERO
	var to := Vector2(15.0, 0.0)
	var behind := LaneMath.lane_openness(from, to, [Vector2(17.0, 0.0)], t)
	var in_front := LaneMath.lane_openness(from, to, [Vector2(13.0, 0.0)], t)
	check(behind >= 0.5, "a marker 2 m behind the receiver leaves the pass on: %.2f" % behind)
	check_eq(in_front, 0.0, "a marker 2 m in front of the receiver cuts it out")
	check_eq(LaneMath.lane_openness(from, to, [Vector2(15.3, 0.0)], t), 0.0, "a marker touching the receiver still closes it")
