extends SceneTree

const Config = preload("res://core/config.gd")
const Intent = preload("res://core/intent.gd")
const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const Sim = preload("res://core/sim.gd")
const Tactic = preload("res://core/tactic.gd")
const Roles = preload("res://bots/roles.gd")
const BotBrain = preload("res://bots/bot_brain.gd")
const BotController = preload("res://sim/bot_controller.gd")


func _init() -> void:
	var args := {"matches": "1", "seed": "1", "home": "medium", "away": "medium", "exploit": "", "baseline": "", "drill": ""}
	var raw := OS.get_cmdline_user_args()
	var problems: Array[String] = []
	for i in range(0, raw.size(), 2):
		var key := raw[i].trim_prefix("--")
		if not args.has(key) or i + 1 >= raw.size():
			problems.append("bad argument: %s" % raw[i])
			continue
		args[key] = raw[i + 1]
	var cfg := Config.load_all("res://config")
	problems.append_array(Config.errors)
	if args.drill != "":
		if cfg.get("drills", {}).has(args.drill):
			cfg = Config.for_drill(cfg, args.drill)
		else:
			problems.append("unknown drill: %s" % args.drill)
	for side in ["home", "away"]:
		if not cfg.get("difficulty", {}).has(args[side]):
			problems.append("unknown difficulty: %s" % args[side])
	if args.exploit != "" and exploit_brain(args.exploit) == null:
		problems.append("unknown exploit: %s" % args.exploit)
	if args.baseline != "" and not cfg.get("drills", {}).get(cfg.get("tuning", {}).get("debug", {}).get("drill", ""), {}).get("roles", {}).has(args.baseline):
		problems.append("unknown role: %s" % args.baseline)
	if not (args.matches.is_valid_int() and args.seed.is_valid_int()):
		problems.append("--matches and --seed take whole numbers")
	if not problems.is_empty():
		for problem in problems:
			printerr(problem)
		quit(1)
		return
	if args.baseline != "":
		print(JSON.stringify(baseline(cfg, int(args.seed), args.home, args.away, args.baseline)))
	else:
		print(JSON.stringify(series(cfg, int(args.matches), int(args.seed), args.home, args.away, args.exploit)))
	quit(0)


static func series(cfg: Dictionary, matches: int, first_seed: int, home: String, away: String, exploit := "") -> Dictionary:
	var result := {"matches": matches, "home_wins": 0, "away_wins": 0, "draws": 0, "goals": [0, 0], "passes_completed": [0, 0]}
	var owned := [0, 0]
	var spacing := 0.0
	for i in matches:
		var match := play(cfg, first_seed + i, home, away, exploit)
		var goals: Array = match.goals
		if goals[0] > goals[1]:
			result.home_wins += 1
		elif goals[1] > goals[0]:
			result.away_wins += 1
		else:
			result.draws += 1
		for team in 2:
			result.goals[team] += goals[team]
			result.passes_completed[team] += match.passes[team]
			owned[team] += match.owned[team]
		spacing += match.spacing
	result.home_possession = float(owned[0]) / maxi(1, owned[0] + owned[1])
	result.mean_spacing = spacing / maxi(1, matches)
	return result


static func baseline(cfg: Dictionary, match_seed: int, home: String, away: String, role: String) -> Dictionary:
	var drill: Dictionary = cfg["drills"][cfg["tuning"].debug.drill]
	var frames := []
	play(cfg, match_seed, home, away, "", frames)
	return Tactic.score_role(frames, drill.roles[role], {"player_id": drill.teams[0].find(role), "tuning": cfg["tuning"]})


static func play(cfg: Dictionary, match_seed: int, home: String, away: String, exploit := "", frames: Variant = null) -> Dictionary:
	var t: Dictionary = cfg["tuning"]
	var drill: Dictionary = cfg["drills"][t.debug.drill]
	var sides := [
		BotController.team(cfg, drill, home, "build_up", "mid_block"),
		BotController.team(cfg, drill, away, "build_up", "mid_block", 1),
	]
	if exploit != "":
		sides[0].brain = exploit_brain(exploit)
	var state := Roles.spawn(drill, t)
	Sim.seed_rng(state, match_seed)
	var bots := BotController.new(cfg, sides)
	var rate := int(t.sim.tick_rate)
	var owned := [0, 0]
	var passes := [0, 0]
	var spacing := 0.0
	var samples := 0
	for i in roundi(t.headless.match_s * rate):
		Sim.step(state, bots.commands(state), cfg)
		if frames != null and state.tick % int(t.headless.frame_ticks) == 0:
			frames.append(PitchSnapshot.from_world(state, rate))
		if state.ball.owner_id != -1:
			owned[state.player_by_id(state.ball.owner_id).team] += 1
		for event in state.events:
			if event.type == "receive" and event.from_id != -1:
				var team := state.player_by_id(event.player_id).team
				if state.player_by_id(event.from_id).team == team:
					passes[team] += 1
		if state.tick % rate == 0:
			for player in state.players:
				if player.role == "gk":
					continue
				var nearest := INF
				for mate in state.players:
					if mate.team == player.team and mate.id != player.id and mate.role != "gk":
						nearest = minf(nearest, player.pos.distance_to(mate.pos))
				spacing += nearest
				samples += 1
	return {"goals": state.score.duplicate(), "owned": owned, "passes": passes, "spacing": spacing / maxi(1, samples)}


static func exploit_brain(name: String) -> GDScript:
	return {"always_back": AlwaysBack, "wing_dribble": WingDribble}.get(name)


class AlwaysBack:
	static func decide(snap: PitchSnapshot, role: Dictionary, params: Dictionary) -> Intent:
		var me: Dictionary = snap.players.filter(func(p: Dictionary) -> bool: return p.id == params.self_id)[0]
		if snap.owner_id != me.id:
			return BotBrain.decide(snap, role, params)
		var dir := Roles.attacking_dir(me.team)
		var back := {}
		for mate in snap.players:
			if mate.team == me.team and mate.id != me.id and (mate.pos.x - me.pos.x) * dir < 0.0:
				if back.is_empty() or mate.pos.x * dir < back.pos.x * dir:
					back = mate
		if back.is_empty():
			return BotBrain.decide(snap, role, params)
		return BotBrain.new(snap, role, params)._pass(back)


class WingDribble:
	static func decide(snap: PitchSnapshot, role: Dictionary, params: Dictionary) -> Intent:
		var me: Dictionary = snap.players.filter(func(p: Dictionary) -> bool: return p.id == params.self_id)[0]
		if snap.owner_id != me.id or me.role == "gk":
			return BotBrain.decide(snap, role, params)
		var t: Dictionary = params.tuning
		var dir := Roles.attacking_dir(me.team)
		var goal := Vector2(dir * snap.pitch.length * 0.5, 0.0)
		var intent := Intent.new()
		if me.pos.distance_to(goal) < t.steering.shoot_range:
			intent.action = PlayerCommand.Action.SHOOT
			intent.power = 1.0
			intent.desired_facing = (goal - me.pos).angle()
			return intent
		var wing := Vector2(goal.x - dir * t.headless.wing_depth, snap.pitch.width * 0.5 - t.headless.wing_inset)
		var heading: Vector2 = (wing - me.pos).normalized()
		intent.desired_velocity = heading * t.player.sprint_speed * params.difficulty.speed_factor
		intent.desired_facing = heading.angle()
		return intent
