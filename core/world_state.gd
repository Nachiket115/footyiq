extends RefCounted

const SCHEMA_VERSION := 1


class PlayerState:
	var id := 0
	var team := 0
	var role := ""
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var body_yaw := 0.0
	var head_yaw := 0.0
	var head_pitch := 0.0
	var sprinting := false
	var control_penalty := 0.0
	var look_away_time := 0.0
	var pitch_up_time := 0.0
	var kick_charge := 0.0


class BallState:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var owner_id := -1
	var last_touch_id := -1
	var pass_from_id := -1
	var pass_target_id := -1


var schema_version := SCHEMA_VERSION
var tick := 0
var players: Array[PlayerState] = []
var ball := BallState.new()
var score: Array[int] = [0, 0]
var rng_state := "0"
var pitch := {}
var events: Array[Dictionary] = []


func player_by_id(id: int) -> PlayerState:
	for player in players:
		if player.id == id:
			return player
	return null


func to_dict() -> Dictionary:
	return _pack(self)


func clone() -> RefCounted:
	var copy: RefCounted = from_dict(to_dict())
	copy.events = events.duplicate(true)
	return copy


static func from_dict(d: Dictionary) -> RefCounted:
	if int(d.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var state := new()
	_unpack(state, d)
	_unpack(state.ball, d.get("ball", {}))
	for player_dict: Dictionary in d.get("players", []):
		var player := PlayerState.new()
		_unpack(player, player_dict)
		state.players.append(player)
	state.score.assign(d.get("score", [0, 0]))
	return state


static func _pack(obj: Object) -> Dictionary:
	var d := {}
	for prop in obj.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.name != "events":
			d[prop.name] = _to_json(obj.get(prop.name))
	return d


static func _to_json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_OBJECT:
			return _pack(value)
		TYPE_ARRAY:
			return value.map(_to_json)
		TYPE_DICTIONARY:
			return value.duplicate(true)
	return value


static func _unpack(obj: Object, d: Dictionary) -> void:
	for prop in obj.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and d.has(prop.name)):
			continue
		var raw: Variant = d[prop.name]
		match typeof(obj.get(prop.name)):
			TYPE_INT:
				obj.set(prop.name, int(raw))
			TYPE_VECTOR2:
				obj.set(prop.name, Vector2(raw[0], raw[1]))
			TYPE_VECTOR3:
				obj.set(prop.name, Vector3(raw[0], raw[1], raw[2]))
			TYPE_DICTIONARY:
				obj.set(prop.name, raw.duplicate(true))
			TYPE_OBJECT, TYPE_ARRAY:
				pass
			_:
				obj.set(prop.name, raw)
