extends RefCounted

const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")


static func kick(state: WorldState, cmd: PlayerCommand, t: Dictionary) -> void:
	var player := state.player_by_id(cmd.player_id)
	var ball := state.ball
	if player == null or ball.pos.y > t.player.height:
		return
	if Vector2(ball.pos.x, ball.pos.z).distance_to(player.pos) > t.control.radius:
		return
	var yaw := player.body_yaw + player.head_yaw
	var loft := deg_to_rad(t.kick.loft_angle_deg) if cmd.lofted else 0.0
	var speed: float = t.kick.shot_speed * clampf(cmd.power, 0.0, 1.0)
	ball.vel = Vector3(cos(yaw) * cos(loft), sin(loft), sin(yaw) * cos(loft)) * speed
	ball.owner_id = -1
	ball.last_touch_id = player.id
