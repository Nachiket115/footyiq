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
			player.pos = anchor(drill.roles[role], kickoff, team)
			player.body_yaw = 0.0 if team == 0 else PI
			state.players.append(player)
	return state
