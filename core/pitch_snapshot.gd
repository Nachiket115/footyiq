extends RefCounted

const WorldState = preload("res://core/world_state.gd")

var time := 0.0
var players: Array[Dictionary] = []
var ball_pos := Vector2.ZERO
var ball_vel := Vector2.ZERO
var ball_height := 0.0
var owner_id := -1
var last_touch_id := -1
var pitch := {}


static func from_world(state: WorldState, tick_rate: float) -> RefCounted:
	var snap := new()
	snap.time = state.tick / tick_rate
	for p in state.players:
		snap.players.append({"id": p.id, "team": p.team, "role": p.role, "pos": p.pos, "vel": p.vel, "facing": p.body_yaw})
	snap.ball_pos = Vector2(state.ball.pos.x, state.ball.pos.z)
	snap.ball_vel = Vector2(state.ball.vel.x, state.ball.vel.z)
	snap.ball_height = state.ball.pos.y
	snap.owner_id = state.ball.owner_id
	snap.last_touch_id = state.ball.last_touch_id
	snap.pitch = state.pitch
	return snap
