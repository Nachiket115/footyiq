extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const Tactic = preload("res://core/tactic.gd")
const HeadlessMatch = preload("res://tools/headless_match.gd")

var cfg := Config.load_all("res://config")
var drill: Dictionary = cfg["drills"]["5v5"]
var params := {"player_id": 0, "tuning": cfg["tuning"]}


func _frame(time: float, me: Vector2, ball: Vector2, owner_id: int) -> PitchSnapshot:
	var snap := PitchSnapshot.new()
	snap.time = time
	snap.pitch = drill.pitch
	var players := [[0, "rm", me], [0, "cb", Vector2(-10.0, 0.0)], [0, "st", Vector2(2.0, 0.0)], [1, "cb", Vector2(15.0, -10.0)]]
	for i in players.size():
		snap.players.append({"id": i, "team": players[i][0], "role": players[i][1], "pos": players[i][2], "vel": Vector2.ZERO, "facing": 0.0})
	snap.ball_pos = ball
	snap.owner_id = owner_id
	snap.last_touch_id = owner_id
	return snap


func _in_zone(time: float, offset := Vector2.ZERO) -> PitchSnapshot:
	var snap := _frame(time, Vector2.ZERO, Vector2(-10.0, 0.0), 1)
	snap.players[0].pos = Tactic.target_zone(drill.roles.rm, "build_up", snap, 1).center + offset
	return snap


func _one_run() -> Dictionary:
	var role: Dictionary = drill.roles.rm.duplicate(true)
	role.triggers = [{"event": "mate_receives", "role": "st", "response": "run_forward", "distance": 3.0, "window_s": 3.0}]
	role.duties = []
	return role


func _run_frames(run_speed: float) -> Array:
	var frames := []
	for i in 10:
		var time := i * 0.5
		var at_striker := time >= 0.5
		var me := Vector2(-6.0 + run_speed * maxf(0.0, time - 0.5), 7.0)
		frames.append(_frame(time, me, Vector2(2.0, 0.0) if at_striker else Vector2(-10.0, 0.0), 2 if at_striker else 1))
	return frames


func test_shipped_tactic_is_valid_and_linked_to_the_drill() -> void:
	check_eq(Tactic.problems("5v5_1-2-1", cfg["tactics"]["5v5_1-2-1"]), [], "problems")
	check(drill.roles.has("st"), "drill roles come from the tactic")
	var broken: Dictionary = cfg["tactics"]["5v5_1-2-1"].duplicate(true)
	broken.roles.st.zones.erase("press")
	broken.roles.st.triggers[0].event = "nope"
	check_eq(Tactic.problems("x", broken).size(), 2, "missing zone and unknown event are both reported")


func test_phase_is_build_up_with_ball_in_own_third() -> void:
	var snap := _frame(0.0, Vector2.ZERO, Vector2(-15.0, 0.0), 1)
	check_eq(Tactic.phase_of_play(snap, 0), "build_up", "team with the ball")
	check_eq(Tactic.phase_of_play(snap, 1), "press", "team without it, ball far upfield for them")
	snap.ball_pos = Vector2(15.0, 0.0)
	check_eq(Tactic.phase_of_play(snap, 0), "final_third", "ball in the attacking third")
	check_eq(Tactic.phase_of_play(snap, 1), "low_block", "defending their own third")
	snap.ball_pos = Vector2.ZERO
	check_eq(Tactic.phase_of_play(snap, 1), "defensive_transition", "defending the middle third")
	snap.owner_id = -1
	snap.last_touch_id = -1
	check_eq(Tactic.phase_of_play(snap, 1), "build_up", "nobody has touched the ball")


func test_target_zone_mirrors_and_follows_the_ball() -> void:
	var snap := _frame(0.0, Vector2.ZERO, Vector2.ZERO, 1)
	var role := {"shift": [0.5, 0.5], "zones": {"build_up": {"center": [-0.25, 0.2], "tolerance": 6.0}}}
	check_eq(Tactic.target_zone(role, "build_up", snap, 1), {"center": Vector2(-10.0, 5.0), "tolerance": 6.0}, "team attacking +x")
	check_eq(Tactic.target_zone(role, "build_up", snap, -1).center, Vector2(10.0, 5.0), "team attacking -x")
	snap.ball_pos = Vector2(4.0, -2.0)
	check_eq(Tactic.target_zone(role, "build_up", snap, 1).center, Vector2(-8.0, 4.0), "shifts with the ball")
	snap.ball_pos = Vector2(0.0, 99.0)
	check_eq(Tactic.target_zone(role, "build_up", snap, 1).center.y, snap.pitch.width * 0.5, "stays on the pitch")


func test_structure_is_1_when_always_in_zone() -> void:
	var score := Tactic.score_role([_in_zone(0.0), _in_zone(0.1), _in_zone(0.2)], drill.roles.rm, params)
	check_eq(score.structure, {"build_up": 1.0}, "structure")


func test_structure_is_0_when_never_in_zone() -> void:
	var far := Vector2(20.0, 0.0)
	var score := Tactic.score_role([_in_zone(0.0, far), _in_zone(0.1, far)], drill.roles.rm, params)
	check_eq(score.structure, {"build_up": 0.0}, "structure")
	var tight := Vector2(0.0, 0.0)
	var crowded := _in_zone(0.0, tight)
	crowded.players[2].pos = crowded.players[0].pos + Vector2(1.0, 0.0)
	check_eq(Tactic.score_role([crowded], drill.roles.rm, params).structure, {"build_up": 0.0}, "in zone but on top of a line mate")
	var marking := _frame(0.0, Vector2(14.0, -9.0), Vector2(8.0, -10.0), 3)
	check_eq(Tactic.score_role([marking], drill.roles.rm, params).structure, {"press": 1.0}, "out of zone but tight on an opponent while defending")
	var loose := _in_zone(0.0, far)
	loose.owner_id = -1
	check_eq(Tactic.score_role([loose], drill.roles.rm, params).structure, {}, "loose ball is not sampled")


func test_run_inside_window_scores() -> void:
	var score := Tactic.score_role(_run_frames(4.0), _one_run(), params)
	check_eq(score.run, {"build_up": 1.0}, "run made with an open lane")
	check_eq(score.missed_triggers, [], "nothing missed")


func test_missed_trigger_listed_with_timestamp() -> void:
	var score := Tactic.score_role(_run_frames(0.0), _one_run(), params)
	check_eq(score.run, {"build_up": 0.0}, "run not made")
	check_eq(score.missed_triggers, [{"t": 0.5, "trigger": "mate_receives", "response": "run_forward"}], "missed list")


func test_no_frames_gives_no_scores() -> void:
	var score := Tactic.score_role([], drill.roles.rm, params)
	check_eq(score, {"missed_triggers": [], "structure": {}, "run": {}, "duty": {}}, "empty result")


func test_bot_baseline_structure_above_0_6() -> void:
	var score := HeadlessMatch.baseline(cfg, 1, "medium", "medium", "rm")
	check(not score.structure.is_empty(), "has structure scores")
	var total := 0.0
	for phase: String in score.structure:
		total += score.structure[phase]
		check(score.structure[phase] > 0.3, "%s structure %.2f" % [phase, score.structure[phase]])
	check(total / score.structure.size() > 0.6, "mean structure over phases %.2f" % (total / score.structure.size()))


func test_run_is_void_when_the_ball_is_lost_inside_the_window() -> void:
	var frames := _run_frames(0.0)
	for snap: PitchSnapshot in frames.slice(3):
		snap.owner_id = 3
		snap.last_touch_id = 3
	var score := Tactic.score_role(frames, _one_run(), params)
	check_eq([score.run, score.missed_triggers], [{}, []], "neither scored nor missed")


func test_every_drill_has_valid_tactics_and_spawns_inside_its_pitch() -> void:
	Config.errors.clear()
	Config.load_all("res://config")
	check_eq(Config.errors, [] as Array[String], "config loads without errors")
	const Roles = preload("res://bots/roles.gd")
	for name: String in cfg["drills"]:
		var own := Config.for_drill(cfg, name)
		var d: Dictionary = own["drills"][name]
		var state := Roles.spawn(d, own["tuning"])
		check_eq(state.players.size(), d.teams[0].size() + d.teams[1].size(), "%s player count" % name)
		for role: String in d.positions:
			check(d.teams[0].has(role), "%s: selectable position %s exists" % [name, role])
		for player in state.players:
			check(absf(player.pos.x) <= d.pitch.length * 0.5 and absf(player.pos.y) <= d.pitch.width * 0.5, "%s %s starts on the pitch" % [name, player.role])
			check(player.pos.x * (1 if player.team == 0 else -1) <= 0.0 or player.role in ["cf", "st", "lw", "rw"], "%s %s starts in its own half: %s" % [name, player.role, player.pos])


func test_drill_overrides_apply_only_to_that_drill() -> void:
	var big := Config.for_drill(cfg, "11v11")
	check_eq(big["tuning"].goal.height, 2.44, "full-size goal")
	check_eq(big["tuning"].debug.drill, "11v11", "drill selected")
	check_eq(cfg["tuning"].goal.height, 2.0, "base config untouched")
	check(big["drills"]["11v11"].team_roles[0].has("dm") and big["drills"]["11v11"].team_roles[1].has("st"), "home plays 4-3-3, away plays 4-4-2")
	check(big["tuning"].goal.dive_reach < big["drills"]["11v11"].pitch.goal_width * 0.5, "a full dive still leaves the corners")
