extends RefCounted

const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const Intent = preload("res://core/intent.gd")
const Steering = preload("res://bots/steering.gd")
const Roles = preload("res://bots/roles.gd")

var human_id := -1

var _t: Dictionary
var _teams: Array
var _moving := {}


func _init(cfg: Dictionary, team_params: Array) -> void:
	_t = cfg["tuning"]
	_teams = team_params


func commands(state: WorldState) -> Array:
	var snap: PitchSnapshot = PitchSnapshot.from_world(state, _t.sim.tick_rate)
	var chasers := _chasers(snap)
	var result := []
	for player in state.players:
		if player.id == human_id:
			continue
		var cmd := _intent(snap, snap.players[state.players.find(player)], chasers).to_command(state.tick + 1, player, _t)
		_watch_ball(cmd, player, state.ball)
		result.append(cmd)
	return result


func _chasers(snap: PitchSnapshot) -> Dictionary:
	var best := {}
	var best_dist := {}
	for me in snap.players:
		var dist: float = me.pos.distance_to(snap.ball_pos)
		if me.role != "gk" and dist < best_dist.get(me.team, INF):
			best_dist[me.team] = dist
			best[me.team] = me.id
	return best


func _intent(snap: PitchSnapshot, me: Dictionary, chasers: Dictionary) -> Intent:
	var s: Dictionary = _t.steering
	var jog: float = _t.player.jog_speed
	var dir := Roles.attacking_dir(me.team)
	var intent := Intent.new()
	intent.desired_facing = (snap.ball_pos - me.pos).angle()
	var owner_team := -1
	for other in snap.players:
		if other.id == snap.owner_id:
			owner_team = other.team

	var goal := Vector2(dir * snap.pitch.length * 0.5, 0.0)
	var target: Vector2 = Roles.anchor(_teams[me.team].roles[me.role], snap.ball_pos, snap.pitch, dir)
	var speed := jog
	if snap.owner_id == me.id:
		target = goal
		if me.pos.distance_to(goal) < s.shoot_range:
			intent.action = PlayerCommand.Action.SHOOT
			intent.power = 1.0
	elif chasers.get(me.team) == me.id and owner_team != me.team:
		target = snap.ball_pos
		speed = _t.player.sprint_speed
		if owner_team != -1:
			intent.action = PlayerCommand.Action.TACKLE

	var others := []
	for other in snap.players:
		if other.id != me.id:
			others.append(other.pos)
	var go := Steering.arrive(me.pos, target, speed, s.arrive_radius)
	var apart: Vector2 = Steering.separation(me.pos, others, s.separation_radius) * jog
	var desired := Steering.blend([go, apart], [1.0, s.separation_weight], speed)
	_moving[me.id] = desired.length() > (s.stop_speed if _moving.get(me.id, false) else s.start_speed)
	if _moving[me.id]:
		intent.desired_velocity = desired
	return intent


func _watch_ball(cmd: PlayerCommand, player: WorldState.PlayerState, ball: WorldState.BallState) -> void:
	var offset := Vector2(ball.pos.x, ball.pos.z) - player.pos
	var limit := deg_to_rad(_t.player.head_yaw_limit_deg)
	cmd.look_yaw = clampf(angle_difference(player.body_yaw, offset.angle()), -limit, limit)
	cmd.look_pitch = -atan2(_t.player.eye_height - ball.pos.y, offset.length())
