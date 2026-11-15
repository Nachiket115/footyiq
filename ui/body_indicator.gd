extends Control

var head_yaw := 0.0

var _settings: Dictionary
var _yaw_limit: float


func _init(settings: Dictionary, yaw_limit: float) -> void:
	_settings = settings
	_yaw_limit = yaw_limit
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var s := _settings
	var offset := absf(rad_to_deg(head_yaw))
	var alpha: float = s.max_alpha * smoothstep(s.fade_start_deg, s.fade_full_deg, offset)
	if alpha <= 0.0:
		return
	var color := Color(s.color as String, alpha)
	var faint := Color(s.color as String, alpha * 0.4)
	var half_track: float = size.x * s.track_width_frac * 0.5
	var centre := Vector2(size.x * 0.5, size.y - s.bottom_margin)
	var m: float = s.marker_size
	var w: float = s.line_width
	draw_line(centre - Vector2(half_track, 0.0), centre + Vector2(half_track, 0.0), faint, w * 0.5, true)
	draw_line(centre - Vector2(0.0, m * 0.4), centre + Vector2(0.0, m * 0.4), faint, w * 0.5, true)
	var body := centre + Vector2(-head_yaw / _yaw_limit * half_track, 0.0)
	draw_polyline([body + Vector2(-m * 0.6, m * 0.5), body + Vector2(0.0, -m * 0.5), body + Vector2(m * 0.6, m * 0.5)], color, w, true)
