extends RefCounted

const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const Intent = preload("res://core/intent.gd")
const Steering = preload("res://bots/steering.gd")
const BotBrain = preload("res://bots/bot_brain.gd")

const Action = PlayerCommand.Action

var human_id := -1

var _t: Dictionary
var _b: Dictionary
var _teams: Array
var _rng: RandomNumberGenerator
var _max_delay := 0
var _history: Array[PitchSnapshot] = []
var _intents := {}
var _drift := {}
var _moving := {}
var _smooth := {}


func _init(cfg: Dictionary, team_params: Array) -> void:
	_t = cfg["tuning"]
	_b = _t.bot
	_teams = team_params
	for team: Dictionary in _teams:
		_max_delay = maxi(_max_delay, roundi(team.difficulty.reaction_time * _t.sim.tick_rate))


static func team(cfg: Dictionary, drill: Dictionary, difficulty: String, attack: String, defend: String) -> Dictionary:
	return {
		"roles": drill.roles,
		"difficulty": cfg["difficulty"][difficulty],
		"objectives": {"attack": cfg["objectives"][attack], "defend": cfg["objectives"][defend]},
		"brain": BotBrain,
	}


func commands(state: WorldState) -> Array:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = hash(state.rng_state)
	_history.append(PitchSnapshot.from_world(state, _t.sim.tick_rate))
	if _history.size() > _max_delay + 1:
		_history.pop_front()
	var every := roundi(_b.decide_interval * _t.sim.tick_rate)
	var result := []
	for player in state.players:
		if player.id == human_id:
			_intents.erase(player.id)
			continue
		if not _intents.has(player.id) or (state.tick + player.id % int(_b.stagger_ticks)) % every == 0:
			var side: Dictionary = _teams[player.team]
			var params := {"self_id": player.id, "tuning": _t, "difficulty": side.difficulty, "objectives": side.objectives, "rng": _rng}
			_intents[player.id] = side.brain.decide(perceive(player.id), side.roles[player.role], params)
		result.append(_command(state, player, _intents[player.id]))
	return result


func perceive(id: int) -> PitchSnapshot:
	var now: PitchSnapshot = _history[-1]
	var me: Dictionary
	for player in now.players:
		if player.id == id:
			me = player
	var diff: Dictionary = _teams[me.team].difficulty
	var old: PitchSnapshot = _history[maxi(0, _history.size() - 1 - roundi(diff.reaction_time * _t.sim.tick_rate))]

	var drift: Array = _drift.get_or_add(id, [])
	var keep: float = _b.noise_keep
	for i in old.players.size() + 1:
		if i == drift.size():
			drift.append(Vector2.ZERO)
		drift[i] = drift[i] * keep + Vector2(_rng.randfn(), _rng.randfn()) * sqrt(1.0 - keep * keep)

	var lag := now.time - old.time
	var seen := PitchSnapshot.new()
	seen.time = old.time
	seen.pitch = old.pitch
	for i in old.players.size():
		var other: Dictionary = old.players[i]
		if other.id == id:
			seen.players.append(me)
			continue
		other = other.duplicate()
		other.pos = _blur(other.pos + other.vel * lag, me.pos, drift[i], diff.perception_noise)
		seen.players.append(other)
	var ball := now if id in [old.owner_id, now.owner_id] else old
	seen.ball_pos = _blur(ball.ball_pos + ball.ball_vel * (now.time - ball.time), me.pos, drift[-1], diff.perception_noise)
	seen.ball_vel = ball.ball_vel
	seen.ball_height = ball.ball_height
	seen.owner_id = ball.owner_id
	seen.last_touch_id = ball.last_touch_id
	return seen


func _blur(pos: Vector2, from: Vector2, drift: Vector2, noise: float) -> Vector2:
	return pos + drift * noise * minf(1.0, from.distance_to(pos) / _b.noise_range)


func _command(state: WorldState, player: WorldState.PlayerState, intent: Intent) -> PlayerCommand:
	var s: Dictionary = _t.steering
	var jog: float = _t.player.jog_speed
	var others := []
	for other in state.players:
		if other.id != player.id:
			others.append(other.pos)
	var apart: Vector2 = Steering.separation(player.pos, others, s.separation_radius) * jog
	var blend := minf(1.0, 1.0 / (s.smooth_s * _t.sim.tick_rate))
	var wanted: Vector2 = _smooth.get(player.id, Vector2.ZERO).lerp(intent.desired_velocity, blend)
	_smooth[player.id] = wanted
	var top: float = _t.player.sprint_speed if wanted.length() > jog else jog
	var desired := Steering.blend([wanted, apart], [1.0, s.separation_weight], top)

	var kicking := intent.action == Action.PASS or intent.action == Action.SHOOT
	var aim := angle_difference(player.body_yaw, intent.desired_facing)
	var to_ball := Vector2(state.ball.pos.x, state.ball.pos.z) - player.pos
	var fire := kicking and state.ball.owner_id == player.id and absf(aim) <= deg_to_rad(_b.kick_cone_deg) \
		and to_ball.dot(Vector2.from_angle(intent.desired_facing)) > 0.0
	if kicking and not fire:
		desired = Vector2.ZERO

	var live := Intent.new()
	live.desired_facing = intent.desired_facing
	live.target_id = intent.target_id
	live.power = intent.power
	if fire or not kicking:
		live.action = intent.action
	_moving[player.id] = desired.length() > (s.stop_speed if _moving.get(player.id, false) else s.start_speed)
	if _moving[player.id]:
		live.desired_velocity = desired

	var cmd := live.to_command(state.tick + 1, player, _t)
	_watch_ball(cmd, player, state.ball)
	if fire:
		cmd.look_yaw = aim
		cmd.look_pitch = 0.0
		cmd.move.x = 0.0
		intent.action = Action.NONE
	return cmd


func _watch_ball(cmd: PlayerCommand, player: WorldState.PlayerState, ball: WorldState.BallState) -> void:
	var offset := Vector2(ball.pos.x, ball.pos.z) - player.pos
	var limit := deg_to_rad(_t.player.head_yaw_limit_deg)
	cmd.look_yaw = clampf(angle_difference(player.body_yaw, offset.angle()), -limit, limit)
	cmd.look_pitch = -atan2(_t.player.eye_height - ball.pos.y, offset.length())
