extends RefCounted

var checks := 0
var failures: Array[String] = []


func check(cond: bool, msg: String = "") -> void:
	checks += 1
	if not cond:
		failures.append(msg)


func check_eq(a: Variant, b: Variant, msg: String = "") -> void:
	check(a == b, "%s: expected %s, got %s" % [msg, b, a])


func check_near(a: float, b: float, eps: float, msg: String = "") -> void:
	check(absf(a - b) <= eps, "%s: expected %s ± %s, got %s" % [msg, b, eps, a])
