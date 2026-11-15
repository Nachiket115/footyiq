extends RefCounted

const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")

const EPS := 1e-4


static func apply(player: WorldState.PlayerState, cmd: PlayerCommand, dt: float, p: Dictionary) -> void:
	var yaw_limit := deg_to_rad(p.head_yaw_limit_deg)
	var pitch_limit := deg_to_rad(p.head_pitch_limit_deg)
	var jog: float = p.jog_speed
	var sprint: float = p.sprint_speed
	var move := Vector2(clampf(cmd.move.x, -1.0, 1.0), clampf(cmd.move.y, -1.0, 1.0))
	var strafing: bool = p.lateral_mode == "strafe"

	var pace := clampf(inverse_lerp(jog, sprint, player.vel.length()), 0.0, 1.0)
	var max_turn := deg_to_rad(lerpf(p.turn_rate_jog_deg, p.turn_rate_sprint_deg, pace)) * dt
	var steer := 0.0 if strafing or move.y < 0.0 else move.x * max_turn
	var drag := clampf(cmd.look_yaw - clampf(cmd.look_yaw, -yaw_limit, yaw_limit), -max_turn, max_turn)
	player.body_yaw = wrapf(player.body_yaw + clampf(steer + drag, -max_turn, max_turn), -PI, PI)
	player.head_yaw = clampf(cmd.look_yaw - drag, -yaw_limit, yaw_limit)
	player.head_pitch = clampf(cmd.look_pitch, -pitch_limit, pitch_limit)

	player.sprinting = cmd.sprint and move.y > 0.0
	var facing := Vector2.from_angle(player.body_yaw)
	var forward := move.y * (sprint if player.sprinting else jog)
	if move.y < 0.0:
		forward = move.y * jog * p.backpedal_factor
	var desired := facing * forward
	if strafing:
		desired += Vector2(-facing.y, facing.x) * move.x * jog * p.strafe_factor
	var rate: float = p.accel if desired.length() > player.vel.length() else p.decel
	player.vel = player.vel.move_toward(desired, rate * dt)
	player.pos += player.vel * dt


static func separate(players: Array, radius: float) -> void:
	var min_dist := radius * 2.0
	for i in players.size():
		for j in range(i + 1, players.size()):
			var a: WorldState.PlayerState = players[i]
			var b: WorldState.PlayerState = players[j]
			var delta := b.pos - a.pos
			var dist := delta.length()
			if dist >= min_dist:
				continue
			var push := (delta / dist if dist > EPS else Vector2.RIGHT) * (min_dist - dist) * 0.5
			a.pos -= push
			b.pos += push
