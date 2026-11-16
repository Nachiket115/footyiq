extends "res://tests/case.gd"

const Config = preload("res://core/config.gd")
const WorldState = preload("res://core/world_state.gd")
const PlayerBody = preload("res://sim/player_body.gd")

var t: Dictionary = Config.load_all("res://config")["tuning"]


func _shot(z: float, speed: float) -> WorldState.BallState:
	var ball := WorldState.BallState.new()
	ball.pos = Vector3(17.0, t.ball.radius, z)
	ball.vel = Vector3(speed, 0.0, 0.0)
	return ball


func test_keeper_dives_toward_the_side_a_fast_shot_passes() -> void:
	var keeper := WorldState.PlayerState.new()
	keeper.role = "gk"
	keeper.pos = Vector2(19.0, 0.0)
	keeper.body_yaw = PI
	var left := PlayerBody.dive_side(keeper, _shot(0.8, 25.0), t)
	var right := PlayerBody.dive_side(keeper, _shot(-0.8, 25.0), t)
	check(left != 0.0 and right == -left, "opposite sides give opposite dives: %s %s" % [left, right])
	check_eq(left, signf(Vector2(0.0, 0.8).dot(Vector2.from_angle(keeper.body_yaw + PI * 0.5))), "toward the ball, in the keeper's own left and right")
	check_eq(PlayerBody.dive_side(keeper, _shot(0.8, 5.0), t), 0.0, "no dive for a slow ball")
	check_eq(PlayerBody.dive_side(keeper, _shot(0.1, 25.0), t), 0.0, "no dive for a shot straight at the keeper")
	check_eq(PlayerBody.dive_side(keeper, _shot(4.0, 25.0), t), 0.0, "no dive for a shot far out of reach")
	var away := _shot(0.8, 25.0)
	away.vel.x = -25.0
	check_eq(PlayerBody.dive_side(keeper, away, t), 0.0, "no dive when the ball is going away")
	keeper.role = "cb"
	check_eq(PlayerBody.dive_side(keeper, _shot(0.8, 25.0), t), 0.0, "only keepers dive")
