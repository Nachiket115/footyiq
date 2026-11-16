extends RefCounted

const WorldState = preload("res://core/world_state.gd")
const PlayerCommand = preload("res://core/player_command.gd")

var desired_velocity := Vector2.ZERO
var desired_facing := 0.0
var action := PlayerCommand.Action.NONE
var target_id := -1
var power := 0.0


func to_command(tick: int, player: WorldState.PlayerState, t: Dictionary) -> PlayerCommand:
	var cmd := PlayerCommand.new()
	cmd.tick = tick
	cmd.player_id = player.id
	cmd.action = action
	cmd.target_id = target_id
	cmd.power = power
	var speed := desired_velocity.length()
	var moving: bool = speed > t.steering.stop_speed
	var error := angle_difference(player.body_yaw, desired_velocity.angle() if moving else desired_facing)
	if absf(error) > deg_to_rad(t.steering.turn_deadband_deg if moving else t.steering.stand_turn_deg):
		cmd.move.x = clampf(error * t.steering.turn_gain, -1.0, 1.0)
	if moving:
		cmd.sprint = speed > t.player.jog_speed
		var top: float = t.player.sprint_speed if cmd.sprint else t.player.jog_speed
		cmd.move.y = clampf(speed / top, 0.0, 1.0) * maxf(0.0, cos(error))
	return cmd
