extends Node

const MOUSE_BUTTONS := {"left": MOUSE_BUTTON_LEFT, "right": MOUSE_BUTTON_RIGHT, "middle": MOUSE_BUTTON_MIDDLE}
const DEADZONE := 0.2

var _mouse_delta := Vector2.ZERO
var _sensitivity: float
var _stick_speed: float


func _init(bindings: Dictionary, camera: Dictionary) -> void:
	_sensitivity = deg_to_rad(camera.look_sensitivity_deg)
	_stick_speed = deg_to_rad(camera.stick_speed_deg)
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		for binding: String in bindings[action]:
			var event := _event(binding)
			if event == null:
				push_error("unknown input binding '%s' for action '%s'" % [binding, action])
			else:
				InputMap.action_add_event(action, event)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not captured and event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif captured and event is InputEventMouseMotion:
		_mouse_delta += event.relative


func take_look(dt: float) -> Vector2:
	var stick := Vector2(Input.get_axis("look_left", "look_right"), Input.get_axis("look_down", "look_up"))
	var look := Vector2(_mouse_delta.x, -_mouse_delta.y) * _sensitivity + stick * _stick_speed * dt
	_mouse_delta = Vector2.ZERO
	return look


func poll() -> Dictionary:
	return {
		"move": Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward")),
		"sprint": Input.is_action_pressed("sprint"),
		"align": Input.is_action_pressed("align"),
		"shoot": Input.is_action_just_pressed("shoot"),
		"lofted": Input.is_action_pressed("lofted"),
		"pass_held": Input.is_action_pressed("pass"),
		"pass_released": Input.is_action_just_released("pass"),
		"trap": Input.is_action_pressed("trap"),
	}


func _event(binding: String) -> InputEvent:
	var parts := binding.split(":")
	if parts.size() < 2:
		return null
	match parts[0]:
		"key":
			var keycode := OS.find_keycode_from_string(parts[1])
			if keycode == KEY_NONE:
				return null
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			return key
		"mouse":
			if not MOUSE_BUTTONS.has(parts[1]):
				return null
			var button := InputEventMouseButton.new()
			button.button_index = MOUSE_BUTTONS[parts[1]]
			return button
		"joy_button":
			var pad := InputEventJoypadButton.new()
			pad.button_index = int(parts[1]) as JoyButton
			return pad
		"joy_axis":
			if parts.size() != 3:
				return null
			var axis := InputEventJoypadMotion.new()
			axis.axis = int(parts[1]) as JoyAxis
			axis.axis_value = float(parts[2])
			return axis
	return null
