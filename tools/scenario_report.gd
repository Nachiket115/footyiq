extends SceneTree

const Config = preload("res://core/config.gd")
const Sim = preload("res://core/sim.gd")
const Scenario = preload("res://core/scenario.gd")
const Roles = preload("res://bots/roles.gd")
const BotController = preload("res://sim/bot_controller.gd")

const LEVELS := ["easy", "medium", "hard"]


func _init() -> void:
	var args := {"drill": "11v11", "runs": "40", "seed": "1", "matches": "0", "idle": ""}
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
	var drill: Dictionary = cfg.get("drills", {}).get(args.drill, {})
	if drill.get("scenarios", []).is_empty():
		problems.append("drill has no scenarios: %s" % args.drill)
	elif args.idle != "" and not drill.teams[0].has(args.idle):
		problems.append("unknown role: %s" % args.idle)
	if not (args.runs.is_valid_int() and args.seed.is_valid_int() and args.matches.is_valid_int()):
		problems.append("--runs, --seed and --matches take whole numbers")
	if not problems.is_empty():
		for problem in problems:
			printerr(problem)
		quit(1)
		return
	cfg = Config.for_drill(cfg, args.drill)
	print(JSON.stringify({
		"scenarios": scenarios(cfg, int(args.runs), int(args.seed), args.idle),
		"play": play(cfg, int(args.matches), int(args.seed)),
	}))
	quit(0)


static func scenarios(cfg: Dictionary, runs: int, first_seed: int, idle_role := "") -> Dictionary:
	var t: Dictionary = cfg["tuning"]
	var drill: Dictionary = cfg["drills"][t.debug.drill]
	var rate: float = t.sim.tick_rate
	var out := {}
	for name: String in drill.scenarios:
		var s: Dictionary = cfg["scenarios"][name]
		out[name] = {}
		for level: String in LEVELS:
			var wins := 0
			var seconds := 0.0
			var gap := 0.0
			var depth := 0.0
			var width := 0.0
			var samples := 0
			for run in runs:
				var state := Roles.spawn(drill, t)
				Sim.seed_rng(state, first_seed + run)
				Roles.arrange(state, drill, Vector2(s.ball[0] * state.pitch.length, s.ball[1] * state.pitch.width), s.team, t)
				var bots := BotController.new(cfg, [
					BotController.team(cfg, drill, "medium", s.objectives[0].attack, s.objectives[0].defend, 0),
					BotController.team(cfg, drill, level, s.objectives[1].attack, s.objectives[1].defend, 1),
				])
				for player in state.players:
					if player.team == 0 and player.role == idle_role:
						bots.human_id = player.id
				var held := {"team": int(s.team), "tick": state.tick}
				var start := state.tick
				var result := ""
				while result == "":
					Sim.step(state, bots.commands(state), cfg)
					Scenario.track(held, state)
					result = Scenario.outcome(s, state, (state.tick - start) / rate, held, t)
					var owner := state.player_by_id(state.ball.owner_id)
					if state.tick % int(t.headless.sample_ticks) != 0 or owner == null or owner.team != 0 or owner.role == "gk":
						continue
					var nearest := INF
					var low := Vector2(INF, INF)
					var high := Vector2(-INF, -INF)
					for player in state.players:
						if player.team == 1 and player.role != "gk":
							nearest = minf(nearest, player.pos.distance_to(owner.pos))
							low = low.min(player.pos)
							high = high.max(player.pos)
					gap += nearest
					depth += high.x - low.x
					width += high.y - low.y
					samples += 1
				wins += int(result == "won")
				seconds += (state.tick - start) / rate
			var n := maxi(1, samples)
			out[name][level] = {
				"runs": runs, "wins": wins, "win_rate": float(wins) / maxi(1, runs), "mean_s": seconds / maxi(1, runs),
				"press_gap": gap / n, "block_depth": depth / n, "block_width": width / n, "samples": samples,
			}
	return out


static func play(cfg: Dictionary, matches: int, first_seed: int) -> Dictionary:
	if matches <= 0:
		return {}
	var t: Dictionary = cfg["tuning"]
	var drill: Dictionary = cfg["drills"][t.debug.drill]
	var rate: float = t.sim.tick_rate
	var passes := [0, 0]
	var outs := 0
	var tackles := 0
	var carries := []
	for i in matches:
		var state := Roles.spawn(drill, t)
		Sim.seed_rng(state, first_seed + i)
		var bots := BotController.new(cfg, [
			BotController.team(cfg, drill, "medium", "build_up", "mid_block", 0),
			BotController.team(cfg, drill, "medium", "build_up", "mid_block", 1),
		])
		var passer_team := -1
		var carrier := -1
		var since := 0
		for tick in roundi(t.headless.match_s * rate):
			var before := state.player_by_id(state.ball.owner_id)
			Sim.step(state, bots.commands(state), cfg)
			if state.ball.owner_id != carrier:
				if carrier != -1 and state.player_by_id(carrier).role != "gk":
					carries.append((state.tick - since) / rate)
				carrier = state.ball.owner_id
				since = state.tick
			for event in state.events:
				if event.type == "pass" and event.target_id != -1:
					passer_team = state.player_by_id(event.player_id).team
				elif event.type == "out":
					outs += 1
					if passer_team != -1:
						passes[1] += 1
						passer_team = -1
				elif event.type == "receive":
					var who := state.player_by_id(event.player_id)
					tackles += int(before != null and before.team != who.team)
					if passer_team != -1:
						passes[0] += int(who.team == passer_team)
						passes[1] += 1
						passer_team = -1
	carries.sort()
	var total := 0.0
	for carry: float in carries:
		total += carry
	return {
		"pass_completion": float(passes[0]) / maxi(1, passes[1]),
		"outs_per_match": float(outs) / matches,
		"carry_p90_s": carries[int(carries.size() * 0.9)] if not carries.is_empty() else 0.0,
		"carry_mean_s": total / maxi(1, carries.size()),
		"tackles_per_match": float(tackles) / matches,
	}
