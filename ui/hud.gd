extends Control

var score: Array = [0, 0]
var seconds := 0.0
var time_left := -1.0
var charge := 0.0
var banner := ""
var role := ""
var positions: Array = []
var title := ""
var goal := ""
var bars: Array = []
var misses: Array = []
var markers := []

var _s: Dictionary
var _teams: Array
var _font := SystemFont.new()
var _k := 1.0


func _init(settings: Dictionary, team_colors: Array) -> void:
	_s = settings
	_teams = team_colors
	_font.font_names = PackedStringArray(settings.fonts)
	_font.font_weight = int(settings.font_weight)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	_k = size.y / _s.reference_height
	_task_card()
	_scoreboard()
	if charge > 0.0:
		var bar := Rect2((size.x - _s.bar_width * _k) * 0.5, size.y - _s.bar_bottom * _k, _s.bar_width * _k, _s.bar_height * _k)
		draw_rect(bar, _c("panel_color"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * charge, bar.size.y)), _c("you_color"))
	if banner != "":
		_result()
	var m: float = _s.marker_size * _k
	for marker: Array in markers:
		var tip: Vector2 = marker[0]
		draw_colored_polygon([tip, tip + Vector2(-m * 0.7, -m), tip + Vector2(m * 0.7, -m)], _c(marker[1]))


func _task_card() -> void:
	var m: float = _s.margin * _k
	var pad := 12.0 * _k
	var y := m
	if title != "":
		var big := int(_s.title_size * _k)
		var small := int(_s.text_size * _k)
		var width := maxf(_width(title, big), _width(goal, small)) + pad * 2.0
		var card := Rect2(m, y, width, big + small + pad * 2.5)
		draw_rect(card, _c("panel_color"))
		draw_rect(Rect2(card.position, Vector2(4.0 * _k, card.size.y)), _c("you_color"))
		_text(Vector2(m + pad, y + pad + big * 0.8), title, big, _c("text_color"))
		_text(Vector2(m + pad, y + pad * 1.5 + big + small * 0.8), goal, small, _c("dim_color"))
		y = card.end.y + 8.0 * _k
	var chip := int(_s.chip_size * _k)
	var x := m
	for i in positions.size():
		var label := "%d  %s" % [i + 1, positions[i]]
		var mine: bool = positions[i] == role
		var box := Rect2(x, y, _width(label, chip) + pad * 1.4, chip * 1.8)
		draw_rect(box, _c("you_color") if mine else _c("panel_color"))
		_text(box.position + Vector2(pad * 0.7, chip * 1.3), label, chip, _c("ink_color") if mine else _c("dim_color"))
		x = box.end.x + 4.0 * _k
	if not positions.has(role) and role != "":
		_text(Vector2(x + pad, y + chip * 1.3), role, chip, _c("you_color"))


func _scoreboard() -> void:
	var big := int(_s.title_size * _k)
	var clock := time_left if time_left >= 0.0 else seconds
	var parts := [str(score[0]), str(score[1]), "%d:%02d" % [int(clock) / 60, int(clock) % 60]]
	var gap := 14.0 * _k
	var flag := 8.0 * _k
	var width := flag * 2.0 + gap * 6.0 + _width(parts[0], big) + _width(parts[1], big) + _width(parts[2], big)
	var board := Rect2((size.x - width) * 0.5, _s.margin * _k, width, big * 1.7)
	draw_rect(board, _c("panel_color"))
	var base := board.position.y + big * 1.25
	var x := board.position.x
	draw_rect(Rect2(x, board.position.y, flag, board.size.y), Color(_teams[0] as String))
	x += flag + gap
	x += _text(Vector2(x, base), parts[0], big, _c("text_color")) + gap
	draw_rect(Rect2(x, board.position.y, flag, board.size.y), Color(_teams[1] as String))
	x += flag + gap
	x += _text(Vector2(x, base), parts[1], big, _c("text_color")) + gap * 2.0
	_text(Vector2(x, base), parts[2], big, _c("you_color") if time_left >= 0.0 and time_left < 5.0 else _c("dim_color"))


func _result() -> void:
	var huge := int(_s.banner_size * _k)
	var row := int(_s.title_size * _k)
	var small := int(_s.text_size * _k)
	var column: float = _s.result_width * _k
	var left := (size.x - column) * 0.5
	var height := huge * 1.3 + bars.size() * row * 1.7 + misses.size() * small * 1.6 + 24.0 * _k
	var top := size.y * 0.28
	draw_rect(Rect2(0.0, top, size.x, height), _c("panel_color"))
	var tone := _c("lost_color") if banner == "LOST" else _c("won_color")
	draw_rect(Rect2(0.0, top, size.x, 4.0 * _k), tone)
	_text(Vector2(left, top + huge * 1.05), banner.capitalize(), huge, tone)
	var y := top + huge * 1.3
	for bar: Array in bars:
		var track := Rect2(left + column * 0.3, y + row * 0.45, column * 0.52, row * 0.5)
		_text(Vector2(left, y + row), bar[0], row, _c("text_color"))
		draw_rect(track, _c("track_color"))
		draw_rect(Rect2(track.position, Vector2(track.size.x * bar[1], track.size.y)), tone)
		var pct := "%d%%" % roundi(bar[1] * 100.0)
		_text(Vector2(left + column - _width(pct, row), y + row), pct, row, _c("text_color"))
		y += row * 1.7
	for miss: String in misses:
		_text(Vector2(left, y + small), miss, small, _c("dim_color"))
		y += small * 1.6


func _text(at: Vector2, text: String, px: int, color: Color) -> float:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
	return _width(text, px)


func _width(text: String, px: int) -> float:
	return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


func _c(key: String) -> Color:
	return Color(_s[key] as String)
