extends Control

var score: Array = [0, 0]
var seconds := 0.0
var charge := 0.0
var banner := ""
var info := ""
var task := ""
var lines: Array[String] = []
var markers := []

var _s: Dictionary
var _font := ThemeDB.fallback_font


func _init(settings: Dictionary) -> void:
	_s = settings
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var text := Color(_s.text_color as String)
	var shade := Color(_s.shade_color as String)
	var line := "%d  -  %d     %d:%02d" % [score[0], score[1], int(seconds) / 60, int(seconds) % 60]
	var width := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, _s.font_size).x
	var top := Vector2((size.x - width) * 0.5, _s.margin)
	draw_rect(Rect2(top - Vector2(12.0, 6.0), Vector2(width + 24.0, _s.font_size + 16.0)), shade)
	draw_string(_font, top + Vector2(0.0, _s.font_size), line, HORIZONTAL_ALIGNMENT_LEFT, -1, _s.font_size, text)

	draw_string(_font, Vector2(_s.margin, _s.margin + _s.font_size * 0.7), info, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_s.font_size * 0.7), text)

	draw_string(_font, Vector2(_s.margin, _s.margin + _s.font_size * 1.7), task, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_s.font_size * 0.7), Color(_s.you_color as String))

	if charge > 0.0:
		var bar := Rect2((size.x - _s.bar_width) * 0.5, size.y - _s.bar_bottom, _s.bar_width, _s.bar_height)
		draw_rect(bar, shade)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * charge, bar.size.y)), Color(_s.you_color as String))

	if banner != "":
		var big := _font.get_string_size(banner, HORIZONTAL_ALIGNMENT_LEFT, -1, _s.banner_size)
		draw_string(_font, Vector2((size.x - big.x) * 0.5, size.y * 0.4), banner, HORIZONTAL_ALIGNMENT_LEFT, -1, _s.banner_size, text)
		for i in lines.size():
			var wide := _font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _s.font_size).x
			var at := Vector2((size.x - wide) * 0.5, size.y * 0.4 + (i + 1.5) * _s.font_size * 1.4)
			draw_rect(Rect2(at - Vector2(8.0, _s.font_size), Vector2(wide + 16.0, _s.font_size * 1.3)), shade)
			draw_string(_font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _s.font_size, text)

	var m: float = _s.marker_size
	for marker: Array in markers:
		var tip: Vector2 = marker[0]
		draw_colored_polygon([tip, tip + Vector2(-m * 0.7, -m), tip + Vector2(m * 0.7, -m)], Color(_s[marker[1]] as String))
