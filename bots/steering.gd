extends RefCounted


static func seek(pos: Vector2, target: Vector2, max_speed: float) -> Vector2:
	return (target - pos).normalized() * max_speed


static func arrive(pos: Vector2, target: Vector2, max_speed: float, slow_radius: float) -> Vector2:
	var offset := target - pos
	return offset.normalized() * max_speed * minf(1.0, offset.length() / slow_radius)


static func separation(pos: Vector2, neighbours: Array, radius: float) -> Vector2:
	var push := Vector2.ZERO
	for other: Vector2 in neighbours:
		var away := pos - other
		var dist := away.length()
		if dist < radius:
			push += (away / dist if dist > 0.0 else Vector2.RIGHT) * (1.0 - dist / radius)
	return push


static func interpose(pos: Vector2, a: Vector2, b: Vector2, max_speed: float, slow_radius: float) -> Vector2:
	return arrive(pos, (a + b) * 0.5, max_speed, slow_radius)


static func blend(parts: Array, weights: Array, max_speed: float) -> Vector2:
	var total := Vector2.ZERO
	for i in parts.size():
		total += parts[i] * weights[i]
	return total.limit_length(max_speed)
