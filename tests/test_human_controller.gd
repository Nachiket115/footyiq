extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const PlayerCommand = preload("res://core/player_command.gd")
const HumanController = preload("res://sim/human_controller.gd")

var t: Dictionary = Config.load_all("res://config")["tuning"]
var yaw_limit := deg_to_rad(t.player.head_yaw_limit_deg)

const IDLE := {"move": Vector2.ZERO, "sprint": false, "align": false, "shoot": false, "lofted": false}


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


func test_shoot_input_becomes_shoot_action() -> void:
	var controller := HumanController.new(t)
	var input := IDLE.merged({"shoot": true, "lofted": true, "move": Vector2(0, 1), "sprint": true}, true)
	var cmd: PlayerCommand = controller.build_command(1, 0, input)
	check_eq(cmd.action, PlayerCommand.Action.SHOOT, "action")
	check(cmd.lofted and cmd.sprint, "modifiers")
	check_eq(cmd.move, Vector2(0, 1), "move")
