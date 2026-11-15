extends "res://tests/case.gd"

const WorldState = preload("res://core/world_state.gd")


func _sample() -> WorldState:
	var state := WorldState.new()
	state.tick = 1234
	state.rng_state = "1234567890123456789"
	state.score = [2, 1]
	state.pitch = {"length": 40.0, "width": 25.0, "boards": false}
	for i in 2:
		var player := WorldState.PlayerState.new()
		player.id = i
		player.team = i
		player.role = "cm"
		player.pos = Vector2(1.1 * i, -3.7)
		player.vel = Vector2(PI / 3.0, 0.1)
		player.body_yaw = 0.3
		player.head_yaw = -1.2
		player.head_pitch = 0.4
		player.sprinting = i == 1
		player.control_penalty = 0.25
		state.players.append(player)
	state.ball.pos = Vector3(0.1, 0.11, -0.3)
	state.ball.vel = Vector3(12.5, 3.3, 1.0 / 3.0)
	state.ball.spin = Vector3(0.0, 4.0, 0.0)
	state.ball.owner_id = 1
	state.ball.last_touch_id = 0
	return state


func test_round_trip_preserves_state() -> void:
	var a := _sample()
	var b: WorldState = WorldState.from_dict(a.to_dict())
	check_eq(b.to_dict(), a.to_dict(), "dict")
	check_eq(typeof(b.tick), TYPE_INT, "tick type")
	check_eq(b.players.size(), 2, "player count")
	check_eq(b.players[1].pos, Vector2(1.1, -3.7), "player pos")
	check_eq(b.players[1].sprinting, true, "sprinting")
	check_eq(b.ball.vel, Vector3(12.5, 3.3, 1.0 / 3.0), "ball vel")
	check_eq(b.score, [2, 1], "score")


func test_dict_survives_json_stringify_parse() -> void:
	var a := _sample()
	var text := JSON.stringify(a.to_dict(), "", false, true)
	var b: WorldState = WorldState.from_dict(JSON.parse_string(text))
	check_eq(b.to_dict(), a.to_dict(), "dict after json")
	check_eq(b.rng_state, "1234567890123456789", "rng state")
	check_eq(typeof(b.ball.owner_id), TYPE_INT, "owner id type")


func test_schema_version_is_1() -> void:
	check_eq(WorldState.new().to_dict()["schema_version"], 1, "schema version")


func test_from_dict_rejects_unknown_version() -> void:
	var d := _sample().to_dict()
	d["schema_version"] = 99
	check_eq(WorldState.from_dict(d), null, "unknown version")
	d.erase("schema_version")
	check_eq(WorldState.from_dict(d), null, "missing version")


func test_clone_is_independent() -> void:
	var a := _sample()
	var b: WorldState = a.clone()
	b.players[0].pos.x += 5.0
	b.ball.pos.y = 9.0
	b.pitch["length"] = 1.0
	b.score[0] = 7
	check_eq(a.players[0].pos, Vector2(0.0, -3.7), "player untouched")
	check_near(a.ball.pos.y, 0.11, 1e-6, "ball untouched")
	check_eq(a.pitch["length"], 40.0, "pitch untouched")
	check_eq(a.score[0], 2, "score untouched")
