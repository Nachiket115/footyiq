extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const HumanController = preload("res://sim/human_controller.gd")
const WorldState = preload("res://core/world_state.gd")

var t: Dictionary = Config.load_all("res://config")["tuning"]
var yaw_limit := deg_to_rad(t.player.head_yaw_limit_deg)

const IDLE := {"move": Vector2.ZERO, "sprint": false, "align": false, "pass_held": false, "pass_released": false, "lob_held": false, "lob_released": false, "shoot_held": false, "shoot_released": false, "trap": false}


func test_look_accumulates_and_pitch_clamps() -> void:
	var controller := HumanController.new(t)
	controller.update_look(Vector2(0.4, 0.2), 0.016)
	controller.update_look(Vector2(0.1, 9.0), 0.016)
	check_near(controller.view_yaw, 0.5, 1e-6, "view yaw")
	check_near(controller.view_pitch, deg_to_rad(t.player.head_pitch_limit_deg), 1e-6, "view pitch")


func test_view_never_passes_the_head_limit() -> void:
	var controller := HumanController.new(t)
	controller.update_look(Vector2(9.0, 0.0), 0.016)
	check_near(controller.view_yaw, yaw_limit, 1e-6, "view yaw clamped")


func test_command_carries_excess_once_then_follows_the_sim() -> void:
	var controller := HumanController.new(t)
	controller.update_look(Vector2(yaw_limit + 0.3, 0.0), 0.016)
	var first: PlayerCommand = controller.build_command(1, 4, IDLE)
	controller.sync(yaw_limit)
	var second: PlayerCommand = controller.build_command(2, 4, IDLE)
	check_near(first.look_yaw, yaw_limit + 0.3, 1e-6, "first command carries the excess")
	check_near(second.look_yaw, yaw_limit, 1e-6, "excess is not carried over")
	check_eq(first.player_id, 4, "player id")
	check_eq(first.tick, 1, "tick")


func test_view_blends_sim_head_change_across_the_tick() -> void:
	var controller := HumanController.new(t)
	controller.update_look(Vector2(1.0, 0.0), 0.016)
	controller.build_command(1, 0, IDLE.merged({"align": true}, true))
	controller.sync(0.9)
	controller.update_look(Vector2.ZERO, 0.016, 0.0)
	check_near(controller.view_yaw, 1.0, 1e-6, "start of tick shows the old head angle")
	controller.update_look(Vector2.ZERO, 0.016, 0.5)
	check_near(controller.view_yaw, 0.95, 1e-6, "halfway")
	controller.update_look(Vector2.ZERO, 0.016, 1.0)
	check_near(controller.view_yaw, 0.9, 1e-6, "end of tick shows the new head angle")


func test_shoot_charges_and_release_shoots_along_the_ground() -> void:
	var controller := HumanController.new(t)
	var tap: PlayerCommand = controller.build_command(1, 0, IDLE.merged({"shoot_released": true, "move": Vector2(0, 1), "sprint": true}, true))
	check_eq(tap.action, PlayerCommand.Action.SHOOT, "action")
	check_near(tap.power, t.kick.shot_power_min, 1e-6, "a tap is the weakest shot")
	check(tap.sprint and not tap.lofted, "sprint carried, no loft")
	check_eq(tap.move, Vector2(0, 1), "move")
	for i in 200:
		check_eq(controller.build_command(i, 0, IDLE.merged({"shoot_held": true}, true)).action, PlayerCommand.Action.NONE, "no action while held")
	check_eq(controller.build_command(201, 0, IDLE.merged({"shoot_released": true}, true)).power, 1.0, "full charge is full power")


func test_lob_button_sends_a_lofted_pass_and_pass_button_a_ground_pass() -> void:
	var controller := HumanController.new(t)
	var ticks := int(t.kick.charge_time * t.sim.tick_rate / 2.0)
	for i in ticks:
		controller.build_command(i, 0, IDLE.merged({"lob_held": true}, true))
	var lob: PlayerCommand = controller.build_command(ticks, 0, IDLE.merged({"lob_released": true}, true))
	check_eq(lob.action, PlayerCommand.Action.PASS, "lob is a pass")
	check(lob.lofted, "in the air")
	check_near(lob.power, 0.5, 0.02, "charged like a pass")
	var ground: PlayerCommand = controller.build_command(ticks + 1, 0, IDLE.merged({"pass_released": true}, true))
	check(ground.action == PlayerCommand.Action.PASS and not ground.lofted, "pass button stays on the ground")


func test_held_pass_charges_and_release_sends_it() -> void:
	var controller := HumanController.new(t)
	var held := IDLE.merged({"pass_held": true}, true)
	var ticks := int(t.kick.charge_time * t.sim.tick_rate / 2.0)
	for i in ticks:
		check_eq(controller.build_command(i, 0, held).action, PlayerCommand.Action.NONE, "no action while held")
	check_near(controller.charge, 0.5, 0.02, "half charge")
	var cmd: PlayerCommand = controller.build_command(ticks, 0, IDLE.merged({"pass_released": true}, true))
	check_eq(cmd.action, PlayerCommand.Action.PASS, "pass on release")
	check_near(cmd.power, 0.5, 0.02, "power")
	check_eq(controller.charge, 0.0, "charge reset")
	for i in 200:
		controller.build_command(i, 0, held)
	check_eq(controller.charge, 1.0, "charge caps at 1")


func test_trap_input_becomes_trap_action() -> void:
	var controller := HumanController.new(t)
	var cmd: PlayerCommand = controller.build_command(1, 0, IDLE.merged({"trap": true}, true))
	check_eq(cmd.action, PlayerCommand.Action.TRAP, "action")


func test_take_over_adopts_the_new_players_head_and_drops_the_charge() -> void:
	var controller := HumanController.new(t)
	controller.update_look(Vector2(1.0, 0.3), 0.016)
	var held := IDLE.duplicate()
	held.pass_held = true
	controller.build_command(1, 4, held)
	controller.take_over(-0.4, 0.1)
	check_eq([controller.view_yaw, controller.view_pitch, controller.charge], [-0.4, 0.1, 0.0], "view and charge")
	var cmd: PlayerCommand = controller.build_command(2, 7, IDLE)
	check_eq([cmd.look_yaw, cmd.look_pitch], [-0.4, 0.1], "next command looks where the new player was looking")


func test_tackle_input_becomes_tackle_action() -> void:
	var controller := HumanController.new(t)
	var input := IDLE.duplicate()
	input.trap = true
	check_eq(controller.build_command(1, 4, input).action, PlayerCommand.Action.TRAP, "trap key alone traps")
	input.tackle = true
	check_eq(controller.build_command(2, 4, input).action, PlayerCommand.Action.TACKLE, "same key tackles when an opponent has the ball")


func _pitch_state() -> WorldState:
	var state := WorldState.new()
	state.pitch = {"length": 40.0, "width": 25.0, "goal_width": 3.0}
	for spec: Array in [[0, "st", Vector2(5.0, 0.0)], [0, "rm", Vector2(13.0, 2.0)], [1, "gk", Vector2(19.0, 0.5)]]:
		var player := WorldState.PlayerState.new()
		player.id = state.players.size()
		player.team = spec[0]
		player.role = spec[1]
		player.pos = spec[2]
		state.players.append(player)
	state.ball.pos = Vector3(5.6, t.ball.radius, 0.0)
	state.ball.owner_id = 0
	return state


func _assisted(controller: HumanController, state: WorldState, input: Dictionary) -> PlayerCommand:
	var cmd: PlayerCommand = controller.build_command(1, 0, IDLE.merged(input, true))
	controller.assist(cmd, state)
	return cmd


func test_chase_movement_is_relative_to_the_camera() -> void:
	var controller := HumanController.new(t)
	var state := _pitch_state()
	var ahead := _assisted(controller, state, {"move": Vector2(0, 1), "sprint": true})
	check(ahead.move.y > 0.9 and absf(ahead.move.x) < 0.01 and ahead.sprint, "up runs away from the camera: %s" % ahead.move)
	check(_assisted(controller, state, {"move": Vector2(1, 0)}).move.x > 0.0, "right turns the player toward screen right")
	controller.orbit(Vector2(PI * 0.5, 0.0))
	check(_assisted(controller, state, {"move": Vector2(0, 1)}).move.x > 0.0, "after the camera orbits, up follows the camera")
	check(_assisted(controller, state, {}).move == Vector2.ZERO, "no input stands still")
	var idle := _assisted(controller, state, {})
	check(idle.look_pitch < 0.0, "eyes stay on the ball so there is no gaze penalty")


func test_assisted_pass_aims_at_the_teammate_near_the_aim() -> void:
	var controller := HumanController.new(t)
	var state := _pitch_state()
	for i in 30:
		_assisted(controller, state, {"pass_held": true, "move": Vector2(0, 1)})
	var cmd := _assisted(controller, state, {"pass_released": true, "move": Vector2(0, 1)})
	check_eq(cmd.target_id, 1, "teammate just off the line is picked")
	check_near(cmd.look_yaw, (state.players[1].pos - Vector2(5.6, 0.0)).angle(), 0.01, "kick is turned onto the teammate")
	check_eq(cmd.move.x, 0.0, "no steering on the kick tick")


func test_assisted_shot_goes_for_the_corner_away_from_the_keeper() -> void:
	var controller := HumanController.new(t)
	var state := _pitch_state()
	var cmd := _assisted(controller, state, {"shoot_released": true, "move": Vector2(0, 1)})
	check(cmd.action == PlayerCommand.Action.SHOOT and cmd.look_yaw < 0.0, "keeper is on the +y side, shot goes to -y: %s" % cmd.look_yaw)
	controller.orbit(Vector2(PI, 0.0))
	var back := _assisted(controller, state, {"shoot_released": true, "move": Vector2(0, 1)})
	check_near(absf(back.look_yaw), deg_to_rad(t.player.head_yaw_limit_deg), 0.01, "facing away from goal there is no assist")
