extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const Minimap = preload("res://ui/minimap.gd")

var t: Dictionary = Config.load_all("res://config")["tuning"]


func test_pitch_positions_map_onto_the_minimap_area() -> void:
	var map := Minimap.new(t.hud.minimap, t.visual.team_colors)
	map.state = WorldState.new()
	map.state.pitch = {"length": 100.0, "width": 60.0, "goal_width": 7.0}
	var area := Rect2(10.0, 20.0, 200.0, 120.0)
	check_eq(map.to_map(Vector2.ZERO, area), Vector2(110.0, 80.0), "centre spot")
	check_eq(map.to_map(Vector2(-50.0, -30.0), area), Vector2(10.0, 20.0), "own left corner is the top-left")
	check_eq(map.to_map(Vector2(50.0, 30.0), area), Vector2(210.0, 140.0), "far right corner is the bottom-right")
	map.free()
