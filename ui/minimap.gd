extends Control

const WorldState = preload("res://core/world_state.gd")

var state: WorldState
var you := -1
var view_yaw := 0.0

var _s: Dictionary
var _teams: Array


func _init(settings: Dictionary, team_colors: Array) -> void:
	_s = settings
	_teams = team_colors
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func to_map(pos: Vector2, area: Rect2) -> Vector2:
	var pitch := Vector2(state.pitch.length, state.pitch.width)
	return area.position + (pos / pitch + Vector2(0.5, 0.5)) * area.size


func _draw() -> void:
	if state == null:
		return
	var k: float = size.y / _s.reference_height
	var width: float = size.x * _s.width_frac
	var margin: float = _s.margin * k
	var pad: float = _s.pad * k
	var area := Rect2(size.x - width - margin - pad, margin + pad, width, width * state.pitch.width / state.pitch.length)
	var line := Color(_s.line_color as String)
	var thin: float = maxf(1.0, 1.5 * k)
	draw_rect(area.grow(pad), Color(_s.panel_color as String))
	draw_rect(area, Color(_s.pitch_color as String))
	draw_rect(area, line, false, thin)
	draw_line(Vector2(area.get_center().x, area.position.y), Vector2(area.get_center().x, area.end.y), line, thin)
	draw_arc(area.get_center(), area.size.x * _s.circle_frac, 0.0, TAU, 32, line, thin)
	var box := Vector2(area.size.x * _s.box_depth_frac, area.size.y * _s.box_width_frac)
	for x: float in [area.position.x, area.end.x - box.x]:
		draw_rect(Rect2(x, area.get_center().y - box.y * 0.5, box.x, box.y), line, false, thin)
	var goal: float = area.size.y * state.pitch.goal_width / state.pitch.width
	for x: float in [area.position.x, area.end.x]:
		draw_line(Vector2(x, area.get_center().y - goal * 0.5), Vector2(x, area.get_center().y + goal * 0.5), Color(_s.ball_color as String), thin * 2.5)

	var dot: float = _s.dot * k
	var mine := Color(_s.you_color as String)
	for player in state.players:
		var at := to_map(player.pos, area)
		if player.id == you:
			var reach: float = _s.view_length * k
			var half := deg_to_rad(_s.view_cone_deg) * 0.5
			draw_colored_polygon([at, at + Vector2.from_angle(view_yaw - half) * reach, at + Vector2.from_angle(view_yaw + half) * reach], Color(mine, 0.35))
			draw_circle(at, dot * 1.9, mine)
		draw_circle(at, dot * 1.25, Color(_s.outline_color as String))
		draw_circle(at, dot, Color(_teams[player.team] as String))
	var ball := to_map(Vector2(state.ball.pos.x, state.ball.pos.z), area)
	draw_circle(ball, _s.ball_dot * k * 1.4, Color(_s.outline_color as String))
	draw_circle(ball, _s.ball_dot * k, Color(_s.ball_color as String))
