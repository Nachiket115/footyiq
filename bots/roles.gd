extends RefCounted

const WorldState = preload("res://core/world_state.gd")


static func attacking_dir(team: int) -> int:
	return 1 if team == 0 else -1


static func anchor(role_data: Dictionary, ball_pos: Vector2, pitch: Dictionary, dir: int) -> Vector2:
	var size := Vector2(pitch.length, pitch.width)
	var home := Vector2(role_data.home[0] * dir, role_data.home[1]) * size
	var shift := Vector2(role_data.shift[0], role_data.shift[1])
	return (home + ball_pos * shift).clamp(size * -0.5, size * 0.5)


static func spawn(drill: Dictionary, t: Dictionary) -> WorldState:
	var state := WorldState.new()
	state.pitch = drill.pitch.duplicate(true)
	state.ball.pos = Vector3(0.0, t.ball.radius, 0.0)
	for team in drill.teams.size():
		for role: String in drill.teams[team]:
			var player := WorldState.PlayerState.new()
			player.id = state.players.size()
			player.team = team
			player.role = role
			player.pos = anchor(drill.roles[role], Vector2.ZERO, state.pitch, attacking_dir(team))
			player.body_yaw = 0.0 if team == 0 else PI
			state.players.append(player)
	return state
