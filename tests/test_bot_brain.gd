extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const Sim = preload("res://core/sim.gd")
const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const Intent = preload("res://core/intent.gd")
const LaneMath = preload("res://core/lane_math.gd")
const Roles = preload("res://bots/roles.gd")
const BotBrain = preload("res://bots/bot_brain.gd")
const BotController = preload("res://sim/bot_controller.gd")
const HeadlessMatch = preload("res://tools/headless_match.gd")

const Action = PlayerCommand.Action

var cfg := Config.load_all("res://config")
var t: Dictionary = cfg["tuning"]
var drill: Dictionary = cfg["drills"]["5v5"]


func _snap(players: Array, ball: Vector2, owner_id: int) -> PitchSnapshot:
	var snap := PitchSnapshot.new()
	snap.pitch = drill.pitch
	for i in players.size():
		var facing := 0.0 if players[i][0] == 0 else PI
		snap.players.append({"id": i, "team": players[i][0], "role": players[i][1], "pos": players[i][2], "vel": Vector2.ZERO, "facing": facing})
	snap.ball_pos = ball
	snap.owner_id = owner_id
	return snap


func _sides(config: Dictionary) -> Array:
	var side := BotController.team(config, drill, "medium", "build_up", "mid_block")
	return [side, side]


func _decide(snap: PitchSnapshot, id: int, rng_seed := 1) -> Intent:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var params := {"self_id": id, "tuning": t, "difficulty": cfg["difficulty"].medium, "objectives": {"attack": cfg["objectives"].build_up, "defend": cfg["objectives"].mid_block}, "rng": rng}
	return BotBrain.decide(snap, drill.roles[snap.players[id].role], params)


func _follow(snap: PitchSnapshot, id: int, seconds: float) -> Vector2:
	for i in int(seconds / t.bot.decide_interval):
		snap.players[id].pos += _decide(snap, id).desired_velocity * t.bot.decide_interval
	return snap.players[id].pos


func _opponents_of(snap: PitchSnapshot, team: int) -> Array:
	var result := []
	for player in snap.players:
		if player.team != team:
			result.append(player.pos)
	return result


func test_carrier_passes_to_clearly_open_forward_teammate() -> void:
	var snap := _snap([
		[0, "cb", Vector2(-10.0, 0.0)],
		[0, "st", Vector2(0.0, 6.0)],
		[0, "gk", Vector2(-18.8, 0.0)],
		[1, "st", Vector2(-12.5, -1.5)],
		[1, "cb", Vector2(12.0, -6.0)],
	], Vector2(-9.4, 0.0), 0)
	for rng_seed in 20:
		var intent := _decide(snap, 0, rng_seed)
		check_eq(intent.action, Action.PASS, "action with seed %d" % rng_seed)
		check_eq(intent.target_id, 1, "target with seed %d" % rng_seed)
	var intent := _decide(snap, 0)
	check_near(intent.desired_facing, Vector2(10.0, 6.0).angle(), 0.01, "aims at the receiver")
	check(intent.power > 0.0 and intent.power < 1.0, "power scaled to the distance: %s" % intent.power)


func test_carrier_shoots_when_close_and_open() -> void:
	var snap := _snap([
		[0, "st", Vector2(14.0, 0.0)],
		[0, "cb", Vector2(-10.0, 0.0)],
		[1, "gk", Vector2(19.0, 0.4)],
		[1, "cb", Vector2(8.0, 9.0)],
	], Vector2(14.6, 0.0), 0)
	for rng_seed in 20:
		check_eq(_decide(snap, 0, rng_seed).action, Action.SHOOT, "action with seed %d" % rng_seed)
	var intent := _decide(snap, 0)
	check_eq(intent.power, 1.0, "full power")
	check(intent.desired_facing < 0.0, "aims at the side away from the keeper")
	snap.players[3].pos = Vector2(16.0, -0.4)
	check(_decide(snap, 0).action != Action.SHOOT, "no shot through a defender")


func test_off_ball_moves_to_open_lane_point() -> void:
	var snap := _snap([
		[0, "cb", Vector2(-10.0, 0.0)],
		[0, "st", Vector2(4.0, 0.0)],
		[1, "cb", Vector2(-2.0, 0.0)],
	], Vector2(-9.4, 0.0), 0)
	snap.players[1].pos = Roles.anchor(drill.roles["st"], snap, 0)
	var before := LaneMath.lane_openness(snap.players[0].pos, snap.players[1].pos, _opponents_of(snap, 0), t)
	check_eq(before, 0.0, "lane to the anchor starts blocked")
	check(_decide(snap, 1).desired_velocity.length() > 1.0, "moves off the blocked spot")
	var after := LaneMath.lane_openness(snap.players[0].pos, _follow(snap, 1, 4.0), _opponents_of(snap, 0), t)
	check(after > 0.8, "ends where the carrier can find it: openness %s" % after)


func test_defender_presses_inside_trigger_radius() -> void:
	var snap := _snap([
		[0, "cb", Vector2(0.0, 0.0)],
		[0, "st", Vector2(10.0, 4.0)],
		[1, "st", Vector2(cfg["difficulty"].medium.press_radius - 1.0, 1.0)],
	], Vector2(0.6, 0.0), 0)
	var intent := _decide(snap, 2)
	var to_ball: Vector2 = snap.ball_pos - snap.players[2].pos
	check(absf(intent.desired_velocity.angle_to(to_ball)) < 0.05, "runs at the ball")
	check(intent.desired_velocity.length() > t.player.jog_speed, "at a sprint")
	check_eq(intent.action, Action.NONE, "no tackle from out of reach")
	snap.players[2].pos = Vector2(1.9, 0.0)
	check(_decide(snap, 2).desired_velocity.length() > t.player.jog_speed, "does not ease off as it closes in")
	snap.players[2].pos = Vector2(1.4, 0.0)
	check_eq(_decide(snap, 2).action, Action.TACKLE, "tackles in reach")


func test_defender_marks_outside_trigger_radius() -> void:
	var snap := _snap([
		[0, "cb", Vector2(0.0, 0.0)],
		[0, "st", Vector2(10.0, 4.0)],
		[1, "st", Vector2(3.0, 0.0)],
		[1, "cb", Vector2(16.0, -3.0)],
	], Vector2(0.6, 0.0), 0)
	var end := _follow(snap, 3, 5.0)
	var attacker: Vector2 = snap.players[1].pos
	check_near(end.distance_to(attacker), t.bot.mark_distance, 0.5, "settles beside the free attacker")
	check(end.x > attacker.x, "on the goal side")
	check(end.y < attacker.y, "shaded toward the ball")
	check_eq(_decide(snap, 3).action, Action.NONE, "no tackle while marking")


func test_delayed_snapshot_is_reaction_time_old() -> void:
	var quiet: Dictionary = cfg.duplicate(true)
	quiet.difficulty.medium.perception_noise = 0.0
	var state: WorldState = Roles.spawn(drill, t)
	Sim.seed_rng(state, 5)
	var controller := BotController.new(quiet, _sides(quiet))
	var seen_at := {}
	for i in 90:
		seen_at[state.tick] = state.players[9].pos + state.players[9].vel * cfg["difficulty"].medium.reaction_time
		Sim.step(state, controller.commands(state), quiet)
	seen_at[state.tick] = state.players[9].pos
	controller.commands(state)
	var delay: float = cfg["difficulty"].medium.reaction_time
	var old_tick := state.tick - roundi(delay * t.sim.tick_rate)
	var seen: PitchSnapshot = controller.perceive(1)
	check_near(seen.time, state.tick / t.sim.tick_rate - delay, 1e-6, "snapshot time")
	check(seen.players[9].pos.is_equal_approx(seen_at[old_tick]), "another player is placed from where they were and how they moved then")
	check(not seen.players[9].pos.is_equal_approx(state.players[9].pos), "which is not where they are now")
	check_eq(seen.players[1].pos, state.players[1].pos, "the bot knows where it is itself")


func test_perception_noise_grows_with_distance() -> void:
	var state: WorldState = Roles.spawn(drill, t)
	Sim.seed_rng(state, 5)
	var controller := BotController.new(cfg, _sides(cfg))
	var near_error := 0.0
	var far_error := 0.0
	for i in 200:
		controller.commands(state)
		var seen: PitchSnapshot = controller.perceive(1)
		near_error += seen.players[0].pos.distance_to(state.players[0].pos)
		far_error += seen.players[5].pos.distance_to(state.players[5].pos)
	check(far_error > 0.0, "distant players are misjudged")
	check(near_error < far_error, "near %s, far %s" % [near_error, far_error])


func test_gk_stands_between_the_ball_and_the_goal_centre() -> void:
	var snap := _snap([
		[0, "gk", Vector2(-18.8, 0.0)],
		[1, "st", Vector2(-10.0, 6.0)],
	], Vector2(-10.0, 6.0), 1)
	check(_decide(snap, 0).desired_velocity.y > 0.0, "moves toward the ball's side")
	var end := _follow(snap, 0, 4.0)
	var goal := Vector2(-snap.pitch.length * 0.5, 0.0)
	var off_line: float = absf((snap.ball_pos - goal).normalized().cross(end - goal))
	check(off_line < 0.2, "on the line from the ball to the goal centre, off by %.2f" % off_line)
	check(end.x < -18.0, "still near its line: %s" % end)
	snap.ball_pos = Vector2(-19.5, 10.0)
	check_near(_follow(snap, 0, 4.0).y, snap.pitch.goal_width * 0.5, 0.2, "never past the post")


func test_bots_play_a_passing_game() -> void:
	var state: WorldState = Roles.spawn(drill, t)
	Sim.seed_rng(state, 11)
	var controller := BotController.new(cfg, _sides(cfg))
	var passes := 0
	var completed := 0
	for i in 3600:
		Sim.step(state, controller.commands(state), cfg)
		for event in state.events:
			if event.type == "pass":
				passes += 1
			if event.type == "receive" and event.from_id != -1:
				completed += int(state.player_by_id(event.from_id).team == state.player_by_id(event.player_id).team)
	check(passes >= 10, "passes attempted in a minute: %d" % passes)
	check(completed * 2 >= passes, "at least half arrive: %d of %d" % [completed, passes])
	for player in state.players:
		check(player.pos.is_finite(), "player %d position is finite" % player.id)


func test_hard_beats_easy_over_20_matches() -> void:
	var result := HeadlessMatch.series(cfg, 20, 1, "hard", "easy")
	check(result.home_wins > result.away_wins, "hard %d, easy %d, draws %d" % [result.home_wins, result.away_wins, result.draws])
	check(result.goals[0] > result.goals[1], "goals %s" % [result.goals])


func test_exploit_always_back_does_not_beat_medium() -> void:
	var result := HeadlessMatch.series(cfg, 20, 1, "medium", "medium", "always_back")
	check(result.home_wins * 2 < result.matches, "exploit won %d of %d" % [result.home_wins, result.matches])


func test_exploit_wing_dribble_does_not_beat_medium() -> void:
	var result := HeadlessMatch.series(cfg, 20, 1, "medium", "medium", "wing_dribble")
	check(result.home_wins * 2 < result.matches, "exploit won %d of %d" % [result.home_wins, result.matches])


func test_objective_shifts_the_line() -> void:
	var snap := _snap([
		[0, "cb", Vector2(-12.0, 0.0)],
		[1, "st", Vector2(-9.0, 0.0)],
		[1, "cb", Vector2(10.0, 0.0)],
	], Vector2(-11.4, 0.0), 0)
	var lines := {}
	for name: String in ["low_block", "mid_block", "press_high"]:
		var rng := RandomNumberGenerator.new()
		var params := {"self_id": 2, "tuning": t, "difficulty": cfg["difficulty"].medium, "objectives": {"attack": cfg["objectives"].build_up, "defend": cfg["objectives"][name]}, "rng": rng}
		snap.players[2].pos = Vector2(10.0, 0.0)
		for i in 50:
			snap.players[2].pos += BotBrain.decide(snap, drill.roles["cb"], params).desired_velocity * t.bot.decide_interval
		lines[name] = snap.players[2].pos.x
	check(lines.press_high < lines.mid_block and lines.mid_block < lines.low_block, "team 1 lines by objective: %s" % lines)


func test_only_the_nearest_defender_presses() -> void:
	var snap := _snap([
		[0, "cb", Vector2(0.0, 0.0)],
		[1, "st", Vector2(3.0, 0.0)],
		[1, "lm", Vector2(2.5, 3.0)],
	], Vector2(0.6, 0.0), 0)
	var to_ball: Vector2 = snap.ball_pos - snap.players[1].pos
	check(absf(_decide(snap, 1).desired_velocity.angle_to(to_ball)) < 0.05, "nearest one goes to the ball")
	var end := _follow(snap, 2, 4.0)
	check(end.distance_to(snap.ball_pos) > cfg["difficulty"].medium.press_radius, "the other leaves it to him: %s" % end)


func test_defender_keeps_its_zone_when_the_attacker_is_elsewhere() -> void:
	var snap := _snap([
		[0, "cb", Vector2(0.0, 0.0)],
		[0, "st", Vector2(2.0, -11.0)],
		[1, "st", Vector2(3.0, 0.0)],
		[1, "cb", Vector2(13.0, 0.0)],
	], Vector2(0.6, 0.0), 0)
	var zone := Roles.anchor(drill.roles.cb, snap, 1)
	var end := _follow(snap, 3, 5.0)
	check(end.distance_to(zone) < 2.0, "stays in its zone: %s, zone %s" % [end, zone])


func test_teammate_makes_its_run_when_the_trigger_player_has_the_ball() -> void:
	var players := [
		[0, "st", Vector2(4.0, 0.0)],
		[0, "rm", Vector2(-2.0, 7.0)],
		[0, "cb", Vector2(-8.0, 0.0)],
		[1, "cb", Vector2(12.0, 0.0)],
	]
	var fed := _snap(players, Vector2(4.6, 0.0), 0)
	var idle := _snap(players, Vector2(-7.4, 0.0), 2)
	var run := _decide(fed, 1).desired_velocity
	check(run.x > t.player.jog_speed, "the wide player sprints forward when the striker receives: %s" % run)
	check(run.x > _decide(idle, 1).desired_velocity.x + 1.0, "and not when the centre-back has it")



func _decide_at(snap: PitchSnapshot, id: int, press_count: int) -> Intent:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var level: Dictionary = cfg["difficulty"].medium.duplicate()
	level.press_count = press_count
	level.press_radius = 20.0
	var params := {"self_id": id, "tuning": t, "difficulty": level, "objectives": {"attack": cfg["objectives"].build_up, "defend": cfg["objectives"].mid_block}, "rng": rng}
	return BotBrain.decide(snap, drill.roles[snap.players[id].role], params)


func _toward_ball(snap: PitchSnapshot, id: int, press_count: int) -> bool:
	var vel := _decide_at(snap, id, press_count).desired_velocity
	return vel.dot(snap.ball_pos - snap.players[id].pos) > 0.0 and vel.length() > t.player.jog_speed


func test_hard_sends_a_second_presser_but_never_the_last_defender() -> void:
	var players := [
		[1, "st", Vector2(0.0, 0.0)],
		[0, "lm", Vector2(-3.0, 0.0)],
		[0, "rm", Vector2(-5.0, 2.0)],
		[0, "cb", Vector2(-6.0, -1.0)],
	]
	var snap := _snap(players, Vector2(-0.6, 0.0), 0)
	check_eq(_decide_at(snap, 2, 1).action == Action.TACKLE or _toward_ball(snap, 2, 1), false, "one presser: the second nearest holds")
	check(_toward_ball(snap, 2, 2), "two pressers: the second nearest closes down")
	check(not _toward_ball(snap, 3, 3), "the last defender never joins the press")


func test_tackle_rate_sets_how_often_a_presser_in_reach_tackles() -> void:
	var snap := _snap([
		[1, "st", Vector2(0.0, 0.0)],
		[0, "cb", Vector2(-1.0, 0.0)],
	], Vector2(-0.5, 0.0), 0)
	var tackles := {0.0: 0, 0.5: 0, 1.0: 0}
	for rate: float in tackles:
		for rng_seed in 40:
			var rng := RandomNumberGenerator.new()
			rng.seed = rng_seed
			var level: Dictionary = cfg["difficulty"].medium.duplicate()
			level.tackle_rate = rate
			var params := {"self_id": 1, "tuning": t, "difficulty": level, "objectives": {"attack": cfg["objectives"].build_up, "defend": cfg["objectives"].mid_block}, "rng": rng}
			tackles[rate] += int(BotBrain.decide(snap, drill.roles.cb, params).action == Action.TACKLE)
	check_eq([tackles[0.0], tackles[1.0]], [0, 40], "never at 0, always at 1")
	check(tackles[0.5] > 10 and tackles[0.5] < 30, "about half the time at 0.5: %d of 40" % tackles[0.5])
