extends RefCounted

const WorldState = preload("res://core/world_state.gd")
const PitchSnapshot = preload("res://core/pitch_snapshot.gd")
const Tactic = preload("res://core/tactic.gd")


static func attacking_dir(team: int) -> int:
	return 1 if team == 0 else -1


static func anchor(role_data: Dictionary, snap: PitchSnapshot, team: int) -> Vector2:
	return Tactic.target_zone(role_data, Tactic.phase_of_play(snap, team), snap, attacking_dir(team)).center


static func spawn(drill: Dictionary, t: Dictionary) -> WorldState:
	var state := WorldState.new()
	state.pitch = drill.pitch.duplicate(true)
	state.ball.pos = Vector3(0.0, t.ball.radius, 0.0)
	var kickoff := PitchSnapshot.new()
	kickoff.pitch = state.pitch
	for team in drill.teams.size():
		for role: String in drill.teams[team]:
			var player := WorldState.PlayerState.new()
			player.id = state.players.size()
			player.team = team
			player.role = role
			player.pos = anchor(drill.get("team_roles", [drill.roles, drill.roles])[team][role], kickoff, team)
			player.body_yaw = 0.0 if team == 0 else PI
			state.players.append(player)
	return state


static func arrange(state: WorldState, drill: Dictionary, ball: Vector2, team: int, t: Dictionary) -> void:
	var snap := PitchSnapshot.from_world(state, t.sim.tick_rate)
	snap.ball_pos = ball
	snap.owner_id = -1
	var nearest: WorldState.PlayerState
	for player in state.players:
		if player.team == team:
			snap.last_touch_id = player.id
	for player in state.players:
		player.pos = anchor(drill.get("team_roles", [drill.roles, drill.roles])[player.team][player.role], snap, player.team)
		player.vel = Vector2.ZERO
		player.body_yaw = 0.0 if player.team == 0 else PI
		player.head_yaw = 0.0
		if player.team == team and (nearest == null or player.pos.distance_to(ball) < nearest.pos.distance_to(ball)):
			nearest = player
	var feet: Vector2 = nearest.pos + Vector2.from_angle(nearest.body_yaw) * t.dribble.lead_distance
	state.ball.pos = Vector3(feet.x, t.ball.radius, feet.y)
	state.ball.vel = Vector3.ZERO
	state.ball.owner_id = nearest.id
	state.ball.last_touch_id = nearest.id
	state.ball.pass_from_id = -1
	state.ball.pass_target_id = -1

