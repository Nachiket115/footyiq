extends RefCounted

const MOUSE_BUTTONS := {"left": MOUSE_BUTTON_LEFT, "right": MOUSE_BUTTON_RIGHT}


static func register(bindings: Dictionary) -> void:
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for binding: String in bindings[action]:
			var event := _event(binding)
			if event == null:
				push_error("unknown input binding '%s' for action '%s'" % [binding, action])
			else:
				InputMap.action_add_event(action, event)


static func _event(binding: String) -> InputEvent:
	var parts := binding.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "key" and OS.find_keycode_from_string(parts[1]) != KEY_NONE:
		var key := InputEventKey.new()
		key.physical_keycode = OS.find_keycode_from_string(parts[1])
		return key
	if parts[0] == "mouse" and MOUSE_BUTTONS.has(parts[1]):
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTONS[parts[1]]
		return button
	return null
